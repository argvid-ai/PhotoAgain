import CoreGraphics
import Foundation
import ImageIO
import PhotoAgainCore
import Vision

/// Experimental Apple primitives adapter, not App algorithm parity. No persistent feature prints.
public enum NativeAnalyzer {
  public static func analyze(_ inputs: [LocalInput], synthetic: Bool = false) throws
    -> EvidenceDocument
  {
    guard inputs.count <= 128 else { throw ContractError.invalid("maximum 128 inputs") }
    var assets = [AssetEvidence]()
    var features = [Int: VNFeaturePrintObservation]()
    for (index, input) in inputs.enumerated() {
      let (evidence, feature) = try autoreleasepool {
        () throws -> (AssetEvidence, VNFeaturePrintObservation?) in
        let data = try SafeIO.read(input)
        guard
          let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
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
              kCGImageSourceThumbnailMaxPixelSize: 2560, kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        else {
          throw ContractError.invalid(
            "invalid, multi-frame or unsupported image; maximum 100 megapixels")
        }
        // ImageIO has already applied EXIF orientation to the bounded thumbnail.
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        var evidence = AssetEvidence(id: String(format: "asset-%04d", index + 1))
        let face = VNDetectFaceCaptureQualityRequest()
        face.revision = VNDetectFaceCaptureQualityRequestRevision3
        do {
          try handler.perform([face])
          let faces = face.results ?? []
          evidence.faceCount = faces.count
          let qualities = faces.compactMap { $0.faceCaptureQuality.map(Double.init) }
          if qualities.count == faces.count && !qualities.isEmpty {
            evidence.faceCaptureQuality = qualities.min()
          } else {
            evidence.missing.append(
              .init(.faceCaptureQuality, faces.isEmpty ? .noFaces : .requestFailed))
          }
        } catch {
          evidence.missing += [
            .init(.faceCount, .requestFailed), .init(.faceCaptureQuality, .requestFailed),
          ]
        }
        if #available(macOS 15.0, *) {
          let aesthetics = VNCalculateImageAestheticsScoresRequest()
          aesthetics.revision = 1
          do {
            try handler.perform([aesthetics])
            if let score = aesthetics.results?.first?.overallScore, score.isFinite {
              evidence.aesthetics = (Double(score) + 1) / 2
            } else {
              evidence.missing.append(.init(.aesthetics, .requestFailed))
            }
          } catch { evidence.missing.append(.init(.aesthetics, .requestFailed)) }
        } else {
          evidence.missing.append(.init(.aesthetics, .unsupportedOS))
        }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        var feature: VNFeaturePrintObservation?
        do {
          try handler.perform([request])
          feature = request.results?.first
        } catch {}
        if feature == nil { evidence.missing.append(.init(.featurePrint, .requestFailed)) }
        return (evidence, feature)
      }
      assets.append(evidence)
      features[index] = feature
    }
    // Experimental connected components at distance <= 0.35; chains may include distant endpoints.
    var parent = Array(assets.indices)
    func root(_ i: Int) -> Int {
      var j = i
      while parent[j] != j { j = parent[j] }
      return j
    }
    for i in assets.indices {
      for j in assets.indices where j > i {
        guard let left = features[i], let right = features[j] else { continue }
        var distance: Float = 0
        if (try? left.computeDistance(&distance, to: right)) != nil, distance.isFinite,
          distance <= 0.35
        {
          parent[root(j)] = root(i)
        }
      }
    }
    var components = [Int: [String]]()
    for i in assets.indices { components[root(i), default: []].append(assets[i].id) }
    let groups = components.keys.sorted().compactMap { key -> CandidateGroup? in
      let ids = components[key]!
      return ids.count > 1 ? .init(id: String(format: "group-%04d", key + 1), assetIDs: ids) : nil
    }
    let document = EvidenceDocument(
      runtimeOS: ProcessInfo.processInfo.operatingSystemVersionString, assets: assets,
      groups: groups, synthetic: synthetic)
    try document.validate()
    return document
  }
}
