import CoreGraphics
import Foundation
import ImageIO
import PhotoAgainCore
import XCTest

@testable import PhotoAgainOllama

final class OllamaTests: XCTestCase {
  let dataset = "B5C68C04-5345-42BF-9754-8E2F350AC500"
  let ids = ["asset-0001", "asset-0002"]
  func payload(_ changes: [String: Any] = [:]) throws -> Data {
    var object: [String: Any] = [
      "schemaVersion": 1, "datasetID": dataset,
      "memberIDs": ids, "abstained": false,
      "hints": [["memberIDs": ids, "category": "focus", "region": "center"]],
    ]
    object.merge(changes) { _, new in new }
    return try JSONSerialization.data(withJSONObject: object)
  }
  func testExactMembershipAndSchemaRejectsForeignDuplicateAndUnknownText() throws {
    _ = try GroupHints.decode(payload(), datasetID: dataset, memberIDs: ids)
    for change: [String: Any] in [
      ["datasetID": UUID().uuidString], ["schemaVersion": 2],
      ["memberIDs": ["asset-0001", "foreign"]], ["memberIDs": ["asset-0001", "asset-0001"]],
      ["memberIDs": ids.reversed().map { $0 }], ["command": "do something"],
      ["hints": [["memberIDs": ["foreign"], "category": "focus", "region": "center"]]],
      ["hints": [["memberIDs": ids + ids, "category": "focus", "region": "center"]]],
      ["hints": [["memberIDs": ids, "category": "focus", "region": "center", "text": "claim"]]],
      ["abstained": true], ["hints": []],
    ] {
      XCTAssertThrowsError(
        try GroupHints.decode(payload(change), datasetID: dataset, memberIDs: ids))
    }
  }
}

private actor FixtureTransport: OllamaTransport {
  enum Mode: Sendable {
    case valid, unknown, noVision, remoteTag, remoteShow, badDigest, malformed, oversized, timeout
    case unfinished, toolCall, badHints
    case numericDone, stringDone, nullDone, booleanSize, stringSize, nullSize
  }
  let mode: Mode
  var requests = [URLRequest]()
  init(_ mode: Mode = .valid) { self.mode = mode }
  func send(_ request: URLRequest, maximumBytes: Int) async throws -> Data {
    requests.append(request)
    if mode == .timeout { throw URLError(.timedOut) }
    if mode == .malformed { return Data("not json".utf8) }
    if mode == .oversized { return Data(repeating: 0, count: maximumBytes + 1) }
    let model = "example-vision:local"
    let digest = String(repeating: "a", count: 64)
    let object: [String: Any]
    switch request.url!.path {
    case "/api/tags":
      var tag: [String: Any] = [
        "name": model, "model": model, "digest": mode == .badDigest ? "bad" : digest,
        "size": 1000, "modified_at": "2026-11-13T00:00:00Z", "details": ["format": "gguf"],
      ]
      if mode == .booleanSize { tag["size"] = true }
      if mode == .stringSize { tag["size"] = "1000" }
      if mode == .nullSize { tag["size"] = NSNull() }
      if mode == .remoteTag { tag["remote_host"] = "https://example.org" }
      object = ["models": mode == .unknown ? [] : [tag]]
    case "/api/show":
      var show: [String: Any] = [
        "capabilities": mode == .noVision ? ["completion"] : ["completion", "vision"],
        "license": "Example license https://example.org/license", "details": ["format": "gguf"],
        "model_info": ["general.architecture": "example"],
      ]
      if mode == .remoteShow { show["remote_model"] = "elsewhere" }
      object = show
    case "/api/chat":
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      let messages = body["messages"] as! [[String: Any]]
      let context =
        try JSONSerialization.jsonObject(with: Data((messages[1]["content"] as! String).utf8))
        as! [String: Any]
      let content = try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "datasetID": context["datasetID"]!, "memberIDs": context["memberIDs"]!,
        "abstained": false,
        "hints": [
          [
            "memberIDs": mode == .badHints ? ["foreign"] : ["asset-0001", "asset-0002"],
            "category": "focus", "region": "center",
          ]
        ],
      ])
      var message: [String: Any] = [
        "role": "assistant", "content": String(decoding: content, as: UTF8.self),
      ]
      if mode == .toolCall { message["tool_calls"] = [["function": ["name": "execute"]]] }
      let done: Any
      switch mode {
      case .numericDone: done = 1
      case .stringDone: done = "true"
      case .nullDone: done = NSNull()
      default: done = true
      }
      object = [
        "model": model, "message": message, "done": done,
        "done_reason": mode == .unfinished ? "length" : "stop", "total_duration": 1,
      ]
    default: throw OllamaError.unsafeEndpoint
    }
    return try JSONSerialization.data(withJSONObject: object)
  }
}

