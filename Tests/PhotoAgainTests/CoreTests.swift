import XCTest

@testable import PhotoAgainCore

final class CoreTests: XCTestCase {
  func testValidationRejectsInvalidSchemaIDsValuesAndGroups() throws {
    var doc = EvidenceDocument(assets: [.init(id: "a", aesthetics: 0.5)])
    try doc.validate()
    doc.schemaVersion = 2
    XCTAssertThrowsError(try doc.validate())
    doc.schemaVersion = 1
    for value in [Double.nan, Double.infinity, -0.1, 1.1] {
      doc.assets[0].aesthetics = value
      XCTAssertThrowsError(try doc.validate())
    }
    doc.assets = [.init(id: "a"), .init(id: "a")]
    XCTAssertThrowsError(try doc.validate())
    doc.assets = [.init(id: "../private.jpg")]
    XCTAssertThrowsError(try doc.validate())
    doc.assets = [.init(id: "a")]
    doc.groups = [.init(id: "g", assetIDs: ["a", "foreign"])]
    XCTAssertThrowsError(try doc.validate())
    XCTAssertThrowsError(try Recipe(desiredCount: 0).validate())
  }
  func testClearWinnerAndCloseScoresAbstain() throws {
    let clear = EvidenceDocument(assets: [
      .init(id: "a", aesthetics: 0.9), .init(id: "b", aesthetics: 0.2),
    ])
    XCTAssertEqual(try Policy.recommend(clear, recipe: .init()).recommendedIDs, ["a"])
    let close = EvidenceDocument(assets: [
      .init(id: "a", aesthetics: 0.9), .init(id: "b", aesthetics: 0.89),
    ])
    XCTAssertTrue(try Policy.recommend(close, recipe: .init()).abstained)
    XCTAssertEqual(try Policy.recommend(close, recipe: .init()).recommendedIDs, [])
  }
  func testEmptySingleUnknownAndForeignProvider() throws {
    XCTAssertTrue(try Policy.recommend(.init(assets: []), recipe: .init()).abstained)
    XCTAssertTrue(try Policy.recommend(.init(assets: [.init(id: "a")]), recipe: .init()).abstained)
    XCTAssertEqual(
      try Policy.recommend(.init(assets: [.init(id: "a", aesthetics: 0.4)]), recipe: .init())
        .recommendedIDs, ["a"])
    let foreign = Provider(id: "other", modelVersion: "v1", preprocessingVersion: "v1")
    let doc = EvidenceDocument(assets: [
      .init(id: "a", aesthetics: 0.4), .init(id: "b", provider: foreign, aesthetics: 1),
    ])
    XCTAssertEqual(try Policy.recommend(doc, recipe: .init()).recommendedIDs, ["a"])
  }
  func testExplicitDecisionAndUndo() throws {
    let doc = EvidenceDocument(assets: [
      .init(id: "a", aesthetics: 0.9), .init(id: "b", aesthetics: 0.2),
    ])
    var ledger = DecisionLedger(
      datasetID: doc.datasetID,
      entries: [
        .init(id: "d1", assetID: "b", action: .keep),
        .init(id: "d2", assetID: "a", action: .exclude),
      ])
    var result = try Policy.recommend(doc, recipe: .init(), ledger: ledger)
    XCTAssertEqual(result.explicitKeeps, ["b"])
    XCTAssertEqual(result.recommendedIDs, [])
    ledger.entries.append(.init(id: "d3", assetID: "a", action: .undo, undoDecisionID: "d2"))
    XCTAssertNil(try ledger.effective(knownIDs: ["a", "b"], datasetID: doc.datasetID)["a"])
    ledger.entries.append(.init(id: "d4", assetID: "b", action: .undo, undoDecisionID: "d1"))
    result = try Policy.recommend(doc, recipe: .init(), ledger: ledger)
    XCTAssertEqual(result.recommendedIDs, ["a"])
    XCTAssertThrowsError(
      try DecisionLedger(
        datasetID: doc.datasetID, entries: [.init(id: "d", assetID: "foreign", action: .keep)]
      ).effective(knownIDs: ["a"], datasetID: doc.datasetID))
  }
  func testVarietyUsesDifferentGroups() throws {
    let doc = EvidenceDocument(
      assets: [
        .init(id: "a", aesthetics: 0.9), .init(id: "b", aesthetics: 0.8),
        .init(id: "c", aesthetics: 0.6),
      ], groups: [.init(id: "g", assetIDs: ["a", "b"])])
    XCTAssertEqual(
      try Policy.recommend(doc, recipe: .init(goal: .keepVariety, desiredCount: 2)).recommendedIDs,
      ["a", "c"])
  }
  func testGroupHintsRejectForeignMembershipAndWrongCapability() throws {
    let evidence = EvidenceDocument(
      assets: [.init(id: "a"), .init(id: "b")], groups: [.init(id: "g", assetIDs: ["a", "b"])])
    let provider = Provider(
      id: "local-advisory", modelVersion: "v1", preprocessingVersion: "v1",
      capability: .groupComparison)
    let valid = GroupComparisonDocument(
      datasetID: evidence.datasetID, provider: provider, groupID: "g", assetIDs: ["a", "b"],
      preferredIDs: ["a"], abstained: false)
    try valid.validate(referencing: evidence)
    var invalid = valid
    invalid.preferredIDs = ["foreign"]
    XCTAssertThrowsError(try invalid.validate(referencing: evidence))
    invalid = valid
    invalid.provider = .native
    XCTAssertThrowsError(try invalid.validate(referencing: evidence))
    invalid = valid
    invalid.assetIDs = ["a"]
    XCTAssertThrowsError(try invalid.validate(referencing: evidence))
    invalid = valid
    invalid.abstained = true
    XCTAssertThrowsError(try invalid.validate(referencing: evidence))
  }
  func testCloseGroupWinnerAbstainsForVariety() throws {
    let evidence = EvidenceDocument(
      assets: [
        .init(id: "a", aesthetics: 0.90), .init(id: "b", aesthetics: 0.89),
        .init(id: "c", aesthetics: 0.4),
      ], groups: [.init(id: "g", assetIDs: ["a", "b"])])
    let result = try Policy.recommend(evidence, recipe: .init(goal: .keepVariety, desiredCount: 2))
    XCTAssertTrue(result.abstained)
    XCTAssertFalse(result.recommendedIDs.contains("a"))
  }
  func testDatasetBindingRejectsSameOrdinalsFromOtherBatch() throws {
    let a = EvidenceDocument(
      assets: [.init(id: "asset-0001", aesthetics: 0.9), .init(id: "asset-0002", aesthetics: 0.2)],
      groups: [.init(id: "g", assetIDs: ["asset-0001", "asset-0002"])])
    let b = EvidenceDocument(assets: a.assets, groups: a.groups)
    XCTAssertNotEqual(a.datasetID, b.datasetID)
    let ledger = DecisionLedger(
      datasetID: a.datasetID, entries: [.init(id: "d", assetID: "asset-0001", action: .keep)])
    XCTAssertThrowsError(try Policy.recommend(b, recipe: .init(), ledger: ledger))
    let rec = try Policy.recommend(a, recipe: .init())
    XCTAssertThrowsError(try rec.validate(referencing: b))
    let provider = Provider(
      id: "advisory", modelVersion: "v1", preprocessingVersion: "v1", capability: .groupComparison)
    let comparison = GroupComparisonDocument(
      datasetID: a.datasetID, provider: provider, groupID: "g",
      assetIDs: ["asset-0001", "asset-0002"])
    XCTAssertThrowsError(try comparison.validate(referencing: b))
    var invalid = a
    invalid.datasetID = ""
    XCTAssertThrowsError(try invalid.validate())
  }
  func testRecommendationRejectsExcessUnknownAndIncompleteCounts() throws {
    let doc = EvidenceDocument(assets: [
      .init(id: "a", aesthetics: 0.9), .init(id: "b", aesthetics: 0.2),
    ])
    var rec = try Policy.recommend(doc, recipe: .init())
    try rec.validate(referencing: doc)
    rec.recommendedIDs = ["a", "b"]
    XCTAssertThrowsError(try rec.validate(referencing: doc))
    rec.recommendedIDs = []
    XCTAssertThrowsError(try rec.validate(referencing: doc))
    rec.abstained = true
    try rec.validate(referencing: doc)
    rec.explicitKeeps = ["a", "b"]
    rec.abstained = false
    try rec.validate(referencing: doc)
    rec.explicitExcludes = ["a"]
    XCTAssertThrowsError(try rec.validate(referencing: doc))
  }
}
