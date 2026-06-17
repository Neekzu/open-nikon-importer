import Foundation
import ImageCaptureCore

final class AppEngineImportProbe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let browser = ICDeviceBrowser()
    private let engine = PTPTransferEngine()

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
                let objects = try await engine.listObjects(on: device)
                let requestedName = ProcessInfo.processInfo.environment["ZR_IMPORT_NAME"] ?? "A001_C140_0616BE.NEV"
                guard let object = objects.first(where: { $0.filename == requestedName }) else {
                    print("OBJECT_NOT_FOUND")
                    Foundation.exit(3)
                }
                print("OBJECT \(object.filename) reported=\(object.reportedSize) resolved=\(object.resolvedSize.map(String.init) ?? "nil") canDownload=\(object.canDownload)")
                let folder = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent(ProcessInfo.processInfo.environment["ZR_IMPORT_DEST"] ?? "Downloads/zr-importer-app-engine-test", isDirectory: true)
                let shouldCleanDestination = ProcessInfo.processInfo.environment["ZR_IMPORT_DEST"] == nil
                    || ProcessInfo.processInfo.environment["ZR_IMPORT_CLEAN_DEST"] == "1"
                if shouldCleanDestination {
                    try? FileManager.default.removeItem(at: folder)
                }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let output = folder.appendingPathComponent(object.filename)
                print("BEGIN \(output.path) expected=\(object.size)")
                try await engine.download(object: object, from: device, to: output) { progress in
                    print(String(format: "PROGRESS %.1f", progress * 100))
                }
                let size = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? NSNumber)?.uint64Value ?? 0
                print("OK size=\(size) path=\(output.path)")
                Foundation.exit(size == object.size ? 0 : 4)
            } catch {
                print("ERROR \(error.localizedDescription)")
                Foundation.exit(5)
            }
        }
    }
}

@main
struct AppEngineImportProbeMain {
    static func main() {
        AppEngineImportProbe().run()
    }
}
