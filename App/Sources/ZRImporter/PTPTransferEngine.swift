import Foundation
@preconcurrency import ImageCaptureCore

struct PTPObject {
    let handle: UInt32
    let storageID: UInt32
    let format: UInt16
    let reportedSize: UInt32
    var resolvedSize: UInt64?
    var supportsNikonPartialObjectEx: Bool
    let filename: String
    let captureDateString: String
    let modificationDateString: String

    var size: UInt64 { resolvedSize ?? UInt64(reportedSize) }
    var hasKnownSize: Bool { resolvedSize != nil || reportedSize < UInt32.max }
    var needsNikonExtendedTransfer: Bool { reportedSize == UInt32.max }
    var canDownload: Bool { !needsNikonExtendedTransfer || (resolvedSize != nil && supportsNikonPartialObjectEx) }
    var fileExtension: String { (filename as NSString).pathExtension.uppercased() }
    var createdAt: Date? { Self.ptpDateFormatter.date(from: captureDateString) }
    var modifiedAt: Date? { Self.ptpDateFormatter.date(from: modificationDateString) }

    private static let ptpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()
}

private struct PTPCommandResponse {
    let code: UInt16
    let transactionID: UInt32
    let parameters: [UInt32]

    var ok: Bool { code == 0x2001 }
    var incompleteTransfer: Bool { code == 0x2007 }
    var codeHex: String { String(format: "0x%04X", code) }
}

enum PTPTransferError: Error, LocalizedError {
    case cameraDoesNotAcceptPTP
    case invalidResponse(String)
    case transferFailed(String)
    case fileBeyondPTPLimit(String)
    case nikonExtendedTransferUnavailable(String)
    case cannotCreateFile(String)
    case sizeMismatch(String)

    var errorDescription: String? {
        switch self {
        case .cameraDoesNotAcceptPTP:
            return "Die Kamera akzeptiert keine PTP-Kommandos."
        case .invalidResponse(let message):
            return message
        case .transferFailed(let message):
            return message
        case .fileBeyondPTPLimit(let filename):
            return "\(filename) ist groesser als der 32-bit-PTP-Downloadpfad der Kamera."
        case .nikonExtendedTransferUnavailable(let filename):
            return "\(filename): Nikon-64-bit-Transfer ist fuer diese Datei nicht verfuegbar."
        case .cannotCreateFile(let path):
            return "Zieldatei konnte nicht angelegt werden: \(path)"
        case .sizeMismatch(let message):
            return message
        }
    }
}

final class PTPTransferEngine {
    private var transactionID: UInt32 = 1
    private let nikonGetObjectSizeCode: UInt16 = 0x9421
    private let nikonGetPartialObjectExCode: UInt16 = 0x9431

    func listObjects(on camera: ICCameraDevice) async throws -> [PTPObject] {
        guard camera.capabilities.contains("ICCameraDeviceCanAcceptPTPCommands") else {
            throw PTPTransferError.cameraDoesNotAcceptPTP
        }

        let operations = (try? await supportedOperations(on: camera)) ?? []
        let supportsNikonObjectSize = operations.contains(nikonGetObjectSizeCode)
        let supportsNikonPartialObjectEx = operations.contains(nikonGetPartialObjectExCode)

        let storageIDs = try await send(camera, code: 0x1004, parameters: []).data.ptpUInt32Array()
        var handles = Set<UInt32>()

        for storageID in storageIDs {
            let result = try await send(camera, code: 0x1007, parameters: [storageID, 0, 0])
            if result.response.ok {
                handles.formUnion(result.data.ptpUInt32Array())
            }
        }

        var objects: [PTPObject] = []
        for handle in handles.sorted() {
            let result = try await send(camera, code: 0x1008, parameters: [handle])
            if result.response.ok, var object = PTPObject.parse(handle: handle, data: result.data) {
                if object.reportedSize == UInt32.max, supportsNikonObjectSize {
                    object.resolvedSize = try? await nikonObjectSize(handle: object.handle, on: camera)
                    object.supportsNikonPartialObjectEx = supportsNikonPartialObjectEx
                }
                objects.append(object)
            }
        }

        return objects
    }

