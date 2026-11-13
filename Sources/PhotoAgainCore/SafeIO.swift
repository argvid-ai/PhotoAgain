import Darwin
import Foundation

/// Local-only input handle. Intentionally not Codable; never include in public summaries.
public struct LocalInput: Sendable {
  public let url: URL
  fileprivate let identity: String
  fileprivate init(url: URL, identity: String) {
    self.url = url
    self.identity = identity
  }
}
public enum SafeIO {
  private static func fail() -> ContractError {
    .invalid("unsafe, changed, inaccessible or oversized local file")
  }
  private static func canonical(_ url: URL) -> URL {
    var path = url.standardizedFileURL.path
    // macOS system aliases only. User-controlled symlinks are rejected component by component.
    if path == "/tmp" || path.hasPrefix("/tmp/") { path = "/private" + path }
    if path == "/var" || path.hasPrefix("/var/") { path = "/private" + path }
    return URL(fileURLWithPath: path)
  }
  private static func parent(_ url: URL) throws -> (Int32, String) {
    guard url.isFileURL else { throw fail() }
    let parts = canonical(url).pathComponents.filter { $0 != "/" }
    guard let name = parts.last, name != ".", name != ".." else { throw fail() }
    var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard fd >= 0 else { throw fail() }
    for part in parts.dropLast() {
      let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      close(fd)
      guard next >= 0 else { throw fail() }
      fd = next
    }
    return (fd, name)
  }
  private static func openRead(_ url: URL) throws -> Int32 {
    let (fd, name) = try parent(url)
    defer { close(fd) }
    let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard file >= 0 else { throw fail() }
    return file
  }
  private static func fingerprint(_ fd: Int32, regular: Bool = true) throws -> String {
    var info = stat()
    guard fstat(fd, &info) == 0, !regular || (info.st_mode & S_IFMT) == S_IFREG else {
      throw fail()
    }
    return
      "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
  }
  public static func inspect(_ url: URL) throws -> LocalInput {
    let fd = try openRead(url)
    defer { close(fd) }
    return .init(url: canonical(url), identity: try fingerprint(fd))
  }
  public static func read(_ input: LocalInput, maximumBytes: Int = 50_000_000) throws -> Data {
    guard maximumBytes > 0 else { throw fail() }
    let fd = try openRead(input.url)
    defer { close(fd) }
    guard try fingerprint(fd) == input.identity else { throw fail() }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_size <= maximumBytes else { throw fail() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
      let count = Darwin.read(fd, &buffer, buffer.count)
      if count < 0 {
        if errno == EINTR { continue }
        throw fail()
      }
      if count == 0 { break }
      guard result.count <= maximumBytes - count else { throw fail() }
      result.append(contentsOf: buffer.prefix(count))
    }
    guard try fingerprint(fd) == input.identity else { throw fail() }
    return result
  }
  public static func writeNew(_ data: Data, to url: URL) throws {
    let (directory, name) = try parent(url)
    defer { close(directory) }
    let fd = openat(
      directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    guard fd >= 0 else {
      throw ContractError.invalid("output exists or parent is unsafe/inaccessible")
    }
    defer { close(fd) }
    do {
      try data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
          let written = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
          if written < 0 && errno == EINTR { continue }
          guard written > 0 else { throw fail() }
          offset += written
        }
      }
      guard fsync(fd) == 0 else { throw fail() }
    } catch {
      unlinkat(directory, name, 0)
      throw error
    }
  }
  public static func expand(_ urls: [URL]) throws -> [LocalInput] {
    guard !urls.isEmpty, urls.count <= 128 else {
      throw ContractError.invalid("expected 1...128 explicit inputs")
    }
    var result = [LocalInput]()
    var seen = Set<String>()
    for url in urls {
      let fd = try openRead(url)
      defer { close(fd) }
      var info = stat()
      guard fstat(fd, &info) == 0 else { throw fail() }
      let candidates: [URL]
      if (info.st_mode & S_IFMT) == S_IFDIR {
        let before = try fingerprint(fd, regular: false)
        let root = canonical(url)
        guard let stream = fdopendir(dup(fd)) else { throw fail() }
        defer { closedir(stream) }
        var entries = 0
        var supported = [URL]()
        while let entry = readdir(stream) {
          let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
              String(cString: $0)
            }
          }
          if name == "." || name == ".." { continue }
          entries += 1
          guard entries <= 4096 else {
            throw ContractError.invalid("flat directory exceeds 4096 entry budget")
          }
          let candidate = root.appendingPathComponent(name)
          if ["jpg", "jpeg", "png", "heic", "heif"].contains(candidate.pathExtension.lowercased()) {
            supported.append(candidate)
            guard supported.count + result.count <= 128 else {
              throw ContractError.invalid("maximum 128 inputs")
            }
          }
        }
        candidates = supported.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard try fingerprint(fd, regular: false) == before else { throw fail() }
      } else {
        candidates = [url]
      }
      for candidate in candidates {
        guard ["jpg", "jpeg", "png", "heic", "heif"].contains(candidate.pathExtension.lowercased())
        else { throw ContractError.invalid("unsupported input extension") }
        let input = try inspect(candidate)
        guard seen.insert(input.identity).inserted else {
          throw ContractError.invalid("duplicate input")
        }
        result.append(input)
        guard result.count <= 128 else { throw ContractError.invalid("maximum 128 inputs") }
      }
    }
    return result
  }
  /// Preflight only, not a multi-file transaction. writeNew still enforces O_EXCL at commit time.
  public static func requireNewOutputs(_ urls: [URL]) throws {
    var destinations = Set<String>()
    for url in urls {
      let (directory, name) = try parent(url)
      defer { close(directory) }
      var directoryInfo = stat()
      guard fstat(directory, &directoryInfo) == 0 else { throw fail() }
      let key =
        "\(directoryInfo.st_dev):\(directoryInfo.st_ino):\(name.precomposedStringWithCanonicalMapping.lowercased())"
      guard destinations.insert(key).inserted else {
        throw ContractError.invalid("output destinations collide")
      }
      var info = stat()
      guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == -1, errno == ENOENT else {
        throw ContractError.invalid("output exists or cannot be checked")
      }
    }
  }
  public static func createNewDirectory(_ url: URL) throws {
    let (directory, name) = try parent(url)
    defer { close(directory) }
    guard mkdirat(directory, name, mode_t(0o700)) == 0 else {
      throw ContractError.invalid("output directory must be new with a safe existing parent")
    }
  }
  public static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(type, from: read(inspect(url), maximumBytes: 8_000_000))
  }
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }
}

