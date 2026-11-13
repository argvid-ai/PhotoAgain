import Foundation

public enum ContractError: Error { case invalid(String) }
public enum Capability: String, Codable, Sendable { case assetAnalysis, groupComparison }
public struct Provider: Codable, Equatable, Sendable {
  public var id: String
  public var modelVersion: String
  public var preprocessingVersion: String
  public var capability: Capability
  public init(
    id: String, modelVersion: String, preprocessingVersion: String,
    capability: Capability = .assetAnalysis
  ) {
    self.id = id
    self.modelVersion = modelVersion
    self.preprocessingVersion = preprocessingVersion
    self.capability = capability
  }
  public static let native = Provider(
    id: "apple-vision-reference", modelVersion: "vision-requests-v1",
    preprocessingVersion: "oriented-thumbnail-2560-v1")
}
public enum Signal: String, Codable, Sendable {
  case aesthetics, faceCount, faceCaptureQuality, featurePrint
}
public enum MissingReason: String, Codable, Sendable {
  case unsupportedOS, noFaces, requestFailed, notProvided
}
public struct MissingSignal: Codable, Sendable {
  public var signal: Signal
  public var reason: MissingReason
  public init(_ signal: Signal, _ reason: MissingReason) {
    self.signal = signal
    self.reason = reason
  }
}
public struct AssetEvidence: Codable, Sendable {
  public var id: String
  public var provider: Provider
  public var aesthetics: Double?
  public var faceCount: Int?
  public var faceCaptureQuality: Double?
  public var missing: [MissingSignal]
  public init(
    id: String, provider: Provider = .native, aesthetics: Double? = nil, faceCount: Int? = nil,
    faceCaptureQuality: Double? = nil, missing: [MissingSignal] = []
  ) {
    self.id = id
    self.provider = provider
    self.aesthetics = aesthetics
    self.faceCount = faceCount
    self.faceCaptureQuality = faceCaptureQuality
    self.missing = missing
  }
}
public struct CandidateGroup: Codable, Sendable {
  public var id: String
  public var assetIDs: [String]
  public var method: String
  public init(
    id: String, assetIDs: [String],
    method: String = "experimental-featureprint-connected-components-distance-0.35"
  ) {
    self.id = id
    self.assetIDs = assetIDs
    self.method = method
  }
}
public struct EvidenceDocument: Codable, Sendable {
  public var datasetID: String
  public var runtimeOS: String?
  public var schemaVersion = 1
  public var assets: [AssetEvidence]
  public var groups: [CandidateGroup]
  public var synthetic: Bool
  public init(
    datasetID: String = UUID().uuidString, runtimeOS: String? = nil, assets: [AssetEvidence],
    groups: [CandidateGroup] = [], synthetic: Bool = false
  ) {
    self.datasetID = datasetID
    self.runtimeOS = runtimeOS
    self.assets = assets
    self.groups = groups
    self.synthetic = synthetic
  }
  public func validate() throws {
    guard UUID(uuidString: datasetID) != nil, schemaVersion == 1, assets.count <= 128,
      groups.count <= 128
    else { throw ContractError.invalid("unsupported schema or size") }
    var ids = Set<String>()
    for a in assets {
      try validateID(a.id)
      guard ids.insert(a.id).inserted, a.provider.capability == .assetAnalysis else {
        throw ContractError.invalid("duplicate ID or wrong capability")
      }
      for value in [a.provider.id, a.provider.modelVersion, a.provider.preprocessingVersion] {
        try validateID(value)
      }
      for value in [a.aesthetics, a.faceCaptureQuality].compactMap({ $0 }) {
        guard value.isFinite && (0...1).contains(value) else {
          throw ContractError.invalid("signal outside 0...1")
        }
      }
      if let count = a.faceCount {
        guard (0...1000).contains(count) else { throw ContractError.invalid("invalid face count") }
      }
      guard Set(a.missing.map(\.signal)).count == a.missing.count else {
        throw ContractError.invalid("duplicate missing signal")
      }
      for m in a.missing {
        if (m.signal == .aesthetics && a.aesthetics != nil)
          || (m.signal == .faceCount && a.faceCount != nil)
          || (m.signal == .faceCaptureQuality && a.faceCaptureQuality != nil)
        {
          throw ContractError.invalid("signal both present and missing")
        }
      }
    }
    var groupIDs = Set<String>()
    var assigned = Set<String>()
    for g in groups {
      try validateID(g.id)
      try validateID(g.method)
      guard groupIDs.insert(g.id).inserted, g.assetIDs.count >= 2, g.assetIDs.count <= 128 else {
        throw ContractError.invalid("invalid group")
      }
      for id in g.assetIDs {
        guard ids.contains(id), assigned.insert(id).inserted else {
          throw ContractError.invalid("foreign or repeated group member")
        }
      }
    }
  }
}
public enum Goal: String, Codable, Sendable {
  case representative
  case keepVariety = "keep-variety"
}
public struct Recipe: Codable, Sendable {
  public var schemaVersion = 1
  public var goal: Goal
  public var desiredCount: Int
  public var minimumMargin: Double
  public init(goal: Goal = .representative, desiredCount: Int = 1, minimumMargin: Double = 0.05) {
    self.goal = goal
    self.desiredCount = desiredCount
    self.minimumMargin = minimumMargin
  }
  public func validate() throws {
    guard schemaVersion == 1, (1...128).contains(desiredCount), minimumMargin.isFinite,
      (0...1).contains(minimumMargin)
    else { throw ContractError.invalid("invalid recipe") }
  }
}
public enum DecisionAction: String, Codable, Sendable { case keep, exclude, undo }
public struct Decision: Codable, Sendable {
  public var id: String
  public var assetID: String
  public var action: DecisionAction
  public var undoDecisionID: String?
  public init(id: String, assetID: String, action: DecisionAction, undoDecisionID: String? = nil) {
    self.id = id
    self.assetID = assetID
    self.action = action
    self.undoDecisionID = undoDecisionID
  }
}
public struct DecisionLedger: Codable, Sendable {
  public var datasetID: String
  public var schemaVersion = 1
  public var entries: [Decision]
  public init(datasetID: String, entries: [Decision] = []) {
    self.datasetID = datasetID
    self.entries = entries
  }
  public func effective(knownIDs: Set<String>, datasetID: String) throws -> [String: DecisionAction]
  {
    guard self.datasetID == datasetID, UUID(uuidString: datasetID) != nil, schemaVersion == 1,
      entries.count <= 10000
    else { throw ContractError.invalid("invalid ledger schema or size") }
    var seen = [String: Decision]()
    var undone = Set<String>()
    for entry in entries {
      try validateID(entry.id)
      guard knownIDs.contains(entry.assetID), seen[entry.id] == nil else {
        throw ContractError.invalid("foreign asset or duplicate decision")
      }
      if entry.action == .undo {
        guard let target = entry.undoDecisionID, let original = seen[target],
          original.action != .undo, original.assetID == entry.assetID,
          undone.insert(target).inserted
        else { throw ContractError.invalid("invalid undo target") }
      } else if entry.undoDecisionID != nil {
        throw ContractError.invalid("unexpected undo target")
      }
      seen[entry.id] = entry
    }
    var result = [String: DecisionAction]()
    for entry in entries where entry.action != .undo && !undone.contains(entry.id) {
      result[entry.assetID] = entry.action
    }
    return result
  }
}
public struct RecommendationDocument: Codable, Sendable {
  public var datasetID: String
  public var schemaVersion = 1
  public var recipe: Recipe
  public var recommendedIDs: [String]
  public var explicitKeeps: [String]
  public var explicitExcludes: [String]
  public var reasons: [String]
  public var abstained: Bool
  public func validate(referencing evidence: EvidenceDocument) throws {
    try evidence.validate()
    try recipe.validate()
    let ids = recommendedIDs + explicitKeeps + explicitExcludes
    let remaining = max(0, recipe.desiredCount - explicitKeeps.count)
    guard schemaVersion == 1, datasetID == evidence.datasetID, Set(ids).count == ids.count,
      Set(ids).isSubset(of: Set(evidence.assets.map(\.id))), recommendedIDs.count <= remaining,
      abstained || recommendedIDs.count == remaining
    else { throw ContractError.invalid("invalid recommendation dataset, IDs or count") }
  }
}
public enum Policy {
  public static func recommend(
    _ evidence: EvidenceDocument, recipe: Recipe, ledger: DecisionLedger? = nil
  ) throws -> RecommendationDocument {
    try evidence.validate()
    try recipe.validate()
    let decisions = try (ledger ?? DecisionLedger(datasetID: evidence.datasetID)).effective(
      knownIDs: Set(evidence.assets.map(\.id)), datasetID: evidence.datasetID)
    let keeps = decisions.filter { $0.value == .keep }.map(\.key).sorted()
    let excludes = decisions.filter { $0.value == .exclude }.map(\.key).sorted()
    var reasons = [
      "Experimental native aesthetics policy; normalized Vision overallScore; no cross-provider score fusion."
    ]
    var selected = [String]()
    let remaining = max(0, recipe.desiredCount - keeps.count)
    // Model/preprocessing identity is exact: an uncalibrated score version never joins this ranking.
    let eligible = evidence.assets.filter {
      $0.provider == .native && $0.aesthetics != nil && decisions[$0.id] == nil
    }.sorted {
      if $0.aesthetics! == $1.aesthetics! { return $0.id < $1.id }
      return $0.aesthetics! > $1.aesthetics!
    }
    var candidates = eligible
    if recipe.goal == .keepVariety {
      var membership = [String: String]()
      for group in evidence.groups { for id in group.assetIDs { membership[id] = group.id } }
      var used = Set(keeps.compactMap { membership[$0] })
      if remaining > 0 {
        for group in evidence.groups where !used.contains(group.id) {
          let ranked = eligible.filter { group.assetIDs.contains($0.id) }
          if ranked.count >= 2
            && ranked[0].aesthetics! - ranked[1].aesthetics! < recipe.minimumMargin
          {
            reasons.append(
              "Native scores within a similarity group are too close; abstaining from automatic variety selection."
            )
            return .init(
              datasetID: evidence.datasetID, recipe: recipe, recommendedIDs: [],
              explicitKeeps: keeps, explicitExcludes: excludes, reasons: reasons, abstained: true)
          }
        }
      }
      candidates = eligible.filter { a in
        guard let group = membership[a.id] else { return true }
        return used.insert(group).inserted
      }
      reasons.append(
        "At most one asset per experimental similarity component; this does not establish semantic diversity."
      )
    }
    var abstained = false
    if remaining > 0 {
      let count = min(remaining, candidates.count)
      if count == 0 {
        abstained = true
        reasons.append("No eligible native aesthetics evidence; unknown is not zero.")
      } else if candidates.count > count
        && candidates[count - 1].aesthetics! - candidates[count].aesthetics! < recipe.minimumMargin
      {
        abstained = true
        reasons.append(
          "Score margin at requested selection boundary is too small; user choice required.")
      } else {
        selected = Array(candidates.prefix(count)).map(\.id)
        reasons.append(
          "Selected descending native aesthetics with minimum boundary margin \(recipe.minimumMargin)."
        )
        if count < remaining {
          abstained = true
          reasons.append("Insufficient eligible evidence to fill requested count.")
        }
      }
    }
    if !keeps.isEmpty || !excludes.isEmpty {
      reasons.append(
        "Explicit decisions preserved separately; recommendations do not change the ledger.")
    }
    if keeps.count > recipe.desiredCount {
      reasons.append("Explicit keeps exceed requested count and take precedence.")
    }
    return .init(
      datasetID: evidence.datasetID, recipe: recipe, recommendedIDs: selected, explicitKeeps: keeps,
      explicitExcludes: excludes, reasons: reasons, abstained: abstained)
  }
}
private func validateID(_ value: String) throws {
  guard !value.isEmpty, value.utf8.count <= 160,
    value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil,
    !value.contains("..")
  else { throw ContractError.invalid("invalid opaque identifier") }
}