    func download(
        object: PTPObject,
        from camera: ICCameraDevice,
        to destinationURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard object.hasKnownSize else {
            throw PTPTransferError.fileBeyondPTPLimit(object.filename)
        }

        let expectedSize = object.size
        if object.needsNikonExtendedTransfer && !object.canDownload {
            throw PTPTransferError.nikonExtendedTransferUnavailable(object.filename)
        }

        let folder = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let partialURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).partial")

        if FileManager.default.fileExists(atPath: partialURL.path) {
            try FileManager.default.removeItem(at: partialURL)
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        guard FileManager.default.createFile(atPath: partialURL.path, contents: nil) else {
            throw PTPTransferError.cannotCreateFile(partialURL.path)
        }

        let fileHandle = try FileHandle(forWritingTo: partialURL)
        defer { try? fileHandle.close() }

        if object.needsNikonExtendedTransfer {
            try await downloadWithNikonPartialObjectEx(
                object: object,
                from: camera,
                expectedSize: expectedSize,
                fileHandle: fileHandle,
                progress: progress
            )
        } else {
            try await downloadWithStandardPartialObject(
                object: object,
                from: camera,
                expectedSize: expectedSize,
                fileHandle: fileHandle,
                progress: progress
            )
        }

        try fileHandle.close()
        let finalSize = ((try? FileManager.default.attributesOfItem(atPath: partialURL.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard finalSize == expectedSize else {
            throw PTPTransferError.sizeMismatch("\(object.filename): Importgroesse stimmt nicht. Erwartet \(expectedSize) Bytes, geschrieben \(finalSize) Bytes.")
        }

        try FileManager.default.moveItem(at: partialURL, to: destinationURL)

        var attributes: [FileAttributeKey: Any] = [:]
        if let createdAt = object.createdAt {
            attributes[.creationDate] = createdAt
        }
        if let modifiedAt = object.modifiedAt {
            attributes[.modificationDate] = modifiedAt
        }
        if !attributes.isEmpty {
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: destinationURL.path)
        }
    }

    private func downloadWithStandardPartialObject(
        object: PTPObject,
        from camera: ICCameraDevice,
        expectedSize: UInt64,
        fileHandle: FileHandle,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let chunkSize: UInt32 = 32 * 1_024 * 1_024
        var offset: UInt64 = 0

        while offset < expectedSize {
            let preferredChunkSize: UInt32 = offset == 0 ? 1 * 1_024 * 1_024 : chunkSize
            let requestLength = UInt32(Swift.min(UInt64(preferredChunkSize), expectedSize - offset))
            let result = try await send(camera, code: 0x101B, parameters: [object.handle, UInt32(offset), requestLength])

            if !result.response.ok {
                throw PTPTransferError.transferFailed("\(object.filename): PTP \(result.response.codeHex) bei Offset \(offset).")
            }

            try writeChunk(result.data, object: object, offset: &offset, expectedSize: expectedSize, requestLength: UInt64(requestLength), fileHandle: fileHandle, progress: progress)
        }
    }

    private func downloadWithNikonPartialObjectEx(
        object: PTPObject,
        from camera: ICCameraDevice,
        expectedSize: UInt64,
        fileHandle: FileHandle,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let chunkSize: UInt64 = 32 * 1_024 * 1_024
        var offset: UInt64 = 0

        while offset < expectedSize {
            let requestLength = Swift.min(chunkSize, expectedSize - offset)
            let result = try await send(
                camera,
                code: nikonGetPartialObjectExCode,
                parameters: [
                    object.handle,
                    UInt32(offset & 0xFFFF_FFFF),
                    UInt32(offset >> 32),
                    UInt32(requestLength & 0xFFFF_FFFF),
                    UInt32(requestLength >> 32)
                ]
            )

            if !result.response.ok {
                throw PTPTransferError.transferFailed("\(object.filename): Nikon PTP \(result.response.codeHex) bei Offset \(offset).")
            }

            let responseLength = result.response.parameters.count >= 2
                ? UInt64(result.response.parameters[0]) | (UInt64(result.response.parameters[1]) << 32)
                : UInt64(result.data.count)
            let expectedChunkLength = responseLength == 0 ? requestLength : responseLength

            try writeChunk(result.data, object: object, offset: &offset, expectedSize: expectedSize, requestLength: expectedChunkLength, fileHandle: fileHandle, progress: progress)
        }
    }

    private func writeChunk(
        _ data: Data,
        object: PTPObject,
        offset: inout UInt64,
        expectedSize: UInt64,
        requestLength: UInt64,
        fileHandle: FileHandle,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        if data.isEmpty {
            throw PTPTransferError.transferFailed("\(object.filename): leerer Chunk bei Offset \(offset).")
        }

        try fileHandle.write(contentsOf: data)
        offset += UInt64(data.count)

        progress(Swift.min(1, Double(offset) / Double(expectedSize)))

        if UInt64(data.count) < requestLength && offset < expectedSize {
            throw PTPTransferError.transferFailed("\(object.filename): kurzer Chunk bei Offset \(offset), erwartet \(requestLength), bekommen \(data.count).")
        }
    }

    private func supportedOperations(on camera: ICCameraDevice) async throws -> Set<UInt16> {
        let result = try await send(camera, code: 0x1001, parameters: [])
        guard result.response.ok else {
            throw PTPTransferError.transferFailed("GetDeviceInfo fehlgeschlagen: \(result.response.codeHex).")
        }
        return Set(try result.data.ptpOperationsSupported())
    }

    private func nikonObjectSize(handle: UInt32, on camera: ICCameraDevice) async throws -> UInt64 {
        let result = try await send(camera, code: nikonGetObjectSizeCode, parameters: [handle])
        guard result.response.ok else {
            throw PTPTransferError.transferFailed("Nikon GetObjectSize fehlgeschlagen: \(result.response.codeHex).")
        }
        guard result.data.count >= 8 else {
            throw PTPTransferError.invalidResponse("Nikon GetObjectSize lieferte zu wenige Daten.")
        }
        return result.data.ptpUInt64(at: 0)
    }

    private func send(_ camera: ICCameraDevice, code: UInt16, parameters: [UInt32], outData: Data? = nil) async throws -> (data: Data, response: PTPCommandResponse) {
        let command = makeCommand(code: code, parameters: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                camera.requestSendPTPCommand(command, outData: outData) { data, responseData, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    do {
                        let response = try responseData.ptpResponse()
                        continuation.resume(returning: (data, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func makeCommand(code: UInt16, parameters: [UInt32]) -> Data {
        let id = transactionID
        transactionID += 1

        var data = Data()
        data.appendPTPLittleEndian(UInt32(12 + parameters.count * 4))
        data.appendPTPLittleEndian(UInt16(1))
        data.appendPTPLittleEndian(code)
        data.appendPTPLittleEndian(id)
        for parameter in parameters {
            data.appendPTPLittleEndian(parameter)
        }
        return data
    }
}

private extension PTPObject {
    static func parse(handle: UInt32, data: Data) -> PTPObject? {
        guard data.count >= 53 else { return nil }

        var offset = 52
        let filename = data.ptpString(at: offset)
        offset += filename.bytesRead
        let captureDate = data.ptpString(at: offset)
        offset += captureDate.bytesRead
        let modificationDate = data.ptpString(at: offset)

        return PTPObject(
            handle: handle,
            storageID: data.ptpUInt32(at: 0),
            format: data.ptpUInt16(at: 4),
            reportedSize: data.ptpUInt32(at: 8),
            resolvedSize: nil,
            supportsNikonPartialObjectEx: false,
            filename: filename.value,
            captureDateString: captureDate.value,
            modificationDateString: modificationDate.value
        )
    }
}

private extension Data {
    mutating func appendPTPLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func ptpUInt8(at offset: Int) -> UInt8 {
        guard offset < count else { return 0 }
        return self[offset]
    }

    func ptpUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return subdata(in: offset..<(offset + 2)).withUnsafeBytes { UInt16(littleEndian: $0.load(as: UInt16.self)) }
    }

    func ptpUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<(offset + 4)).withUnsafeBytes { UInt32(littleEndian: $0.load(as: UInt32.self)) }
    }

    func ptpUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return subdata(in: offset..<(offset + 8)).withUnsafeBytes { UInt64(littleEndian: $0.load(as: UInt64.self)) }
    }

    func ptpUInt32Array() -> [UInt32] {
        guard count >= 4 else { return [] }
        let itemCount = Int(ptpUInt32(at: 0))
        var result: [UInt32] = []
        result.reserveCapacity(itemCount)

        for index in 0..<itemCount {
            let offset = 4 + index * 4
            guard offset + 4 <= count else { break }
            result.append(ptpUInt32(at: offset))
        }

        return result
    }

    func ptpUInt16Array(at offset: Int) throws -> ([UInt16], Int) {
        guard offset + 4 <= count else {
            throw PTPTransferError.invalidResponse("PTP-Array war zu kurz.")
        }
        let itemCount = Int(ptpUInt32(at: offset))
        var result: [UInt16] = []
        result.reserveCapacity(itemCount)
        let dataOffset = offset + 4

        for index in 0..<itemCount {
            let itemOffset = dataOffset + index * 2
            guard itemOffset + 2 <= count else {
                throw PTPTransferError.invalidResponse("PTP-UInt16-Array war zu kurz.")
            }
            result.append(ptpUInt16(at: itemOffset))
        }

        return (result, 4 + itemCount * 2)
    }

    func ptpString(at offset: Int) -> (value: String, bytesRead: Int) {
        guard offset < count else { return ("", 0) }
        let characterCount = Int(ptpUInt8(at: offset))
        if characterCount == 0 { return ("", 1) }

        var scalars = String.UnicodeScalarView()
        for index in 0..<Swift.max(0, characterCount - 1) {
            let unitOffset = offset + 1 + index * 2
            guard unitOffset + 2 <= count else { break }
            if let scalar = UnicodeScalar(Int(ptpUInt16(at: unitOffset))) {
                scalars.append(scalar)
            }
        }

        return (String(scalars), 1 + characterCount * 2)
    }

    func ptpOperationsSupported() throws -> [UInt16] {
        var offset = 0
        offset += 2 // StandardVersion
        offset += 4 // VendorExtensionID
        offset += 2 // VendorExtensionVersion
        offset += ptpString(at: offset).bytesRead
        offset += 2 // FunctionalMode
        return try ptpUInt16Array(at: offset).0
    }

    func ptpResponse() throws -> PTPCommandResponse {
        guard count >= 12 else {
            throw PTPTransferError.invalidResponse("PTP-Antwort war zu kurz.")
        }

        let length = Swift.min(Int(ptpUInt32(at: 0)), count)
        let containerType = ptpUInt16(at: 4)
        guard containerType == 3 else {
            throw PTPTransferError.invalidResponse("Unerwarteter PTP-Container \(containerType).")
        }

        let code = ptpUInt16(at: 6)
        let transactionID = ptpUInt32(at: 8)
        var parameters: [UInt32] = []

        for offset in stride(from: 12, to: length, by: 4) where offset + 4 <= count {
            parameters.append(ptpUInt32(at: offset))
        }

        return PTPCommandResponse(code: code, transactionID: transactionID, parameters: parameters)
    }
}
