import CoreGraphics
import Foundation
import ImageIO
import PhotoAgainCore
import PhotoAgainOllama
import PhotoAgainVision
import UniformTypeIdentifiers

let help = """
  PhotoAgain — experimental local Apple Vision reference framework (macOS 14+)
    photoagain --help
    photoagain group-hints --input FILE --input FILE [--input FILE ...] --model EXACT_LOCAL_TAG --output NEW_JSON --acknowledge-runtime user-confirmed [--check-only true]
    photoagain demo --output NEW_DIRECTORY
    photoagain analyze --input FILE_OR_FLAT_DIRECTORY [--input ...] --output NEW_JSON [--private-manifest NEW.private.json]
    photoagain recommend --input EVIDENCE_JSON --recipe RECIPE_JSON [--decisions LEDGER_JSON] --output NEW_JSON
    photoagain validate --input JSON [--kind evidence|recipe|decisions|recommendations] [--evidence EVIDENCE_JSON]
  Explicit JPEG/PNG/single-frame HEIC inputs only; no recursion, symlinks or output overwrite.
  Up to 128 images, 50 MB compressed each, 100 megapixels; previews at most 2560 pixels.
  macOS 14 records missing aesthetics; policy abstains without eligible native aesthetics.
  group-hints: 2–4 explicit files; 1280-pixel metadata-stripped previews; optional Ollama at fixed loopback.
  Acknowledge a user-controlled runtime: loopback cannot certify its outbound behavior.
  --check-only true validates argument syntax only, without image/metadata reads or runtime requests.
  Demo images are synthetic test fixtures, not a real-photo quality benchmark.
  Public JSON contains opaque IDs and evidence, never original paths or image bytes.
  Each analysis creates a new datasetID; never reuse an old ledger across analysis batches.
  --private-manifest explicitly writes a separate 0600 local ID/path map; never share it as public evidence.
  Directory entry budget: 4096. Public/private output pairs are preflighted but are not transactional.
  """
