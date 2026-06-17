import AVFoundation
import Foundation

struct PreviewMetadata: Equatable {
    let duration: String?
    let dimensions: String?
    let codec: String?

    static func load(from url: URL) -> PreviewMetadata? {
        let asset = AVURLAsset(url: url)
        let videoTrack = asset.tracks(withMediaType: .video).first
        let seconds = CMTimeGetSeconds(asset.duration)

        let duration = seconds.isFinite && seconds > 0
            ? Self.durationFormatter.string(from: seconds) ?? String(format: "%.1f s", seconds)
            : nil

        let dimensions: String?
        if let videoTrack {
            let transformed = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            let width = Int(abs(transformed.width).rounded())
            let height = Int(abs(transformed.height).rounded())
            dimensions = width > 0 && height > 0 ? "\(width) × \(height)" : nil
        } else {
            dimensions = nil
        }

        let codec: String?
        if let format = videoTrack?.formatDescriptions.first {
            let subtype = CMFormatDescriptionGetMediaSubType(format as! CMFormatDescription)
            codec = Self.fourCC(subtype)
        } else {
            codec = nil
        }

        guard duration != nil || dimensions != nil || codec != nil else { return nil }
        return PreviewMetadata(duration: duration, dimensions: dimensions, codec: codec)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let text = String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", value)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
