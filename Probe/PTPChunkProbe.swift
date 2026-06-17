import Foundation
import ImageCaptureCore

private struct ChunkPTPResponse {
    let code: UInt16
    let parameters: [UInt32]
    var ok: Bool { code == 0x2001 }
    var codeHex: String { String(format: "0x%04X", code) }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func u16(_ offset: Int) -> UInt16 {
        subdata(in: offset..<(offset + 2)).withUnsafeBytes { UInt16(littleEndian: $0.load(as: UInt16.self)) }
    }

    func u32(_ offset: Int) -> UInt32 {
        subdata(in: offset..<(offset + 4)).withUnsafeBytes { UInt32(littleEndian: $0.load(as: UInt32.self)) }
    }

    func ptpArray32() -> [UInt32] {
        guard count >= 4 else { return [] }
        let n = Int(u32(0))
        return (0..<n).compactMap { offset -> UInt32? in
            let pos = 4 + offset * 4
            return pos + 4 <= count ? u32(pos) : nil
        }
    }

    func ptpString(_ offset: Int) -> (String, Int) {
        guard offset < count else { return ("", 0) }
        let n = Int(self[offset])
        if n == 0 { return ("", 1) }
        var scalars = String.UnicodeScalarView()
        for index in 0..<Swift.max(0, n - 1) {
            let pos = offset + 1 + index * 2
            guard pos + 2 <= count else { break }
            if let scalar = UnicodeScalar(Int(u16(pos))) {
                scalars.append(scalar)
            }
        }
        return (String(scalars), 1 + n * 2)
    }

    func hex(_ bytes: Int = 32) -> String {
        prefix(bytes).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

private struct ChunkObjectInfo {
    let handle: UInt32
    let format: UInt16
    let size: UInt32
    let filename: String

    static func parse(handle: UInt32, data: Data) -> ChunkObjectInfo? {
        guard data.count >= 53 else { return nil }
        let format = data.u16(4)
        let size = data.u32(8)
        let name = data.ptpString(52).0
        return ChunkObjectInfo(handle: handle, format: format, size: size, filename: name)
    }
}

final class PTPChunkProbe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let browser = ICDeviceBrowser()
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
        camera.delegate = self
        print("CAMERA \(camera.name ?? "unknown")")
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {}
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}
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
                let storage = try await send(device, 0x1004, [])
                let storageIDs = storage.data.ptpArray32()
                var handles: [UInt32] = []
                for storageID in storageIDs {
                    let result = try await send(device, 0x1007, [storageID, 0, 0])
                    handles.append(contentsOf: result.data.ptpArray32())
                }

                var objects: [ChunkObjectInfo] = []
                for handle in Set(handles).sorted() {
                    let infoResult = try await send(device, 0x1008, [handle])
                    if let info = ChunkObjectInfo.parse(handle: handle, data: infoResult.data) {
                        objects.append(info)
                    }
                }

                guard let nev = objects.first(where: { $0.filename.uppercased().hasSuffix(".NEV") }) else {
                    print("NO_NEV")
                    Foundation.exit(4)
                }
                print("NEV handle=\(String(format: "0x%08X", nev.handle)) size=\(nev.size) file=\(nev.filename)")

                let firstChunk = try await send(device, 0x101B, [nev.handle, 0, 1_048_576])
                print("PARTIAL response=\(firstChunk.response.codeHex) bytes=\(firstChunk.data.count) params=\(firstChunk.response.parameters) prefix=\(firstChunk.data.hex(48))")
                let output = URL(fileURLWithPath: "/tmp/\(nev.filename).first-1MiB")
                try firstChunk.data.write(to: output)
                print("WROTE \(output.path)")

                if let jpg = objects.first(where: { $0.filename.uppercased().hasSuffix(".JPG") }) {
                    let jpgChunk = try await send(device, 0x101B, [jpg.handle, 0, Swift.min(jpg.size, 1_048_576)])
                    print("JPG_PARTIAL response=\(jpgChunk.response.codeHex) bytes=\(jpgChunk.data.count) file=\(jpg.filename) prefix=\(jpgChunk.data.hex(16))")
                }

