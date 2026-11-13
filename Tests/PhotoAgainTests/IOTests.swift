import Foundation
import PhotoAgainCore
import XCTest

final class IOTests: XCTestCase {
  func temporary() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
    addTeardownBlock { try? FileManager.default.removeItem(at: u) }
    return u
  }
  func testNoClobberAndChangedInput() throws {
    let root = try temporary()
    let file = root.appendingPathComponent("test.png")
    try Data([1, 2]).write(to: file)
    XCTAssertThrowsError(try SafeIO.writeNew(Data([9]), to: file))
    XCTAssertEqual(try Data(contentsOf: file), Data([1, 2]))
    let input = try SafeIO.inspect(file)
    try Data([3, 4, 5]).write(to: file)
    XCTAssertThrowsError(try SafeIO.read(input))
    let output = root.appendingPathComponent("new.json")
    try SafeIO.writeNew(Data([7]), to: output)
    XCTAssertEqual(try Data(contentsOf: output), Data([7]))
  }
  func testSymlinksMissingAndOversizeAreRejected() throws {
    let root = try temporary()
    let file = root.appendingPathComponent("test.png")
    try Data([1, 2]).write(to: file)
    let link = root.appendingPathComponent("link.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    XCTAssertThrowsError(try SafeIO.inspect(link))
    XCTAssertThrowsError(try SafeIO.inspect(root.appendingPathComponent("missing")))
    XCTAssertThrowsError(try SafeIO.read(SafeIO.inspect(file), maximumBytes: 1))
    let dirlink = root.appendingPathComponent("dirlink")
    try FileManager.default.createSymbolicLink(at: dirlink, withDestinationURL: root)
    XCTAssertThrowsError(try SafeIO.writeNew(Data(), to: dirlink.appendingPathComponent("escape")))
  }
  func testFlatExpansionDoesNotRecurse() throws {
    let root = try temporary()
    try Data([1]).write(to: root.appendingPathComponent("a.png"))
    let sub = root.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
    try Data([2]).write(to: sub.appendingPathComponent("b.png"))
    XCTAssertEqual(try SafeIO.expand([root]).count, 1)
  }
  func testDirectoryEntryBudget() throws {
    let root = try temporary()
    for i in 0...4096 { try Data().write(to: root.appendingPathComponent("entry-\(i).txt")) }
    XCTAssertThrowsError(try SafeIO.expand([root]))
  }
  func testPrivateMappingRejectsChangedFileAndForeignDataset() throws {
    let root = try temporary()
    let file = root.appendingPathComponent("a.png")
    try Data([1, 2]).write(to: file)
    let evidence = EvidenceDocument(assets: [.init(id: "asset-0001")])
    let map = try PrivateInputManifest(evidence: evidence, inputs: [SafeIO.inspect(file)])
    let decoded = try JSONDecoder().decode(PrivateInputManifest.self, from: SafeIO.encode(map))
    try decoded.validate(referencing: evidence)
    XCTAssertThrowsError(
      try decoded.validate(referencing: EvidenceDocument(assets: evidence.assets)))
    try Data([3, 4, 5]).write(to: file)
    XCTAssertThrowsError(try decoded.validate(referencing: evidence))
  }
}
