import Foundation

// TO EVERYONE REVERSE-ENGINEERING THE PROTOCOL
// client-server socket API is not public yet. What `aerospork subscribe` prints is: see
// docs/aerospork-subscribe.adoc.
//
// One answer per request, except `subscribe`, which gets one answer per line it prints: the snapshot
// first, then an event in each answer's stdout, all with exit code 0. A refusal, or the end of the
// stream by `enable off`, is a last answer with a non-zero exit code and the reason on stderr.
public struct ServerAnswer: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let serverVersionAndHash: String

    public init(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        serverVersionAndHash: String,
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.serverVersionAndHash = serverVersionAndHash
    }
}

// TO EVERYONE REVERSE-ENGINEERING THE PROTOCOL
// client-server socket API is not public yet.
public struct ClientRequest: Codable, Sendable {
    public let args: [String]
    public let stdin: String

    public init(
        args: [String],
        stdin: String,
    ) {
        self.args = args
        self.stdin = stdin
    }

    public static func decodeJson(_ data: Data) -> Result<ClientRequest, String> {
        Result { try JSONDecoder().decode(Self.self, from: data) }.mapError { $0.localizedDescription }
    }
}
