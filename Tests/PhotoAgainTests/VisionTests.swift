import CoreGraphics
import ImageIO
import PhotoAgainCore
import PhotoAgainVision
import UniformTypeIdentifiers
import XCTest

final class VisionTests: XCTestCase {
  func testSyntheticPNGAndDuplicateGrouping() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let context = CGContext(
      data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 30, y: 20, width: 30, height: 40))
    let image = context.makeImage()!
    for name in ["a.png", "b.png"] {
      let url = root.appendingPathComponent(name)
      let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
      CGImageDestinationAddImage(dest, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
    let result = try NativeAnalyzer.analyze(SafeIO.expand([root]), synthetic: true)
    XCTAssertNotNil(result.runtimeOS)
    try result.validate()
    XCTAssertEqual(result.assets.count, 2)
    XCTAssertTrue(result.synthetic)
    XCTAssertTrue(
      result.assets.allSatisfy {
        $0.faceCount == 0
          || $0.missing.contains { $0.signal == .faceCount && $0.reason == .requestFailed }
      })
    XCTAssertTrue(
      result.assets.allSatisfy {
        $0.aesthetics != nil || $0.missing.contains { $0.signal == .aesthetics }
      })
    // A sandbox without Vision compute may return explicitly missing feature prints.
    if result.assets.allSatisfy({ !$0.missing.contains { $0.signal == .featurePrint } }) {
      XCTAssertEqual(result.groups.first?.assetIDs, ["asset-0001", "asset-0002"])
    }
    let json = String(data: try SafeIO.encode(result), encoding: .utf8)!
    XCTAssertFalse(json.contains(root.path))
    XCTAssertFalse(json.contains("a.png"))
    XCTAssertFalse(json.contains("embedding"))
  }
  func testInvalidImageRejectedAndEmptySupported() throws {
    XCTAssertEqual(try NativeAnalyzer.analyze([]).assets.count, 0)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".png")
    try Data([1, 2, 3]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertThrowsError(try NativeAnalyzer.analyze([SafeIO.inspect(file)]))
  }
}
