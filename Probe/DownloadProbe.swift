import Foundation
import ImageCaptureCore

final class DownloadProbe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var progressObservation: NSKeyValueObservation?

    func run() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            print("TIMEOUT")
            Foundation.exit(2)
        }
        RunLoop.main.run()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        self.camera = camera
        camera.delegate = self
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

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        let files = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        guard let file = files
            .filter({ ($0.name ?? "").uppercased().hasSuffix(".JPG") })
            .sorted(by: { $0.fileSize < $1.fileSize })
            .first else {
            print("NO_JPG_FOUND")
            Foundation.exit(4)
        }

        let destination = URL(fileURLWithPath: "/tmp/zr-importer-download-test", isDirectory: true)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            print("MKDIR_ERROR \(error.localizedDescription)")
            Foundation.exit(5)
        }

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destination,
            .saveAsFilename: file.name ?? "download-test.jpg",
            .overwrite: true,
            .deleteAfterSuccessfulDownload: false
        ]

        print("DOWNLOADING \(file.name ?? "unnamed")")
        let progress = file.requestDownload(options: options) { savedFilename, error in
            if let error {
                print("DOWNLOAD_ERROR \(error.localizedDescription)")
                Foundation.exit(6)
            }
            let output = destination.appendingPathComponent(savedFilename ?? file.name ?? "download-test.jpg")
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? -1
            print("DOWNLOAD_OK path=\(output.path) size=\(size)")
            Foundation.exit(size > 0 ? 0 : 7)
        }

        progressObservation = progress?.observe(\.fractionCompleted, options: [.new]) { progress, _ in
            print("PROGRESS \(Int(progress.fractionCompleted * 100))")
        }
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}

DownloadProbe().run()
