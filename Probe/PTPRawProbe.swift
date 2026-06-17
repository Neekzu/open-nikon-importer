import Foundation
import ImageCaptureCore

struct PTPResponse {
    let code: UInt16
    let transactionID: UInt32
    let parameters: [UInt32]

    var ok: Bool { code == 0x2001 }
    var codeHex: String { String(format: "0x%04X", code) }
}

enum PTPParseError: Error, CustomStringConvertible {
    case shortData(String)
    case badContainer(String)

    var description: String {
        switch self {
        case .shortData(let value): return "shortData(\(value))"
        case .badContainer(let value): return "badContainer(\(value))"
        }
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func leUInt8(at offset: Int) throws -> UInt8 {
        guard offset + 1 <= count else { throw PTPParseError.shortData("UInt8 @ \(offset)") }
        return self[offset]
    }

    func leUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else { throw PTPParseError.shortData("UInt16 @ \(offset)") }
        return subdata(in: offset..<(offset + 2)).withUnsafeBytes { UInt16(littleEndian: $0.load(as: UInt16.self)) }
    }

    func leUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else { throw PTPParseError.shortData("UInt32 @ \(offset)") }
        return subdata(in: offset..<(offset + 4)).withUnsafeBytes { UInt32(littleEndian: $0.load(as: UInt32.self)) }
    }

    func ptpUInt32Array() throws -> [UInt32] {
        let itemCount = Int(try leUInt32(at: 0))
        var result: [UInt32] = []
        result.reserveCapacity(itemCount)
        for index in 0..<itemCount {
            result.append(try leUInt32(at: 4 + index * 4))
        }
        return result
    }

    func ptpUInt16Array(at offset: Int = 0) throws -> ([UInt16], Int) {
        let itemCount = Int(try leUInt32(at: offset))
        var result: [UInt16] = []
        result.reserveCapacity(itemCount)
        let dataOffset = offset + 4
        for index in 0..<itemCount {
            result.append(try leUInt16(at: dataOffset + index * 2))
        }
        return (result, 4 + itemCount * 2)
    }

    func ptpString(at start: Int) throws -> (String, Int) {
        let charCount = Int(try leUInt8(at: start))
        if charCount == 0 { return ("", 1) }
        let byteCount = 1 + charCount * 2
        guard start + byteCount <= count else { throw PTPParseError.shortData("PTPString @ \(start)") }

        var scalars = String.UnicodeScalarView()
        for index in 0..<Swift.max(0, charCount - 1) {
            let unit = try leUInt16(at: start + 1 + index * 2)
            if let scalar = UnicodeScalar(Int(unit)) {
                scalars.append(scalar)
            }
        }
        return (String(scalars), byteCount)
    }

    func hexPrefix(_ maxBytes: Int = 64) -> String {
        prefix(maxBytes).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

struct PTPObjectInfo {
    let handle: UInt32
    let storageID: UInt32
    let format: UInt16
    let size: UInt32
    let parent: UInt32
    let filename: String
    let captureDate: String
    let modificationDate: String

    static func parse(handle: UInt32, data: Data) throws -> PTPObjectInfo {
        let storageID = try data.leUInt32(at: 0)
        let format = try data.leUInt16(at: 4)
        let size = try data.leUInt32(at: 8)
        let parent = try data.leUInt32(at: 32)
        var offset = 52
        let filenameResult = try data.ptpString(at: offset)
        offset += filenameResult.1
        let captureResult = try data.ptpString(at: offset)
        offset += captureResult.1
        let modificationResult = try data.ptpString(at: offset)
        return PTPObjectInfo(
            handle: handle,
            storageID: storageID,
            format: format,
            size: size,
            parent: parent,
            filename: filenameResult.0,
            captureDate: captureResult.0,
            modificationDate: modificationResult.0
        )
    }
}

final class PTPRawProbe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var transactionID: UInt32 = 1

    func run() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            print("TIMEOUT")
            Foundation.exit(2)
        }
        RunLoop.main.run()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        self.camera = camera
        camera.delegate = self
        print("CAMERA \(camera.name ?? "unknown") capabilities=\(camera.capabilities.joined(separator: ","))")
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {}

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            print("OPEN_ERROR \(error.localizedDescription)")
            Foundation.exit(3)
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    func didRemove(_ device: ICDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task {
            do {
                try await probe(device)
                Foundation.exit(0)
            } catch {
                print("PROBE_ERROR \(error)")
                Foundation.exit(10)
            }
        }
    }

    private func probe(_ camera: ICCameraDevice) async throws {
        let deviceInfo = try await send(camera, code: 0x1001, parameters: [])
        print("GET_DEVICE_INFO response=\(deviceInfo.response.codeHex) dataBytes=\(deviceInfo.data.count) dataPrefix=\(deviceInfo.data.hexPrefix(24))")
        if let operations = try? parseOperationsSupported(fromDeviceInfo: deviceInfo.data) {
            print("OPERATIONS_SUPPORTED \(operations.map { String(format: "0x%04X", $0) }.joined(separator: ","))")
            print("SUPPORTS_GET_PARTIAL_OBJECT64 \(operations.contains(0x95C1))")
        }

        let storage = try await send(camera, code: 0x1004, parameters: [])
        print("GET_STORAGE_IDS response=\(storage.response.codeHex) dataBytes=\(storage.data.count) prefix=\(storage.data.hexPrefix())")
        let storageIDs = try storage.data.ptpUInt32Array()
        print("STORAGE_IDS \(storageIDs.map { String(format: "0x%08X", $0) }.joined(separator: ","))")

        var allHandles: [UInt32] = []
        for storageID in storageIDs {
            let attempts: [(String, [UInt32])] = [
                ("all-root", [storageID, 0, 0]),
                ("all-all", [storageID, 0, 0xFFFF_FFFF]),
                ("undefined-root", [storageID, 0x3000, 0]),
                ("movie-root", [storageID, 0x300B, 0])
            ]
            for attempt in attempts {
                let result = try await send(camera, code: 0x1007, parameters: attempt.1)
                let handles = (try? result.data.ptpUInt32Array()) ?? []
                print("GET_HANDLES \(attempt.0) storage=\(String(format: "0x%08X", storageID)) response=\(result.response.codeHex) count=\(handles.count)")
                allHandles.append(contentsOf: handles)
            }
        }

        let uniqueHandles = Array(Set(allHandles)).sorted()
        print("UNIQUE_HANDLES \(uniqueHandles.count)")
        for handle in uniqueHandles {
            let result = try await send(camera, code: 0x1008, parameters: [handle])
            if result.response.ok, let info = try? PTPObjectInfo.parse(handle: handle, data: result.data) {
                print("OBJECT handle=\(String(format: "0x%08X", info.handle)) format=\(String(format: "0x%04X", info.format)) size=\(info.size) parent=\(String(format: "0x%08X", info.parent)) file=\(info.filename) capture=\(info.captureDate) modified=\(info.modificationDate)")
            } else {
                print("OBJECT_ERROR handle=\(String(format: "0x%08X", handle)) response=\(result.response.codeHex) bytes=\(result.data.count) prefix=\(result.data.hexPrefix())")
            }
        }
    }

    private func send(_ camera: ICCameraDevice, code: UInt16, parameters: [UInt32], outData: Data? = nil) async throws -> (data: Data, response: PTPResponse) {
        let command = makeCommand(code: code, parameters: parameters)
        return try await withCheckedThrowingContinuation { continuation in
            camera.requestSendPTPCommand(command, outData: outData) { inData, responseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                do {
                    let response = try Self.parseResponse(responseData)
                    continuation.resume(returning: (inData, response))
                } catch {
                    print("BAD_RESPONSE code=\(String(format: "0x%04X", code)) inBytes=\(inData.count) responseBytes=\(responseData.count) responsePrefix=\(responseData.hexPrefix())")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeCommand(code: UInt16, parameters: [UInt32]) -> Data {
        let id = transactionID
        transactionID += 1
        var data = Data()
        data.appendLE(UInt32(12 + parameters.count * 4))
        data.appendLE(UInt16(1))
        data.appendLE(code)
        data.appendLE(id)
        for parameter in parameters {
            data.appendLE(parameter)
        }
        return data
    }

    private func parseOperationsSupported(fromDeviceInfo data: Data) throws -> [UInt16] {
        var offset = 0
        offset += 2 // standard version
        offset += 4 // vendor extension ID
        offset += 2 // vendor extension version
        offset += try data.ptpString(at: offset).1
        offset += 2 // functional mode
        return try data.ptpUInt16Array(at: offset).0
    }

    private static func parseResponse(_ data: Data) throws -> PTPResponse {
        guard data.count >= 12 else { throw PTPParseError.shortData("response \(data.count)") }
        let length = Int(try data.leUInt32(at: 0))
        let type = try data.leUInt16(at: 4)
        guard type == 3 else { throw PTPParseError.badContainer("type \(type)") }
        let code = try data.leUInt16(at: 6)
        let transactionID = try data.leUInt32(at: 8)
        let paramBytes = Swift.max(0, Swift.min(length, data.count) - 12)
        var parameters: [UInt32] = []
        for offset in stride(from: 12, to: 12 + paramBytes, by: 4) {
            if offset + 4 <= data.count {
                parameters.append(try data.leUInt32(at: offset))
            }
        }
        return PTPResponse(code: code, transactionID: transactionID, parameters: parameters)
    }
}

PTPRawProbe().run()
