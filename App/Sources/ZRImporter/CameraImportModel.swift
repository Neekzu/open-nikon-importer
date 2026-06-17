import AppKit
import AVFoundation
import Combine
import Foundation
@preconcurrency import ImageCaptureCore

final class CameraImportModel: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    @Published var cameraName = "Keine Kamera"
    @Published var connectionStatus = "Warte auf Kamera"
    @Published var files: [CameraFileItem] = []
    @Published var selectedIDs = Set<CameraFileItem.ID>()
    @Published var filter: FileFilter = .all
    @Published var displayMode: DisplayMode = .thumbnails
    @Published var destinationURL: URL
    @Published var importStates: [CameraFileItem.ID: ImportState] = [:]
    @Published var thumbnails: [CameraFileItem.ID: NSImage] = [:]
    @Published var lastImportedFolder: URL?
    @Published var systemNote: String?
    @Published var lastErrorMessage: String?
    @Published var previewURL: URL?
    @Published var previewTitle: String?
    @Published var previewSubtitle: String?
    @Published var previewStatus: String?
    @Published var previewMetadata: PreviewMetadata?
    @Published private var nrawScanPhase: NRAWScanPhase = .idle

    private let browser = ICDeviceBrowser()
    private let ptpEngine = PTPTransferEngine()
    private var camera: ICCameraDevice?
    private var importQueue: [CameraFileItem] = []
    private var importDestinationURLs: [CameraFileItem.ID: URL] = [:]
    private var activeImportFolderURL: URL?
    private var catalogGeneration = 0
    private var progressObservers: [CameraFileItem.ID: NSKeyValueObservation] = [:]
    private var previewProgressObserver: NSKeyValueObservation?
    private var requestedCameraThumbnailObjectIDs = Set<ObjectIdentifier>()
    private var thumbnailItemIDsByCameraFile = [ObjectIdentifier: Set<CameraFileItem.ID>]()
    private let previewCacheURL: URL
    private let maxTemporaryPreviewBytes: Int64 = 1_200_000_000
    private let minimumFreeSpaceAfterImport: Int64 = 512 * 1_024 * 1_024

    override init() {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let datedFolder = Self.defaultImportFolder(base: movies)
        destinationURL = datedFolder
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        previewCacheURL = caches
            .appendingPathComponent("Open Nikon Importer", isDirectory: true)
            .appendingPathComponent("Previews", isDirectory: true)
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
    }

    var visibleFiles: [CameraFileItem] {
        files.filter { filter.includes($0) }
            .sorted { lhs, rhs in
                switch (lhs.createdAt, rhs.createdAt) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    var selectedFiles: [CameraFileItem] {
        files.filter { selectedIDs.contains($0.id) }
    }

    var selectedItem: CameraFileItem? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return files.first { $0.id == id }
    }

    var canImportSelection: Bool {
        !selectedFiles.isEmpty && importQueue.isEmpty
    }

    var canImportAllVisible: Bool {
        !visibleFiles.isEmpty && importQueue.isEmpty
    }

    var canChangeDestination: Bool {
        importQueue.isEmpty
    }

    var hasConnectedCamera: Bool {
        camera != nil
    }

    var visibleTotalSizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: visibleFiles.reduce(Int64(0)) { $0 + $1.size },
            countStyle: .file
        )
    }

    var workflowStatusChips: [WorkflowStatusChip] {
        [
            cameraStatusChip,
            catalogStatusChip,
            nrawStatusChip,
            destinationStatusChip
        ]
    }

    func start() {
        browser.start()
    }

    func refresh() {
        guard let camera else {
            files = []
            selectedIDs = []
            thumbnails.removeAll()
            nrawScanPhase = .idle
            connectionStatus = "Keine Kamera verbunden"
            return
        }
        readCatalog(from: camera)
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationURL
        panel.message = "Importziel wählen"
        panel.prompt = "Auswählen"

        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url
            importStates.removeAll()
            lastImportedFolder = nil
            lastErrorMessage = nil
        }
    }

    func importSelected() {
        importFiles(selectedFiles)
    }

    func importVisible() {
        importFiles(visibleFiles)
    }

    func revealLastImport() {
        guard let lastImportedFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastImportedFolder])
    }

    func revealDestination() {
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func select(_ item: CameraFileItem, extending: Bool = false) {
        if extending {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } else {
            selectedIDs = [item.id]
        }
        selectionDidChange()
    }

    func preview(_ item: CameraFileItem) {
        selectedIDs = [item.id]
        selectionDidChange()
        previewSelection(openQuickLook: true)
    }

    func thumbnail(for item: CameraFileItem) -> NSImage? {
        if let image = thumbnails[item.id] {
            return image
        }
        if let proxy = pairedProxy(for: item), let image = thumbnails[proxy.id] {
            return image
        }
        return nil
    }

    func selectionDidChange() {
        previewProgressObserver = nil
        previewURL = previewLocalURL(for: selectedItem)
        previewTitle = selectedItem?.name
        previewSubtitle = selectedItem.map { mediaKind(for: $0).label }
        previewStatus = selectedItem == nil ? nil : previewHint(for: selectedItem!)
        previewMetadata = nil
        loadPreviewMetadataIfPossible()
    }

    func mediaKind(for item: CameraFileItem) -> CameraMediaKind {
        if isVideoProxy(item) { return .videoProxy }
        return item.defaultMediaKind
    }

    func pairedProxy(for item: CameraFileItem) -> CameraFileItem? {
        guard item.isRawVideo else { return nil }
        return files.first {
            $0.id != item.id
                && $0.baseName == item.baseName
                && ["MP4", "MOV", "M4V"].contains($0.fileExtension)
        }
    }

    func localImportedURL(for item: CameraFileItem) -> URL? {
        if case .complete(let url) = importStates[item.id],
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let destinationFile = destinationURL.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: destinationFile.path) {
            return destinationFile
        }

        return nil
    }

    func localPreviewProxyURL(for item: CameraFileItem) -> URL? {
        if let proxy = pairedProxy(for: item) {
            if let local = localImportedURL(for: proxy) {
                return local
            }
            let cached = previewCacheURL.appendingPathComponent(proxy.name)
            if FileManager.default.fileExists(atPath: cached.path) {
                return cached
            }
        }
        return nil
    }

    func workflowRows(for item: CameraFileItem) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Format", mediaKind(for: item).label),
            ("Datei", item.name),
            ("Größe", item.sizeLabel),
            ("Datum", item.createdAt.map(Self.detailDateFormatter.string(from:)) ?? "-"),
            ("Quelle", item.sourceLabel)
        ]

        if let proxy = pairedProxy(for: item) {
            rows.append(("Preview-Proxy", proxy.name))
        }

        if let localURL = localImportedURL(for: item) {
            rows.append(("Lokal", localURL.path(percentEncoded: false)))
        }

        if let metadata = previewMetadata {
            if let duration = metadata.duration {
                rows.append(("Dauer", duration))
            }
            if let dimensions = metadata.dimensions {
                rows.append(("Auflösung", dimensions))
            }
            if let codec = metadata.codec {
                rows.append(("Codec", codec))
            }
        }

        return rows
    }

    func technicalRows(for item: CameraFileItem) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Extension", item.fileExtension.isEmpty ? "-" : item.fileExtension)
        ]

        if let uti = item.uti, !uti.isEmpty {
            rows.append(("UTI", uti))
        }

        switch item.source {
        case .imageCapture(let file):
            rows.append(("macOS RAW", file.isRaw ? "ja" : "nein"))
            rows.append(("macOS Movie", item.isMovie ? "ja" : "nein"))
            rows.append(("Originalname", file.originalFilename ?? "-"))
            if let sidecars = file.sidecarFiles, !sidecars.isEmpty {
                rows.append(("Sidecars", "\(sidecars.count)"))
            }
            if let pairedRaw = file.pairedRawImage {
                rows.append(("Paired RAW", pairedRaw.name ?? pairedRaw.originalFilename ?? "-"))
            }
        case .ptp(let object):
            rows.append(("PTP Handle", String(format: "0x%08X", object.handle)))
            rows.append(("PTP Format", String(format: "0x%04X", object.format)))
            rows.append(("Storage", String(format: "0x%08X", object.storageID)))
            rows.append(("Reported Size", object.reportedSize == UInt32.max ? "0xFFFFFFFF" : "\(object.reportedSize)"))
            if let resolved = object.resolvedSize {
                rows.append(("Resolved Size", "\(resolved)"))
            }
            rows.append(("Transfer", object.needsNikonExtendedTransfer ? "Nikon 64-bit PTP" : "Standard PTP"))
        }

        return rows
    }

    func previewSelection(openQuickLook: Bool = true) {
        guard let item = selectedItem else {
            previewStatus = "Keine Datei ausgewählt."
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.preparePreview(for: item, openQuickLook: openQuickLook)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        self.camera = camera
        camera.delegate = self
        cameraName = camera.name ?? "Nikon Kamera"
        connectionStatus = "Verbunden"
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard device === camera else { return }
        camera = nil
        files = []
        selectedIDs = []
        thumbnails.removeAll()
        nrawScanPhase = .idle
        selectionDidChange()
        importQueue = []
        progressObservers.removeAll()
        cameraName = "Keine Kamera"
        connectionStatus = "Kamera getrennt"
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            connectionStatus = "Session-Fehler"
            systemNote = error.localizedDescription
            return
        }
        connectionStatus = "Lese Inhalte"
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        if let error {
            systemNote = error.localizedDescription
        }
    }

    func didRemove(_ device: ICDevice) {
        camera = nil
        files = []
        selectedIDs = []
        thumbnails.removeAll()
        nrawScanPhase = .idle
        selectionDidChange()
        connectionStatus = "Kamera getrennt"
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        readCatalog(from: camera)
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        readCatalog(from: camera)
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {
        guard let thumbnail, let file = item as? ICCameraFile else { return }
        let objectID = ObjectIdentifier(file)
        let ids = thumbnailItemIDsByCameraFile[objectID] ?? [CameraFileItem(file: file).id]
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for id in ids {
                self.thumbnails[id] = image
            }
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        readCatalog(from: camera)
    }

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        readCatalog(from: device)
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        systemNote = nil
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        systemNote = "Kamera ist gesperrt oder blockiert."
    }

    private func readCatalog(from camera: ICCameraDevice) {
        catalogGeneration += 1
        let generation = catalogGeneration
        let nextFiles = (camera.mediaFiles ?? [])
            .compactMap { $0 as? ICCameraFile }
            .map(CameraFileItem.init(file:))

        if importQueue.isEmpty {
            importStates.removeAll()
            lastErrorMessage = nil
        }
        files = nextFiles
        selectedIDs.formIntersection(Set(nextFiles.map(\.id)))
        selectionDidChange()
        requestThumbnails(for: nextFiles)
        connectionStatus = nextFiles.isEmpty ? "Lese PTP-Katalog" : "\(nextFiles.count) Dateien · lese N-RAW"
        nrawScanPhase = .scanning

        let hasNikonZR = (camera.name ?? "").localizedCaseInsensitiveContains("ZR")
        let hasNRAW = nextFiles.contains { $0.fileExtension == "NEV" }
        if hasNikonZR && !hasNRAW {
            systemNote = "N-RAW .NEV wird per PTP-Chunks gesucht."
        } else {
            systemNote = nil
        }

        guard camera.capabilities.contains("ICCameraDeviceCanAcceptPTPCommands") else {
            connectionStatus = nextFiles.isEmpty ? "Keine importierbaren Dateien" : "\(nextFiles.count) Dateien"
            nrawScanPhase = .unsupported
            return
        }

        Task { [weak self, weak camera] in
            guard let self, let camera else { return }

            do {
                let objects = try await self.ptpEngine.listObjects(on: camera)
                let nrawItems = objects
                    .filter { $0.fileExtension == "NEV" }
                    .map(CameraFileItem.init(ptpObject:))

                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.catalogGeneration else { return }

                    let imageCaptureItems = self.files.filter {
                        if case .imageCapture = $0.source { return true }
                        return false
                    }
                    let merged = imageCaptureItems + nrawItems
                    self.files = merged
                    self.selectedIDs.formIntersection(Set(merged.map(\.id)))
                    self.selectionDidChange()
                    self.requestThumbnails(for: merged)
                    self.connectionStatus = nrawItems.isEmpty
                        ? "\(merged.count) Dateien"
                        : "\(merged.count) Dateien · \(nrawItems.count) N-RAW"
                    self.nrawScanPhase = nrawItems.isEmpty ? .noneFound : .found(nrawItems.count)
                    self.systemNote = nrawItems.isEmpty
                        ? "Keine .NEV-Dateien im PTP-Katalog gefunden."
                        : "N-RAW aktiv: .NEV wird direkt per PTP importiert."
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.catalogGeneration else { return }
                    self.connectionStatus = nextFiles.isEmpty ? "PTP-Katalogfehler" : "\(nextFiles.count) Dateien"
                    self.nrawScanPhase = .failed
                    self.systemNote = "PTP-Katalog konnte nicht gelesen werden: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importFiles(_ items: [CameraFileItem]) {
        guard !items.isEmpty, importQueue.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        } catch {
            systemNote = "Importziel nicht beschreibbar: \(error.localizedDescription)"
            return
        }

        lastErrorMessage = nil
        let importableItems = items.filter(\.canImport)
        let blockedItems = items.filter { !$0.canImport }

        for item in blockedItems {
            let reason = item.unavailableReason ?? "\(item.name) ist aktuell nicht importierbar."
            importStates[item.id] = .failed(reason)
            lastErrorMessage = reason
        }

        guard !importableItems.isEmpty else {
            return
        }

        let plan = makeImportPlan(for: importableItems, in: destinationURL)
        if let diskSpaceError = diskSpacePreflightError(for: importableItems, in: destinationURL) {
            for item in importableItems {
                importStates[item.id] = .failed(diskSpaceError)
            }
            lastErrorMessage = diskSpaceError
            return
        }

        if plan.duplicateCount > 0 {
            let firstRename = plan.renamedExamples.first.map { "\($0.original) -> \($0.renamed)" }
            let detail = firstRename.map { " Beispiel: \($0)." } ?? ""
            systemNote = "Bestehende Dateien werden nicht überschrieben. \(plan.duplicateCount) Import\(plan.duplicateCount == 1 ? "" : "e") erhalten automatisch einen Suffix.\(detail)"
        }

        importDestinationURLs = plan.destinationURLs
        activeImportFolderURL = destinationURL
        importQueue = importableItems
        for item in importableItems {
            importStates[item.id] = .queued
        }
        importNext()
    }

    private func importNext() {
        guard !importQueue.isEmpty else {
            progressObservers.removeAll()
            lastImportedFolder = activeImportFolderURL ?? destinationURL
            activeImportFolderURL = nil
            importDestinationURLs.removeAll()
            connectionStatus = "\(files.count) Dateien"
            return
        }

        let item = importQueue.removeFirst()
        importStates[item.id] = .importing(0)
        connectionStatus = "Importiere \(item.name)"

        switch item.source {
        case .imageCapture(let file):
            importImageCaptureFile(file, item: item)
        case .ptp(let object):
            importPTPObject(object, item: item)
        }
    }

    private func importImageCaptureFile(_ file: ICCameraFile, item: CameraFileItem) {
        let targetURL = importDestinationURLs[item.id] ?? destinationURL.appendingPathComponent(item.name)
        let targetFolderURL = targetURL.deletingLastPathComponent()
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: targetFolderURL,
            .saveAsFilename: targetURL.lastPathComponent,
            .overwrite: false,
            .sidecarFiles: true,
            .deleteAfterSuccessfulDownload: false
        ]

        let progress = file.requestDownload(options: options) { [weak self] savedFilename, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressObservers[item.id] = nil

                if let error {
                    self.importStates[item.id] = .failed(error.localizedDescription)
                    self.lastErrorMessage = error.localizedDescription
                } else {
                    let savedURL = targetFolderURL.appendingPathComponent(savedFilename ?? targetURL.lastPathComponent)
                    self.importStates[item.id] = .complete(savedURL)
                    if self.selectedIDs.contains(item.id) {
                        self.selectionDidChange()
                    }
                }

                self.importNext()
            }
        }

        progressObservers[item.id] = progress?.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.importStates[item.id] = .importing(progress.fractionCompleted)
            }
        }
    }

    private func importPTPObject(_ object: PTPObject, item: CameraFileItem) {
        guard let camera else {
            importStates[item.id] = .failed("Kamera ist nicht mehr verbunden.")
            importNext()
            return
        }

        let outputURL = importDestinationURLs[item.id] ?? destinationURL.appendingPathComponent(item.name)
        Task { [weak self, weak camera] in
            guard let self, let camera else { return }

            do {
                try await self.ptpEngine.download(object: object, from: camera, to: outputURL) { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.importStates[item.id] = .importing(progress)
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.importStates[item.id] = .complete(outputURL)
                    self.lastErrorMessage = nil
                    if self.selectedIDs.contains(item.id) {
                        self.selectionDidChange()
                    }
                    self.importNext()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.importStates[item.id] = .failed(error.localizedDescription)
                    self.lastErrorMessage = error.localizedDescription
                    self.importNext()
                }
            }
        }
    }

    private var cameraStatusChip: WorkflowStatusChip {
        if hasConnectedCamera {
            return WorkflowStatusChip(title: "Camera", value: cameraName, kind: .ready)
        }
        return WorkflowStatusChip(title: "Camera", value: "Nicht verbunden", kind: .idle)
    }

    private var catalogStatusChip: WorkflowStatusChip {
        guard hasConnectedCamera else {
            return WorkflowStatusChip(title: "Catalog", value: "Wartet", kind: .idle)
        }

        if connectionStatus.localizedCaseInsensitiveContains("Lese") {
            return WorkflowStatusChip(title: "Catalog", value: "Liest", kind: .working)
        }

        if files.isEmpty {
            return WorkflowStatusChip(title: "Catalog", value: "Leer", kind: .warning)
        }

        return WorkflowStatusChip(title: "Catalog", value: "\(files.count) Dateien", kind: .ready)
    }

    private var nrawStatusChip: WorkflowStatusChip {
        switch nrawScanPhase {
        case .idle:
            return WorkflowStatusChip(title: "N-RAW scan", value: "Wartet", kind: .idle)
        case .scanning:
            return WorkflowStatusChip(title: "N-RAW scan", value: "Läuft", kind: .working)
        case .found(let count):
            return WorkflowStatusChip(title: "N-RAW scan", value: "\(count) gefunden", kind: .ready)
        case .noneFound:
            return WorkflowStatusChip(title: "N-RAW scan", value: "Keine .NEV", kind: .idle)
        case .unsupported:
            return WorkflowStatusChip(title: "N-RAW scan", value: "Nicht verfügbar", kind: .warning)
        case .failed:
            return WorkflowStatusChip(title: "N-RAW scan", value: "Fehler", kind: .warning)
        }
    }

    private var destinationStatusChip: WorkflowStatusChip {
        switch destinationReadiness() {
        case .writable:
            return WorkflowStatusChip(title: "Destination", value: "Beschreibbar", kind: .ready)
        case .willCreate:
            return WorkflowStatusChip(title: "Destination", value: "Wird erstellt", kind: .ready)
        case .notWritable:
            return WorkflowStatusChip(title: "Destination", value: "Nicht beschreibbar", kind: .blocked)
        }
    }

    private func destinationReadiness() -> DestinationReadiness {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue && fileManager.isWritableFile(atPath: destinationURL.path)
                ? .writable
                : .notWritable
        }

        var probeURL = destinationURL.deletingLastPathComponent()
        while !fileManager.fileExists(atPath: probeURL.path, isDirectory: &isDirectory) {
            let nextURL = probeURL.deletingLastPathComponent()
            if nextURL.path == probeURL.path {
                return .notWritable
            }
            probeURL = nextURL
        }

        return isDirectory.boolValue && fileManager.isWritableFile(atPath: probeURL.path)
            ? .willCreate
            : .notWritable
    }

    private func makeImportPlan(for items: [CameraFileItem], in folderURL: URL) -> ImportPlan {
        var destinationURLs: [CameraFileItem.ID: URL] = [:]
        var reservedPaths = Set<String>()
        var renamedExamples: [(original: String, renamed: String)] = []

        for item in items {
            let destinationURL = uniqueDestinationURL(
                for: item.name,
                in: folderURL,
                reservedPaths: &reservedPaths
            )
            destinationURLs[item.id] = destinationURL

            if destinationURL.lastPathComponent != item.name {
                renamedExamples.append((item.name, destinationURL.lastPathComponent))
            }
        }

        return ImportPlan(
            destinationURLs: destinationURLs,
            duplicateCount: renamedExamples.count,
            renamedExamples: Array(renamedExamples.prefix(3))
        )
    }

    private func uniqueDestinationURL(
        for filename: String,
        in folderURL: URL,
        reservedPaths: inout Set<String>
    ) -> URL {
        let baseName = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension

        for index in 1...10_000 {
            let candidateName: String
            if index == 1 {
                candidateName = filename
            } else if pathExtension.isEmpty {
                candidateName = "\(baseName) (\(index))"
            } else {
                candidateName = "\(baseName) (\(index)).\(pathExtension)"
            }

            let candidateURL = folderURL.appendingPathComponent(candidateName)
            let reservedKey = candidateURL.standardizedFileURL.path.lowercased()
            if !reservedPaths.contains(reservedKey),
               !FileManager.default.fileExists(atPath: candidateURL.path) {
                reservedPaths.insert(reservedKey)
                return candidateURL
            }
        }

        let fallbackName = UUID().uuidString + "-" + filename
        let fallbackURL = folderURL.appendingPathComponent(fallbackName)
        reservedPaths.insert(fallbackURL.standardizedFileURL.path.lowercased())
        return fallbackURL
    }

    private func diskSpacePreflightError(for items: [CameraFileItem], in folderURL: URL) -> String? {
        let requiredBytes = items.reduce(Int64(0)) { partial, item in
            partial + max(0, item.size)
        }
        guard requiredBytes > 0 else { return nil }

        do {
            let availableBytes = try availableCapacityForImport(at: folderURL)
            let requiredWithReserve = requiredBytes + minimumFreeSpaceAfterImport
            guard availableBytes >= requiredWithReserve else {
                return [
                    "Nicht genug freier Speicher am Importziel.",
                    "Benötigt \(Self.bytesLabel(requiredBytes)) plus \(Self.bytesLabel(minimumFreeSpaceAfterImport)) Reserve, verfügbar \(Self.bytesLabel(availableBytes))."
                ].joined(separator: " ")
            }
        } catch {
            return "Freier Speicher am Importziel konnte nicht geprüft werden: \(error.localizedDescription)"
        }

        return nil
    }

    private func availableCapacityForImport(at folderURL: URL) throws -> Int64 {
        let values = try folderURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])

        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }

        throw CocoaError(.fileReadUnknown)
    }

    private static func bytesLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func defaultImportFolder(base: URL) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return base
            .appendingPathComponent("Nikon Imports", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
    }

    private func isVideoProxy(_ item: CameraFileItem) -> Bool {
        guard ["MP4", "MOV", "M4V"].contains(item.fileExtension) else { return false }
        return files.contains {
            $0.id != item.id
                && $0.baseName == item.baseName
                && $0.isRawVideo
        }
    }

    private func requestThumbnails(for items: [CameraFileItem]) {
        for item in items {
            if thumbnails[item.id] != nil { continue }

            if let local = previewLocalURL(for: item),
               let image = makeLocalThumbnail(for: local) {
                thumbnails[item.id] = image
                continue
            }

            switch item.source {
            case .imageCapture(let file):
                requestCameraThumbnail(file, assignTo: [item.id])
            case .ptp:
                if let proxy = pairedProxy(for: item),
                   case .imageCapture(let proxyFile) = proxy.source {
                    requestCameraThumbnail(proxyFile, assignTo: [item.id, proxy.id])
                }
            }
        }
    }

    private func requestCameraThumbnail(_ file: ICCameraFile, assignTo itemIDs: Set<CameraFileItem.ID>) {
        let objectID = ObjectIdentifier(file)
        thumbnailItemIDsByCameraFile[objectID, default: []].formUnion(itemIDs)

        guard !requestedCameraThumbnailObjectIDs.contains(objectID) else { return }
        requestedCameraThumbnailObjectIDs.insert(objectID)
        file.requestThumbnail()
    }

    private func makeLocalThumbnail(for url: URL) -> NSImage? {
        let fileExtension = url.pathExtension.uppercased()

        if ["JPG", "JPEG", "PNG", "HEIC", "HEIF", "TIFF", "TIF", "NEF", "DNG"].contains(fileExtension) {
            return NSImage(contentsOf: url)
        }

        if ["MOV", "MP4", "M4V"].contains(fileExtension) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }

        return nil
    }

    private func previewLocalURL(for item: CameraFileItem?) -> URL? {
        guard let item else { return nil }

        if item.isRawVideo {
            if let proxyURL = localPreviewProxyURL(for: item) {
                return proxyURL
            }
            if pairedProxy(for: item) != nil {
                return nil
            }
            return localImportedURL(for: item)
        }

        if let local = localImportedURL(for: item) {
            return local
        }

        let cached = previewCacheURL.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        return nil
    }

    private func previewHint(for item: CameraFileItem) -> String? {
        if let _ = previewLocalURL(for: item) {
            return item.isRawVideo ? "Lokale RAW-Datei bereit; kein Proxy gefunden." : "Lokale Vorschau bereit."
        }

        if item.isRawVideo {
            if let proxy = pairedProxy(for: item) {
                return "Proxy \(proxy.name) wird für die Vorschau vorbereitet."
            }
            return "Kein gleichnamiger Proxy gefunden. RAW erst importieren oder extern öffnen."
        }

        if case .imageCapture = item.source,
           (item.isPreviewableMovie || item.isPreviewableImage),
           item.size <= maxTemporaryPreviewBytes {
            return "Temporäre Vorschau wird vorbereitet."
        }

        if item.isPreviewableMovie || item.isPreviewableImage {
            return "Für diese große Datei erst importieren, dann per Space previewen."
        }

        return "Für dieses Format ist keine native Vorschau bekannt."
    }

    private func preparePreview(for item: CameraFileItem, openQuickLook: Bool) async {
        await MainActor.run {
            previewTitle = item.name
            previewSubtitle = mediaKind(for: item).label
            previewStatus = "Bereite Vorschau vor..."
            previewMetadata = nil
        }

        do {
            let targetURL = try await resolvePreviewURL(for: item)
            await MainActor.run {
                previewURL = targetURL
                previewStatus = item.isRawVideo ? "Proxy-Vorschau bereit." : "Vorschau bereit."
                loadPreviewMetadataIfPossible()
                if openQuickLook {
                    QuickLookPreviewer.shared.preview(url: targetURL)
                }
            }
        } catch {
            await MainActor.run {
                previewURL = previewLocalURL(for: item)
                previewStatus = error.localizedDescription
            }
        }
    }

    private func resolvePreviewURL(for item: CameraFileItem) async throws -> URL {
        if item.isRawVideo {
            if let proxyURL = localPreviewProxyURL(for: item) {
                return proxyURL
            }
            if let proxy = pairedProxy(for: item) {
                return try await cachePreviewFile(proxy, reason: "Lade Proxy \(proxy.name)")
            }
            if let local = localImportedURL(for: item) {
                return local
            }
            throw PreviewError.unavailable("Kein Preview-Proxy für \(item.name) gefunden.")
        }

        if let local = localImportedURL(for: item) {
            return local
        }

        let cached = previewCacheURL.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        guard item.isPreviewableMovie || item.isPreviewableImage else {
            throw PreviewError.unavailable("Keine native Vorschau für \(item.fileExtension).")
        }

        guard item.size <= maxTemporaryPreviewBytes else {
            throw PreviewError.unavailable("\(item.name) ist zu groß für eine temporäre Vorschau. Erst importieren.")
        }

        return try await cachePreviewFile(item, reason: "Lade Vorschau")
    }

    private func cachePreviewFile(_ item: CameraFileItem, reason: String) async throws -> URL {
        guard case .imageCapture(let file) = item.source else {
            throw PreviewError.unavailable("\(item.name) ist nur per PTP sichtbar und hat keinen direkten Preview-Download.")
        }

        try FileManager.default.createDirectory(at: previewCacheURL, withIntermediateDirectories: true)
        let outputURL = previewCacheURL.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        await MainActor.run {
            previewStatus = "\(reason) · 0 %"
        }

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: previewCacheURL,
            .saveAsFilename: item.name,
            .overwrite: true,
            .sidecarFiles: false,
            .deleteAfterSuccessfulDownload: false
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let progress = file.requestDownload(options: options) { savedFilename, error in
                DispatchQueue.main.async {
                    self.previewProgressObserver = nil
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let savedURL = self.previewCacheURL.appendingPathComponent(savedFilename ?? item.name)
                continuation.resume(returning: savedURL)
            }

            DispatchQueue.main.async { [weak self] in
                self?.previewProgressObserver = progress?.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                    DispatchQueue.main.async {
                        self?.previewStatus = "\(reason) · \(Int(progress.fractionCompleted * 100)) %"
                    }
                }
            }
        }
    }

    private func loadPreviewMetadataIfPossible() {
        guard let previewURL else {
            previewMetadata = nil
            return
        }

        Task {
            let metadata = await PreviewMetadata.load(from: previewURL)
            await MainActor.run {
                if self.previewURL == previewURL {
                    self.previewMetadata = metadata
                }
            }
        }
    }

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private enum PreviewError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

private struct ImportPlan {
    let destinationURLs: [CameraFileItem.ID: URL]
    let duplicateCount: Int
    let renamedExamples: [(original: String, renamed: String)]
}

struct WorkflowStatusChip: Identifiable {
    let title: String
    let value: String
    let kind: WorkflowStatusKind

    var id: String { title }
}

enum WorkflowStatusKind {
    case ready
    case working
    case warning
    case blocked
    case idle
}

private enum NRAWScanPhase: Equatable {
    case idle
    case scanning
    case found(Int)
    case noneFound
    case unsupported
    case failed
}

private enum DestinationReadiness {
    case writable
    case willCreate
    case notWritable
}
