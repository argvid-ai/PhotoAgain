import CoreGraphics
import Foundation
import ImageIO
import PhotoAgainCore

public enum HintPreview {
  /// Caller must gate runtime acknowledgement before inspecting any inputs.
  static func prepare(_ input: LocalInput) throws -> Data {
    try autoreleasepool {
      let data = try SafeIO.read(input)
      guard
        let source = CGImageSourceCreateWithData(
          data as CFData,
          [kCGImageSourceShouldCache: false] as CFDictionary),
        CGImageSourceGetCount(source) == 1,
        let type = CGImageSourceGetType(source) as String?,
        ["public.jpeg", "public.png", "public.heic", "public.heif"].contains(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0, width <= 100_000, height <= 100_000,
        Int64(width) * Int64(height) <= 100_000_000,
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
      else { throw OllamaError.invalidRequest }
      // Redraw pixels into a new RGB image so source profiles/metadata are not copied.
      guard
        let context = CGContext(
          data: nil, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { throw OllamaError.invalidRequest }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      let output = NSMutableData()
      guard let clean = context.makeImage(),
        let destination = CGImageDestinationCreateWithData(
          output, "public.jpeg" as CFString, 1, nil)
      else { throw OllamaError.invalidRequest }
      CGImageDestinationAddImage(
        destination, clean,
        [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
      guard CGImageDestinationFinalize(destination), output.length <= 2_000_000 else {
        throw OllamaError.invalidRequest
      }
      return output as Data
    }
  }
}
