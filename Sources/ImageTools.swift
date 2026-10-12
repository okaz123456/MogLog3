import Foundation
import ImageIO
import UniformTypeIdentifiers

// 写真の撮影情報（EXIF）
struct PhotoMeta {
    var takenAt: Date?
    var latitude: Double?
    var longitude: Double?
}

// 縮小済みの写真（保存前の一時データ）
struct ProcessedPhoto: Identifiable {
    let id = UUID()
    let imageData: Data
    let thumbnailData: Data
    let meta: PhotoMeta
}

enum ImageTools {
    // 元画像 → 縮小版（長辺1600px）・サムネイル（長辺300px）・撮影情報（D-11）
    static func process(_ data: Data,
                        imageMaxPixel: Int = 1600,
                        thumbnailMaxPixel: Int = 300,
                        quality: Double = 0.7) -> ProcessedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = downscaledJPEG(source: source, maxPixel: imageMaxPixel, quality: quality),
              let thumbnail = downscaledJPEG(source: source, maxPixel: thumbnailMaxPixel, quality: quality)
        else { return nil }
        return ProcessedPhoto(imageData: image,
                              thumbnailData: thumbnail,
                              meta: readMeta(source: source))
    }

    // 既存の画像からサムネイルだけを作る（復元用：本体は再圧縮しない）
    static func makeThumbnail(_ data: Data, maxPixel: Int = 300, quality: Double = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downscaledJPEG(source: source, maxPixel: maxPixel, quality: quality)
    }

    // 縮小してJPEGに再圧縮（画像内のEXIFは残らない：D-22）
    private static func downscaledJPEG(source: CGImageSource, maxPixel: Int, quality: Double) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // 縦横の向きを補正
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // 撮影位置と撮影日時を読み取る
    private static func readMeta(source: CGImageSource) -> PhotoMeta {
        var meta = PhotoMeta()
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return meta
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            meta.latitude = lat
            meta.longitude = lon
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            meta.takenAt = formatter.date(from: text)
        }
        return meta
    }
}
