import Foundation
import ImageCaptureCore

final class DeepImageCaptureProbe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?

    func run() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
            print("TIMEOUT")
            Foundation.exit(2)
        }
        RunLoop.main.run()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        self.camera = camera
        camera.delegate = self
        camera.mediaPresentation = .originalAssets
        print("CAMERA \(camera.name ?? "unknown") presentation=\(camera.mediaPresentation.rawValue)")
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
        print("CAPABILITIES \(device.capabilities.joined(separator: ","))")
        print("CONTENT_COUNT \(device.contents?.count ?? -1)")
        print("MEDIA_COUNT \(device.mediaFiles?.count ?? -1)")

        let types = [
            "public.item",
            "public.content",
            "public.data",
            "public.image",
            "public.movie",
            "public.audio",
            "public.raw-image",
            "com.nikon.raw-image",
            "com.nikon.nraw",
            "com.nikon.nev"
        ]

        for type in types {
            let result = device.files(ofType: type) ?? []
            print("FILES_OF_TYPE \(type) count=\(result.count) \(result)")
        }

        for file in (device.mediaFiles ?? []).compactMap({ $0 as? ICCameraFile }) {
            print("MEDIA \(file.name ?? "unnamed") uti=\(file.uti ?? "nil") size=\(file.fileSize)")
        }

        Foundation.exit(0)
    }
}

DeepImageCaptureProbe().run()