                if ProcessInfo.processInfo.environment["ZR_FULL_TEST"] == "1" {
                    let requestedName = ProcessInfo.processInfo.environment["ZR_FULL_NAME"]?.uppercased()
                    guard let target = objects
                        .filter({
                            $0.filename.uppercased().hasSuffix(".NEV")
                                && (requestedName == nil || $0.filename.uppercased() == requestedName)
                                && (requestedName != nil || $0.size < UInt32.max)
                        })
                        .sorted(by: { $0.size < $1.size })
                        .first else {
                        print("NO_KNOWN_SIZE_NEV")
                        Foundation.exit(6)
                    }

                    let folder = URL(
                        fileURLWithPath: ProcessInfo.processInfo.environment["ZR_FULL_DEST"] ?? "/tmp/zr-importer-full-nev-test",
                        isDirectory: true
                    )
                    try? FileManager.default.removeItem(at: folder)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let output = folder.appendingPathComponent(target.filename)
                    FileManager.default.createFile(atPath: output.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: output)
                    defer { try? handle.close() }

                    let chunkSize: UInt32 = UInt32(ProcessInfo.processInfo.environment["ZR_CHUNK_BYTES"] ?? "") ?? (32 * 1_024 * 1_024)
                    var offset: UInt64 = 0
                    let expected = UInt64(target.size)
                    let started = Date()
                    print("FULL_BEGIN file=\(target.filename) size=\(target.size) chunk=\(chunkSize)")
                    while offset < expected {
                        let remaining = expected - offset
                        let request = UInt32(Swift.min(UInt64(chunkSize), remaining))
                        let result = try await send(device, 0x101B, [target.handle, UInt32(offset), request])
                        if !result.response.ok {
                            print("FULL_ERROR response=\(result.response.codeHex) offset=\(offset)")
                            Foundation.exit(7)
                        }
                        if result.data.isEmpty {
                            print("FULL_EMPTY offset=\(offset)")
                            Foundation.exit(8)
                        }
                        try handle.write(contentsOf: result.data)
                        offset += UInt64(result.data.count)
                        let pct = Double(offset) / Double(expected) * 100
                        let elapsed = Date().timeIntervalSince(started)
                        print(String(format: "FULL_PROGRESS %.1f%% %@ / %@ %.1fs", pct, ByteCountFormatter.string(fromByteCount: Int64(offset), countStyle: .file), ByteCountFormatter.string(fromByteCount: Int64(expected), countStyle: .file), elapsed))
                    }
                    let savedSize = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? NSNumber)?.uint64Value ?? 0
                    print("FULL_OK path=\(output.path) size=\(savedSize)")
                    Foundation.exit(savedSize == expected ? 0 : 9)
                }

                Foundation.exit(firstChunk.data.isEmpty ? 5 : 0)
            } catch {
                print("ERROR \(error)")
                Foundation.exit(9)
            }
        }
    }

    private func send(_ camera: ICCameraDevice, _ code: UInt16, _ parameters: [UInt32], outData: Data? = nil) async throws -> (data: Data, response: ChunkPTPResponse) {
        let command = makeCommand(code, parameters)
        return try await withCheckedThrowingContinuation { continuation in
            camera.requestSendPTPCommand(command, outData: outData) { data, responseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let response = Self.parseResponse(responseData)
                continuation.resume(returning: (data, response))
            }
        }
    }

    private func makeCommand(_ code: UInt16, _ parameters: [UInt32]) -> Data {
        var data = Data()
        data.appendLE(UInt32(12 + parameters.count * 4))
        data.appendLE(UInt16(1))
        data.appendLE(code)
        data.appendLE(transactionID)
        transactionID += 1
        for parameter in parameters {
            data.appendLE(parameter)
        }
        return data
    }

    private static func parseResponse(_ data: Data) -> ChunkPTPResponse {
        guard data.count >= 12 else {
            return ChunkPTPResponse(code: 0, parameters: [])
        }
        let length = Swift.min(Int(data.u32(0)), data.count)
        let code = data.u16(6)
        var parameters: [UInt32] = []
        for offset in stride(from: 12, to: length, by: 4) where offset + 4 <= data.count {
            parameters.append(data.u32(offset))
        }
        return ChunkPTPResponse(code: code, parameters: parameters)
    }
}

PTPChunkProbe().run()
