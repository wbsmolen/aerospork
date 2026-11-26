@testable import AppBundle
import AppKit
import XCTest

/// A listed element that counts its window id reads, the `_AXUIElementGetWindow` IPC `identifyWindows` saves.
private final class IdCountingElement: AxUiElementMock, Hashable {
    let windowId: CGWindowID?
    let role: String
    private(set) var idReads = 0
    private(set) var roleReads = 0

    init(_ windowId: CGWindowID?, role: String = kAXWindowRole) {
        self.windowId = windowId
        self.role = role
    }

    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        guard attr.key == kAXRoleAttribute else { return nil }
        roleReads += 1
        return role as? Attr.T
    }

    func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool { false }

    func containingWindowId() -> CGWindowID? {
        idReads += 1
        return windowId
    }

    static func == (lhs: IdCountingElement, rhs: IdCountingElement) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

final class ListedWindowsIndexTest: XCTestCase {
    func testAKnownWindowCostsNoIdRead() {
        let known = IdCountingElement(7)
        let result = identifyWindows([known], known: [known: 7])
        assertEquals(result.map(\.windowId), [7])
        assertEquals(known.idReads, 0)
    }

    func testANewWindowCostsOneIdRead() {
        let known = IdCountingElement(7)
        let new = IdCountingElement(8)
        let result = identifyWindows([known, new], known: [known: 7])
        assertEquals(result.map(\.windowId), [7, 8])
        assertEquals(known.idReads, 0)
        assertEquals(new.idReads, 1)
    }

    /// Finder's desktop is among its children and has no window.
    func testAnElementWithNoWindowIsStillFilteredOut() {
        let desktop = IdCountingElement(nil)
        assertEquals(identifyWindows([desktop], known: [:]).map(\.windowId), [])
        assertEquals(desktop.idReads, 1)
    }

    /// Finder's child walk asks a role of what it does not know, and of nothing it does.
    func testOnlyAMissIsAskedWhetherItIsAWindow() {
        let known = IdCountingElement(7)
        let menuBar = IdCountingElement(9, role: kAXMenuBarRole)
        let new = IdCountingElement(8)
        let result = identifyWindows([known, menuBar, new], known: [known: 7]) { $0.get(Ax.roleAttr) == kAXWindowRole }
        assertEquals(result.map(\.windowId), [7, 8])
        assertEquals(known.roleReads, 0)
        assertEquals(menuBar.roleReads, 1)
    }

    /// The index rests on `AXUIElement` hashing by `CFHash`/`CFEqual`, not by identity: each read of a list hands
    /// back new objects for the same elements. Creating an element is local, so this sends no AX message.
    func testTwoReadsOfOneElementFindEachOther() {
        let first = AXUIElementCreateApplication(getpid())
        let second = AXUIElementCreateApplication(getpid())
        assertEquals([first: UInt32(7)][second], 7)
        assertEquals([first: UInt32(7)][AXUIElementCreateApplication(1)], nil)
    }
}
