import Foundation
import ImmichClient

public actor MockTransport: HTTPTransport {
    private let responses: [Result<(Data, URLResponse), Error>]
    private let constant: Bool
    private var index = 0
    private var requests: [URLRequest] = []

    public var recordedRequests: [URLRequest] {
        requests
    }

    /// Returns `result` for every request (request count is unbounded).
    public init(result: Result<(Data, URLResponse), Error>) {
        self.responses = [result]
        self.constant = true
    }

    /// Returns each result in order, one per request (the last result repeats once the
    /// sequence is exhausted). Used to drive the resolver's key-first / slug-fallback path.
    public init(sequence: [Result<(Data, URLResponse), Error>]) {
        precondition(!sequence.isEmpty, "MockTransport sequence must not be empty")
        self.responses = sequence
        self.constant = false
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if constant {
            return try responses[0].get()
        }
        let result = responses[Swift.min(index, responses.count - 1)]
        index += 1
        return try result.get()
    }
}