struct Arguments {
  var command: String
  var options: [String: [String]] = [:]
  init(_ args: [String]) throws {
    guard let first = args.first else {
      command = "--help"
      return
    }
    command = first
    var i = 1
    while i < args.count {
      let key = args[i]
      guard key.hasPrefix("--"), i + 1 < args.count, !args[i + 1].hasPrefix("--") else {
        throw ContractError.invalid("expected option value")
      }
      options[key, default: []].append(args[i + 1])
      i += 2
    }
  }
  func check(_ allowed: Set<String>) throws {
    guard Set(options.keys).isSubset(of: allowed),
      options.allSatisfy({ $0.key == "--input" || $0.value.count == 1 })
    else { throw ContractError.invalid("unknown or repeated option") }
  }
  func one(_ key: String) throws -> String {
    guard let values = options[key], values.count == 1 else {
      throw ContractError.invalid("missing or repeated required option")
    }
    return values[0]
  }
  func url(_ key: String) throws -> URL { URL(fileURLWithPath: try one(key)) }
}
func write<T: Encodable>(_ object: T, _ url: URL) throws {
  try SafeIO.writeNew(SafeIO.encode(object), to: url)
}
func demo(_ directory: URL) throws {
  try SafeIO.createNewDirectory(directory)
  for i in 1...3 {
    guard
      let context = CGContext(
        data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw ContractError.invalid("image context failed") }
    context.setFillColor(CGColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
    context.setFillColor(CGColor(red: 0.95, green: 0.7, blue: 0.25, alpha: 1))
    context.fillEllipse(in: CGRect(x: i == 3 ? 160 : 50, y: 50, width: 100, height: 100))
    guard let image = context.makeImage() else {
      throw ContractError.invalid("image fixture failed")
    }
    let data = NSMutableData()
    guard
      let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw ContractError.invalid("image fixture failed") }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else {
      throw ContractError.invalid("image fixture failed")
    }
    try SafeIO.writeNew(data as Data, to: directory.appendingPathComponent("synthetic-\(i).png"))
  }
  let urls = (1...3).map { directory.appendingPathComponent("synthetic-\($0).png") }
  let evidence = try NativeAnalyzer.analyze(SafeIO.expand(urls), synthetic: true)
  let recipe = Recipe(goal: .keepVariety, desiredCount: 2)
  try write(evidence, directory.appendingPathComponent("evidence.json"))
  try write(recipe, directory.appendingPathComponent("recipe.json"))
  try write(
    Policy.recommend(evidence, recipe: recipe),
    directory.appendingPathComponent("recommendations.json"))
  print(
    "Synthetic test completed: \(evidence.assets.count) assets; \(evidence.groups.count) experimental groups. Not a quality benchmark."
  )
}
do {
  let args = try Arguments(Array(CommandLine.arguments.dropFirst()))
  switch args.command {
  case "--help", "help":
    try args.check([])
    print(help)
  case "group-hints":
    try args.check(["--input", "--model", "--output", "--acknowledge-runtime", "--check-only"])
    guard args.options["--acknowledge-runtime"] == ["user-confirmed"] else {
      throw OllamaError.acknowledgementRequired
    }
    let model = try args.one("--model")
    let output = try args.url("--output")
    let inputs = (args.options["--input"] ?? []).map { URL(fileURLWithPath: $0) }
    try OllamaAdapter.validateOptions(inputURLs: inputs, model: model, acknowledgedRuntime: true)
    if let check = args.options["--check-only"] {
      guard check == ["true"] else { throw OllamaError.invalidRequest }
      print("Arguments valid only; no inputs read and no runtime contacted.")
    } else {
      try await OllamaAdapter().writeHints(
        inputURLs: inputs, model: model,
        acknowledgedRuntime: true, output: output)
      print("Unverified check-region hints written; runtime trust is user-confirmed, not attested.")
    }
  case "demo":
    try args.check(["--output"])
    try demo(args.url("--output"))
  case "analyze":
    try args.check(["--input", "--output", "--private-manifest"])
    guard let paths = args.options["--input"] else { throw ContractError.invalid("missing input") }
    let publicOutput = try args.url("--output")
    let privateOutput = try args.options["--private-manifest"].map { _ in
      try args.url("--private-manifest")
    }
    if let privateOutput, !privateOutput.lastPathComponent.hasSuffix(".private.json") {
      throw ContractError.invalid("private manifest must end in .private.json")
    }
    try SafeIO.requireNewOutputs([publicOutput] + (privateOutput.map { [$0] } ?? []))
    let inputs = try SafeIO.expand(paths.map { URL(fileURLWithPath: $0) })
    let evidence = try NativeAnalyzer.analyze(inputs)
    let publicData = try SafeIO.encode(evidence)
    let privateData = try privateOutput.map { _ in
      try SafeIO.encode(PrivateInputManifest(evidence: evidence, inputs: inputs))
    }
    try SafeIO.writeNew(publicData, to: publicOutput)
    if let privateOutput, let privateData {
      do { try SafeIO.writeNew(privateData, to: privateOutput) } catch {
        FileHandle.standardError.write(
          Data(
            "Public evidence was created, but private mapping failed. The output pair is incomplete; multi-file writes are not transactional.\n"
              .utf8))
        throw error
      }
    }
    print("Analyzed \(evidence.assets.count) assets locally.")
  case "recommend":
    try args.check(["--input", "--recipe", "--decisions", "--output"])
    let evidence = try SafeIO.decode(EvidenceDocument.self, from: args.url("--input"))
    let recipe = try SafeIO.decode(Recipe.self, from: args.url("--recipe"))
    let ledger =
      try args.options["--decisions"].map { _ in
        try SafeIO.decode(DecisionLedger.self, from: args.url("--decisions"))
      } ?? DecisionLedger(datasetID: evidence.datasetID)
    let result = try Policy.recommend(evidence, recipe: recipe, ledger: ledger)
    try write(result, args.url("--output"))
    print("Recommendation completed; abstained: \(result.abstained). Originals untouched.")
  case "validate":
    try args.check(["--input", "--kind", "--evidence"])
    let url = try args.url("--input")
    switch args.options["--kind"]?.first ?? "evidence" {
    case "evidence": try SafeIO.decode(EvidenceDocument.self, from: url).validate()
    case "recipe": try SafeIO.decode(Recipe.self, from: url).validate()
    case "decisions":
      let evidence = try SafeIO.decode(EvidenceDocument.self, from: args.url("--evidence"))
      try evidence.validate()
      _ = try SafeIO.decode(DecisionLedger.self, from: url).effective(
        knownIDs: Set(evidence.assets.map(\.id)), datasetID: evidence.datasetID)
    case "recommendations":
      let evidence = try SafeIO.decode(EvidenceDocument.self, from: args.url("--evidence"))
      try evidence.validate()
      try SafeIO.decode(RecommendationDocument.self, from: url).validate(referencing: evidence)
    default: throw ContractError.invalid("unknown validation kind")
    }
    print("Valid version-1 document.")
  default: throw ContractError.invalid("unknown command; use --help")
  }
} catch let error as OllamaError {
  FileHandle.standardError.write(
    Data(
      "PhotoAgain local hints failed: \(error.rawValue). No runtime offline attestation is made. Use --help.\n"
        .utf8))
  exit(1)
} catch {
  // Avoid echoing user paths, filenames or decoder payloads to diagnostic summaries.
  FileHandle.standardError.write(
    Data(
      "PhotoAgain failed: invalid/unsafe input, unsupported document, unavailable operation or existing output. Use --help.\n"
        .utf8))
  exit(1)
}