/// PRIVATE local mapping: contains source paths and filesystem metadata. Never share as public evidence.
public struct PrivateInputManifest: Codable, Sendable {
  public struct Entry: Codable, Sendable {
    public var assetID: String
    public var path: String
    public var fileIdentity: String
  }
  public var schemaVersion = 1
  public var privacy = "private-local-input-map"
  public var datasetID: String
  public var entries: [Entry]
  public init(evidence: EvidenceDocument, inputs: [LocalInput]) throws {
    guard evidence.assets.count == inputs.count else {
      throw ContractError.invalid("private mapping count mismatch")
    }
    datasetID = evidence.datasetID
    entries = zip(evidence.assets, inputs).map {
      Entry(assetID: $0.0.id, path: $0.1.url.path, fileIdentity: $0.1.identity)
    }
    try validate(referencing: evidence)
  }
  /// Rechecks original local identities; does not read media or infer paths from public IDs.
  public func validate(referencing evidence: EvidenceDocument) throws {
    try evidence.validate()
    guard schemaVersion == 1, privacy == "private-local-input-map", datasetID == evidence.datasetID,
      entries.map(\.assetID) == evidence.assets.map(\.id)
    else { throw ContractError.invalid("invalid private mapping dataset or membership") }
    for entry in entries {
      let input = try SafeIO.inspect(URL(fileURLWithPath: entry.path))
      guard input.identity == entry.fileIdentity else {
        throw ContractError.invalid("private mapped input changed")
      }
    }
  }
}