/// Advisory comparisons are separate from asset scoring and are never consumed by Policy.
public struct GroupComparisonDocument: Codable, Sendable {
  public var datasetID: String
  public var schemaVersion = 1
  public var provider: Provider
  public var groupID: String
  public var assetIDs: [String]
  public var preferredIDs: [String]
  public var abstained: Bool
  public init(
    datasetID: String, provider: Provider, groupID: String, assetIDs: [String],
    preferredIDs: [String] = [], abstained: Bool = true
  ) {
    self.datasetID = datasetID
    self.provider = provider
    self.groupID = groupID
    self.assetIDs = assetIDs
    self.preferredIDs = preferredIDs
    self.abstained = abstained
  }
  public func validate(referencing evidence: EvidenceDocument) throws {
    try evidence.validate()
    guard datasetID == evidence.datasetID, schemaVersion == 1,
      provider.capability == .groupComparison,
      let group = evidence.groups.first(where: { $0.id == groupID }),
      Set(assetIDs) == Set(group.assetIDs), assetIDs.count == group.assetIDs.count,
      Set(preferredIDs).count == preferredIDs.count, Set(preferredIDs).isSubset(of: Set(assetIDs)),
      !abstained || preferredIDs.isEmpty
    else { throw ContractError.invalid("invalid advisory group comparison") }
    for value in [provider.id, provider.modelVersion, provider.preprocessingVersion] {
      try validateID(value)
    }
  }
}
