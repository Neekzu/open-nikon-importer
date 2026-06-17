import Foundation
import ImageCaptureCore

enum CameraFileSource {
    case imageCapture(ICCameraFile)
    case ptp(PTPObject)
}

enum CameraMediaKind: String {
    case nikonNRAW
    case redR3D
    case videoProxy
    case movie
    case photoRaw
    case photo
    case sidecar
    case other

    var label: String {
        switch self {
        case .nikonNRAW: return "N-RAW"
        case .redR3D: return "R3D"
        case .videoProxy: return "Proxy"
        case .movie: return "Video"
        case .photoRaw: return "Foto RAW"
        case .photo: return "Foto"
        case .sidecar: return "Sidecar"
        case .other: return "Datei"
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case list = "Liste"
    case thumbnails = "Thumbnails"

    var id: String { rawValue }
}

struct CameraFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let fileExtension: String
    let size: Int64
    let sizeIsKnown: Bool
    let createdAt: Date?
    let uti: String?
    let isRaw: Bool
    let isMovie: Bool
    let source: CameraFileSource

    init(file: ICCameraFile) {
        let resolvedName = file.name ?? file.originalFilename ?? "Unnamed"
        let resolvedSize = Int64(file.fileSize)
        let resolvedDate = file.fileCreationDate
        name = resolvedName
        fileExtension = (resolvedName as NSString).pathExtension.uppercased()
        size = resolvedSize
        sizeIsKnown = true
        createdAt = resolvedDate
        uti = file.uti
        isRaw = file.isRaw || ["NEF", "NRW", "RAW", "DNG", "R3D"].contains(fileExtension)
        isMovie = file.uti == "public.movie" || ["MOV", "MP4", "R3D"].contains(fileExtension)
        source = .imageCapture(file)
        id = [
            "ic",
            resolvedName,
            String(resolvedSize),
            resolvedDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no-date"
        ].joined(separator: "|")
    }

    init(ptpObject object: PTPObject) {
        name = object.filename
        fileExtension = object.fileExtension
        size = Int64(object.size)
        sizeIsKnown = object.hasKnownSize
        createdAt = object.createdAt
        uti = fileExtension == "NEV" ? "com.nikon.nraw" : "public.data"
        isRaw = ["NEF", "NRW", "RAW", "DNG", "NEV", "R3D"].contains(fileExtension)
        isMovie = ["MOV", "MP4", "NEV", "R3D"].contains(fileExtension)
        source = .ptp(object)
        id = [
            "ptp",
            String(format: "0x%08X", object.handle),
            object.filename,
            object.captureDateString
        ].joined(separator: "|")
    }

    var sizeLabel: String {
        let label = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return sizeIsKnown ? label : ">= \(label)"
    }

    var baseName: String {
        (name as NSString).deletingPathExtension
    }

    var isNikonNRAW: Bool {
        fileExtension == "NEV"
    }

    var isRedR3D: Bool {
        fileExtension == "R3D"
    }

    var isRawVideo: Bool {
        isNikonNRAW || isRedR3D
    }

    var isPreviewableMovie: Bool {
        ["MOV", "MP4", "M4V"].contains(fileExtension)
    }

    var isPreviewableImage: Bool {
        ["JPG", "JPEG", "PNG", "HEIC", "HEIF", "TIFF", "TIF", "NEF", "DNG"].contains(fileExtension)
    }

    var defaultMediaKind: CameraMediaKind {
        if isNikonNRAW { return .nikonNRAW }
        if isRedR3D { return .redR3D }
        if ["XMP", "XML", "WAV"].contains(fileExtension) { return .sidecar }
        if isPreviewableMovie { return .movie }
        if isRaw { return .photoRaw }
        if isPreviewableImage { return .photo }
        return .other
    }

    var sourceLabel: String {
        switch source {
        case .imageCapture:
            return "macOS"
        case .ptp:
            return "PTP"
        }
    }

    var canImport: Bool {
        switch source {
        case .imageCapture:
            return true
        case .ptp(let object):
            return object.canDownload
        }
    }

    var unavailableReason: String? {
        guard !canImport else { return nil }
        return "\(name): Nikon meldet diese N-RAW-Datei als `0xFFFFFFFF`, und der 64-bit-Nikon-Transfer konnte nicht aktiviert werden."
    }

    static func == (lhs: CameraFileItem, rhs: CameraFileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum FileFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case video = "Video"
    case photo = "Foto"
    case raw = "RAW"

    var id: String { rawValue }

    func includes(_ item: CameraFileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .video:
            return item.isMovie
        case .photo:
            return !item.isMovie
        case .raw:
            return item.isRaw || ["NEF", "NRW", "RAW", "DNG", "NEV", "R3D"].contains(item.fileExtension)
        }
    }
}

enum ImportState: Equatable {
    case idle
    case queued
    case importing(Double)
    case complete(URL)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return ""
        case .queued:
            return "Wartet"
        case .importing(let progress):
            return "\(Int(progress * 100)) %"
        case .complete:
            return "Fertig"
        case .failed:
            return "Fehler"
        }
    }
}
