import Foundation
import ImageIO

enum EXIFReader {
    static func read(from data: Data) -> CaptureMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return CaptureMetadata()
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        let make = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
        let model = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
        let lens = exif[kCGImagePropertyExifLensModel] as? String ?? ""
        let focal = number(exif[kCGImagePropertyExifFocalLength]).map { "\(format($0)) mm" } ?? ""
        let aperture = number(exif[kCGImagePropertyExifFNumber]).map { "f/\(format($0))" } ?? ""
        let shutter = number(exif[kCGImagePropertyExifExposureTime]).map(formatShutter) ?? ""
        let isoValue = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? ""
        let latitude = number(gps[kCGImagePropertyGPSLatitude]).map { (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -$0 : $0 }
        let longitude = number(gps[kCGImagePropertyGPSLongitude]).map { (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -$0 : $0 }

        var result = CaptureMetadata(
            camera: [make, model].filter { !$0.isEmpty }.joined(separator: " "), lens: lens, focalLength: focal,
            aperture: aperture, shutterSpeed: shutter, iso: isoValue.map { "ISO \($0)" } ?? "", capturedAt: date,
            latitude: latitude, longitude: longitude, source: .exif
        )
        if result.recognizedCount == 0 { result.source = .manual }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func formatShutter(_ value: Double) -> String {
        value >= 1 ? "\(format(value)) s" : "1/\(Int((1 / value).rounded())) s"
    }
}