extension OllamaTests {
  func fixtures() throws -> (URL, [URL]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let context = CGContext(
      data: nil, width: 1600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1600, height: 800))
    let image = context.makeImage()!
    let files = ["one.jpg", "two.jpg"].map { root.appendingPathComponent($0) }
    for file in files {
      let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil)!
      CGImageDestinationAddImage(
        dest, image,
        [
          kCGImagePropertyOrientation: 6,
          kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 10.0, kCGImagePropertyGPSLongitude: 20.0,
          ],
          kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "PRIVATE-SYNTHETIC-MARKER"],
        ] as CFDictionary)
      XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
    return (root, files)
  }

  func testCompletionRequiresJSONBooleanAndCreatesNoOutputForOtherScalars() async throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    for mode: FixtureTransport.Mode in [.numericDone, .stringDone, .nullDone] {
      let transport = FixtureTransport(mode)
      let output = root.appendingPathComponent(UUID().uuidString + ".json")
      do {
        try await OllamaAdapter(transport: transport).writeHints(
          inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true, output: output
        )
        XCTFail("Nonboolean completion accepted: \(mode)")
      } catch { XCTAssertEqual(error as? OllamaError, .invalidResponse) }
      XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "\(mode)")
      let requests = await transport.requests
      XCTAssertEqual(requests.last?.url?.path, "/api/chat")
    }
  }

  func testModelSizeRejectsBooleanStringAndNullBeforeImageBearingChat() async throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    for mode: FixtureTransport.Mode in [.booleanSize, .stringSize, .nullSize] {
      let transport = FixtureTransport(mode)
      let output = root.appendingPathComponent(UUID().uuidString + ".json")
      do {
        try await OllamaAdapter(transport: transport).writeHints(
          inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true, output: output
        )
        XCTFail("Nonnumeric model size accepted: \(mode)")
      } catch { XCTAssertEqual(error as? OllamaError, .invalidMetadata) }
      XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "\(mode)")
      let requests = await transport.requests
      XCTAssertEqual(requests.compactMap { $0.url?.path }, ["/api/tags"], "\(mode)")
    }
  }

  func testAcknowledgementPrecedesReadsAndTransportAndPureValidation() async throws {
    let transport = FixtureTransport()
    let missing = [
      URL(fileURLWithPath: "/nonexistent/one.jpg"), URL(fileURLWithPath: "/nonexistent/two.jpg"),
    ]
    do {
      _ = try await OllamaAdapter(transport: transport).compare(
        inputURLs: missing, model: "example-vision:local", acknowledgedRuntime: false)
      XCTFail("Acknowledgement was bypassed")
    } catch { XCTAssertEqual(error as? OllamaError, .acknowledgementRequired) }
    let calls = await transport.requests
    XCTAssertTrue(calls.isEmpty)
    try OllamaAdapter.validateOptions(
      inputURLs: missing, model: "example-vision:local", acknowledgedRuntime: true)
    for model in ["x:cloud", "remote-model", "https://host/model", "../model", "", "x\n"] {
      XCTAssertThrowsError(
        try OllamaAdapter.validateOptions(
          inputURLs: missing, model: model, acknowledgedRuntime: true))
    }
  }

  func testPreviewAppliesOrientationBoundsAndDropsSourceMetadata() throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = try HintPreview.prepare(SafeIO.inspect(files[0]))
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    XCTAssertEqual(CGImageSourceGetType(source)! as String, "public.jpeg")
    XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 640)
    XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 1280)
    XCTAssertNil(props[kCGImagePropertyGPSDictionary])
    XCTAssertNil(props[kCGImagePropertyTIFFDictionary])
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE-SYNTHETIC-MARKER"))
  }

  func testMockComparisonBindsRequestAndPreservesNativePolicyBytes() async throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    let evidence = EvidenceDocument(
      assets: [AssetEvidence(id: "asset-0001"), AssetEvidence(id: "asset-0002")], groups: [],
      synthetic: true)
    let ledger = DecisionLedger(
      datasetID: evidence.datasetID,
      entries: [Decision(id: "keep-1", assetID: "asset-0001", action: .keep)])
    let recipe = Recipe(goal: .keepVariety, desiredCount: 1)
    let before = try SafeIO.encode(Policy.recommend(evidence, recipe: recipe, ledger: ledger))
    let ledgerBefore = try SafeIO.encode(ledger)
    let transport = FixtureTransport()
    let result = try await OllamaAdapter(transport: transport).compare(
      inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true)
    XCTAssertNotEqual(result.requestID, evidence.datasetID)
    XCTAssertEqual(result.comparison.datasetID, result.requestID)
    XCTAssertEqual(result.comparison.memberIDs, ["asset-0001", "asset-0002"])
    XCTAssertEqual(result.runtimeTrust, "user-confirmed-not-attested")
    XCTAssertEqual(result.comparison.hints.first?.category, .focus)
    XCTAssertEqual(
      try SafeIO.encode(Policy.recommend(evidence, recipe: recipe, ledger: ledger)), before)
    XCTAssertEqual(try SafeIO.encode(ledger), ledgerBefore)
    let encoded = String(decoding: try SafeIO.encode(result), as: UTF8.self)
    for forbidden in [
      root.path, "one.jpg", "two.jpg", "base64", "PRIVATE-SYNTHETIC-MARKER", "license",
    ] { XCTAssertFalse(encoded.contains(forbidden)) }
    let requests = await transport.requests
    XCTAssertEqual(requests.compactMap { $0.url?.path }, ["/api/tags", "/api/show", "/api/chat"])
    let chat = try JSONSerialization.jsonObject(with: requests[2].httpBody!) as! [String: Any]
    XCTAssertEqual(chat["stream"] as? Bool, false)
    XCTAssertNil(chat["tools"])
    XCTAssertNotNil(chat["format"] as? [String: Any])
    let messages = chat["messages"] as! [[String: Any]]
    XCTAssertEqual((messages[1]["images"] as? [String])?.count, 2)
  }

  func testMetadataFailuresNeverSendImagesAndGenerationErrorsProduceNoFile() async throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    for mode: FixtureTransport.Mode in [
      .unknown, .noVision, .remoteTag, .remoteShow, .badDigest, .malformed, .oversized, .timeout,
      .unfinished, .toolCall, .badHints,
    ] {
      let transport = FixtureTransport(mode)
      let output = root.appendingPathComponent(UUID().uuidString + ".json")
      do {
        try await OllamaAdapter(transport: transport).writeHints(
          inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true, output: output
        )
        XCTFail("Unsafe response accepted: \(mode)")
      } catch {}
      XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
      let requests = await transport.requests
      if ![.unfinished, .toolCall, .badHints].contains(mode) {
        XCTAssertFalse(requests.contains { $0.url?.path == "/api/chat" })
      } else {
        XCTAssertEqual(requests.last?.url?.path, "/api/chat")
      }
    }
  }

  func testNoClobberAndDirectoryInputFailBeforeTransport() async throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("existing.json")
    let original = Data("original".utf8)
    try original.write(to: output)
    let transport = FixtureTransport()
    do {
      try await OllamaAdapter(transport: transport).writeHints(
        inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true, output: output)
      XCTFail("overwrote existing output")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: output), original)
    // Directory with a supported extension must still be rejected as non-regular.
    let directory = root.appendingPathComponent("directory.jpg")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
      _ = try await OllamaAdapter(transport: transport).compare(
        inputURLs: [directory, files[0]], model: "example-vision:local", acknowledgedRuntime: true)
      XCTFail("expanded a directory")
    } catch {}
    let requests = await transport.requests
    XCTAssertTrue(requests.isEmpty)
  }

  func testEndpointAllowlistAndRedirectRefusal() throws {
    for endpoint in [
      "http://example.org:11434/api/tags", "https://127.0.0.1:11434/api/tags",
      "http://127.0.0.1:80/api/tags", "http://127.0.0.1:11434/api/pull",
      "http://127.0.0.1:11434/api/tags?x=1", "http://user:pass@127.0.0.1:11434/api/tags",
    ] {
      XCTAssertThrowsError(try LoopbackTransport.validate(URLRequest(url: URL(string: endpoint)!)))
    }
    let request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
    try LoopbackTransport.validate(request)
    let config = LoopbackTransport.configuration()
    XCTAssertNil(config.httpCookieStorage)
    XCTAssertNil(config.urlCache)
    XCTAssertNil(config.urlCredentialStorage)
    XCTAssertEqual(config.connectionProxyDictionary?.count, 0)
    XCTAssertLessThanOrEqual(config.timeoutIntervalForResource, 90)
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    // An unresumed task is not a request; exercise our redirect delegate directly.
    let task = session.dataTask(with: request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
    let completed = expectation(description: "redirect denied")
    LoopbackTransport().urlSession(
      session, task: task, willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: URL(string: "https://example.org")!)
    ) { request in
      XCTAssertNil(request)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
  }

  func testAbstentionHintCapsAndClosedVocabulary() throws {
    _ = try GroupHints.decode(
      payload(["abstained": true, "hints": []]), datasetID: dataset, memberIDs: ids)
    let hint: [String: Any] = ["memberIDs": ids, "category": "exposure", "region": "wholeFrame"]
    for changes: [String: Any] in [
      ["hints": Array(repeating: hint, count: 9)],
      ["hints": [hint, hint]],
      ["hints": [["memberIDs": ids, "category": "identity", "region": "center"]]],
      ["hints": [["memberIDs": [], "category": "focus", "region": "center"]]],
      ["hints": [["memberIDs": ids, "category": "focus", "region": "outside"]]],
    ] {
      XCTAssertThrowsError(
        try GroupHints.decode(payload(changes), datasetID: dataset, memberIDs: ids))
    }
    XCTAssertThrowsError(
      try GroupHints.decode(Data(repeating: 32, count: 32_769), datasetID: dataset, memberIDs: ids))
  }

  func testSuccessfulWriteUsesNewPrivateModeFileAndRejectsSecondWrite() async throws {
    let (root, files) = try fixtures()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("hints.json")
    let adapter = OllamaAdapter(transport: FixtureTransport())
    try await adapter.writeHints(
      inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true, output: output)
    let original = try Data(contentsOf: output)
    let result = try JSONDecoder().decode(GroupHintsDocument.self, from: original)
    try result.comparison.validate(
      datasetID: result.requestID, memberIDs: ["asset-0001", "asset-0002"])
    XCTAssertEqual(
      (try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber)?
        .intValue, 0o600)
    do {
      try await adapter.writeHints(
        inputURLs: files, model: "example-vision:local", acknowledgedRuntime: true, output: output)
      XCTFail("second write succeeded")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: output), original)
  }

  func testCancelledTaskDoesNotReadOrContactRuntime() async throws {
    let transport = FixtureTransport()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await OllamaAdapter(transport: transport).compare(
        inputURLs: [
          URL(fileURLWithPath: "/missing/a.jpg"), URL(fileURLWithPath: "/missing/b.jpg"),
        ], model: "example-vision:local", acknowledgedRuntime: true)
    }
    do {
      _ = try await task.value
      XCTFail("ignored cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    let requests = await transport.requests
    XCTAssertTrue(requests.isEmpty)
  }
}
