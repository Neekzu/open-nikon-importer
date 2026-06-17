import Foundation
import ImageCaptureCore

final class ImageCaptureProbe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var didPrintCatalog = false

    func run() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            if self.camera == nil {
                print("TIMEOUT no camera detected")
                Foundation.exit(2)
            }
            if !self.didPrintCatalog {
                print("TIMEOUT camera detected, but catalog not ready")
                Foundation.exit(3)
            }
        }

        RunLoop.main.run()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        self.camera = camera
        camera.delegate = self
        print("CAMERA name=\(camera.name ?? "unknown") transport=\(camera.transportType ?? "unknown") uuid=\(camera.uuidString ?? "unknown")")
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if device === camera {
            print("REMOVED \(device.name ?? "camera")")
            Foundation.exit(4)
        }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            print("OPEN_ERROR \(error.localizedDescription) \(error)")
            Foundation.exit(5)
        }
        print("SESSION_OPEN")
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        if let error {
            print("SESSION_CLOSED error=\(error.localizedDescription)")
        } else {
            print("SESSION_CLOSED")
        }
    }

    func didRemove(_ device: ICDevice) {
        print("DEVICE_REMOVED \(device.name ?? "camera")")
        Foundation.exit(4)
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        print("ADDED_ITEMS count=\(items.count)")
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        didPrintCatalog = true
        let items = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        print("CATALOG_READY files=\(items.count)")
        print("CONTENT_TREE_BEGIN")
        for item in device.contents ?? [] {
            printItem(item, indent: "")
        }
        print("CONTENT_TREE_END")
        print("MEDIA_FILES_BEGIN")
        for file in items.sorted(by: { ($0.fileCreationDate ?? .distantPast) < ($1.fileCreationDate ?? .distantPast) }) {
            printFile(file, prefix: "FILE")
        }
        print("MEDIA_FILES_END")
        Foundation.exit(0)
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    private func printItem(_ item: ICCameraItem, indent: String) {
        if let folder = item as? ICCameraFolder {
            print("\(indent)FOLDER name=\(folder.name ?? "unnamed") uti=\(folder.uti ?? "nil")")
            for child in folder.contents ?? [] {
                printItem(child, indent: indent + "  ")
            }
        } else if let file = item as? ICCameraFile {
            printFile(file, prefix: "\(indent)TREE_FILE")
        } else {
            print("\(indent)ITEM name=\(item.name ?? "unnamed") uti=\(item.uti ?? "nil")")
        }
    }

    private func printFile(_ file: ICCameraFile, prefix: String) {
        let name = file.name ?? file.originalFilename ?? "unnamed"
        let ext = (name as NSString).pathExtension.uppercased()
        let date = file.fileCreationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no-date"
        let size = ByteCountFormatter.string(fromByteCount: Int64(file.fileSize), countStyle: .file)
        print("\(prefix) ext=\(ext) size=\(size) date=\(date) name=\(name) uti=\(file.uti ?? "nil") raw=\(file.isRaw)")
    }
}

ImageCaptureProbe().run()
