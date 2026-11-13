import Foundation

/// Injection boundary. Implementations must honor cancellation and response bounds.
/// An injected transport is trusted developer code, not a configurable remote endpoint.
public protocol OllamaTransport: Sendable {
  func send(_ request: URLRequest, maximumBytes: Int) async throws -> Data
}

public final class LoopbackTransport: NSObject, OllamaTransport, URLSessionTaskDelegate, Sendable {
  public override init() { super.init() }

  static func validate(_ request: URLRequest) throws {
    guard let url = request.url, url.scheme == "http", url.host == "127.0.0.1",
      url.port == 11434, url.user == nil, url.password == nil, url.query == nil,
      url.fragment == nil,
      ["/api/tags", "/api/show", "/api/chat"].contains(url.path),
      request.httpMethod == (url.path == "/api/tags" ? "GET" : "POST")
    else { throw OllamaError.unsafeEndpoint }
  }

  static func configuration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 90
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.urlCredentialStorage = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.connectionProxyDictionary = [:]
    return config
  }

  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(.cancelAuthenticationChallenge, nil)
  }

  public func send(_ request: URLRequest, maximumBytes: Int) async throws -> Data {
    try Self.validate(request)
    guard maximumBytes > 0, maximumBytes <= 1_048_576 else { throw OllamaError.invalidRequest }
    try Task.checkCancellation()
    let session = URLSession(
      configuration: Self.configuration(), delegate: self, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.url == request.url
    else { throw OllamaError.invalidResponse }
    guard response.expectedContentLength <= maximumBytes else { throw OllamaError.responseTooLarge }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumBytes else { throw OllamaError.responseTooLarge }
      data.append(byte)
    }
    return data
  }
}
