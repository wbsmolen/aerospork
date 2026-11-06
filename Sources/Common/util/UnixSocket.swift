import Darwin
import Foundation

// Minimal blocking AF_UNIX SOCK_STREAM wrapper with length-prefixed framing.
// Replaces the BlueSocket dependency. Both AeroSpork's server and CLI speak this
// framing: a 4-byte big-endian length header followed by the JSON payload.
// TRADEOFF: blocking I/O on a dedicated dispatch queue / short-lived CLI process — no async event loop needed for a local IPC socket.

private func withSockaddrUn<R>(path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    if pathBytes.count >= cap { return nil } // path too long for sun_path
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: pathBytes) // remaining bytes stay 0 (addr is zero-initialized) -> null terminated
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) }
    }
}

public enum UnixSocketError: Error, Equatable {
    /// The peer announced a frame we refuse to allocate for. The stream is desynchronized
    /// afterwards, so the connection can't be reused.
    case frameTooLarge(UInt32)
}

/// One connected AF_UNIX stream socket. Thread-confined to whoever owns it.
public final class UnixSocketConnection: @unchecked Sendable {
    /// Largest frame we're willing to allocate for. A config file is the biggest legitimate
    /// payload, so 16 MiB is generous; uncapped, a 4-byte header of 0xFFFFFFFF would make the
    /// window manager reserve 4 GiB on behalf of anyone who can reach the socket.
    public static let maxFrameSize: UInt32 = 16 << 20

    private let fd: Int32
    public init(fd: Int32) {
        self.fd = fd
        // A peer that hangs up before the reply (Ctrl-C, a status-bar `timeout`) must make `write` fail
        // with EPIPE, not raise SIGPIPE, whose default action kills the window manager mid-layout.
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Connect to a unix socket path. Returns nil on any failure.
    public static func connect(to path: String) -> UnixSocketConnection? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let ok = withSockaddrUn(path: path) { sa, len in Darwin.connect(fd, sa, len) == 0 } ?? false
        if !ok { Darwin.close(fd); return nil }
        return UnixSocketConnection(fd: fd)
    }

    public func close() { _ = Darwin.close(fd) }

    /// Give up on reads that block longer than `seconds`, reporting them as a dropped connection.
    /// Without it a client that connects and never speaks pins a server task forever.
    public func setReadTimeout(seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private func writeAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard var p = raw.baseAddress else { return true } // empty payload
            var remaining = raw.count
            while remaining > 0 {
                let n = Darwin.write(fd, p, remaining)
                if n > 0 {
                    p = p.advanced(by: n)
                    remaining -= n
                } else if n < 0 && (errno == EINTR || errno == EAGAIN) {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    /// Read exactly `n` bytes. nil on EOF or error (handles partial reads + EINTR).
    private func readExactly(_ n: Int) -> Data? {
        if n == 0 { return Data() }
        var out = Data()
        out.reserveCapacity(n)
        var buf = [UInt8](repeating: 0, count: min(n, 65536))
        var remaining = n
        while remaining > 0 {
            let want = min(remaining, buf.count)
            let r = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, want) }
            if r > 0 {
                out.append(contentsOf: buf[0 ..< r])
                remaining -= r
            } else if r == 0 {
                return nil // EOF before full message
            } else if errno == EINTR {
                continue // interrupted by a signal, not a failure
            } else {
                return nil // includes EAGAIN, which is how SO_RCVTIMEO reports a read timeout
            }
        }
        return out
    }

    /// Send a framed message (4-byte big-endian length + payload).
    @discardableResult
    public func sendMessage(_ data: Data) -> Bool {
        var len = UInt32(data.count).bigEndian
        var framed = Data(bytes: &len, count: 4)
        framed.append(data)
        return writeAll(framed)
    }

    /// Receive one framed message. nil when the peer closed, timed out, or errored.
    /// Throws `frameTooLarge` for a header we won't honour — the length prefix is peer-controlled,
    /// so it is validated before it reaches `reserveCapacity`.
    public func recvMessage() throws -> Data? {
        guard let header = readExactly(4) else { return nil }
        let len = UInt32(bigEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard len <= Self.maxFrameSize else { throw UnixSocketError.frameTooLarge(len) }
        return readExactly(Int(len))
    }
}

/// A listening AF_UNIX stream socket.
public final class UnixSocketListener: @unchecked Sendable {
    private let fd: Int32
    private init(fd: Int32) { self.fd = fd }

    /// Bind + listen on `path`, removing any stale socket file first. nil on failure.
    public static func bind(to path: String, backlog: Int32 = 128) -> UnixSocketListener? {
        unlink(path) // drop stale socket file from a previous run
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let bound = withSockaddrUn(path: path) { sa, len in Darwin.bind(fd, sa, len) == 0 } ?? false
        if !bound { Darwin.close(fd); return nil }
        if listen(fd, backlog) != 0 { Darwin.close(fd); return nil }
        return UnixSocketListener(fd: fd)
    }

    /// Block until a client connects. nil on transient accept error (caller should retry).
    public func accept() -> UnixSocketConnection? {
        let c = Darwin.accept(fd, nil, nil)
        guard c >= 0 else { return nil }
        return UnixSocketConnection(fd: c)
    }

    public func close() { _ = Darwin.close(fd) }
}
