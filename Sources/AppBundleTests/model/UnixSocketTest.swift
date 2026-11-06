@testable import AppBundle
import Common
import Darwin
import Foundation
import XCTest

/// A connected socket pair: the raw fd stands in for a hostile client that writes bytes by hand,
/// `conn` is the side under test. No listener needed.
private func socketPair() -> (peerFd: Int32, conn: UnixSocketConnection) {
    var fds: [Int32] = [0, 0]
    check(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
    return (fds[0], UnixSocketConnection(fd: fds[1]))
}

/// Write a length prefix with no payload behind it, the way a hostile client would.
private func writeRawHeader(_ fd: Int32, _ len: UInt32) {
    var beLen = len.bigEndian
    check(withUnsafeBytes(of: &beLen) { Darwin.write(fd, $0.baseAddress, 4) } == 4)
}

final class UnixSocketTest: XCTestCase {
    func testRoundTrip() throws {
        let (peerFd, conn) = socketPair()
        defer { Darwin.close(peerFd); conn.close() }
        UnixSocketConnection(fd: peerFd).sendMessage(Data("hello".utf8))
        assertEquals(try conn.recvMessage(), Data("hello".utf8))
    }

    func testRejectsOversizedFrameHeader() {
        let (peerFd, conn) = socketPair()
        defer { Darwin.close(peerFd); conn.close() }
        conn.setReadTimeout(seconds: 1) // so an unguarded read fails instead of hanging the suite
        writeRawHeader(peerFd, UnixSocketConnection.maxFrameSize + 1)
        assertThrowsFrameTooLarge { try conn.recvMessage() }
    }

    func testRejectsMaxUInt32FrameHeader() {
        let (peerFd, conn) = socketPair()
        defer { Darwin.close(peerFd); conn.close() }
        conn.setReadTimeout(seconds: 1)
        writeRawHeader(peerFd, UInt32.max) // uncapped, this reserves 4 GiB
        assertThrowsFrameTooLarge { try conn.recvMessage() }
    }

    func testAcceptsHeaderAtTheLimit() throws {
        let (peerFd, conn) = socketPair()
        defer { Darwin.close(peerFd); conn.close() }
        conn.setReadTimeout(seconds: 1)
        writeRawHeader(peerFd, UnixSocketConnection.maxFrameSize)
        // Legal header, so we wait for the (never sent) payload and time out rather than throw.
        assertNil(try conn.recvMessage())
    }

    func testReadTimeoutEndsASilentConnection() throws {
        let (peerFd, conn) = socketPair()
        defer { Darwin.close(peerFd); conn.close() }
        conn.setReadTimeout(seconds: 1)
        let start = Date()
        assertNil(try conn.recvMessage()) // client connected and never spoke
        assertTrue(Date().timeIntervalSince(start) < 10)
    }

    func testWriteToAPeerThatHungUpFailsInsteadOfRaisingSigpipe() {
        let (peerFd, conn) = socketPair()
        defer { conn.close() }
        Darwin.close(peerFd) // the CLI was Ctrl-C'd before the reply
        // Without SO_NOSIGPIPE this write kills the whole process, test runner included.
        assertFalse(conn.sendMessage(Data("reply".utf8)))
    }

    private func assertThrowsFrameTooLarge(_ body: () throws -> Data?, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try body()
            XCTFail("Expected UnixSocketError.frameTooLarge", file: file, line: line)
        } catch let e as UnixSocketError {
            if case .frameTooLarge = e { return }
            XCTFail("Unexpected \(e)", file: file, line: line)
        } catch {
            XCTFail("Unexpected \(error)", file: file, line: line)
        }
    }
}
