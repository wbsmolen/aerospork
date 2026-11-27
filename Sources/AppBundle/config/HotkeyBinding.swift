import AppKit
import Carbon
import Common
import Foundation
import TOMLKit

// Global hotkeys are registered with Carbon's `RegisterEventHotKey`. Only the currently active
// mode's bindings are registered at any time. A mode switch or a reload changes only the
// registrations that differ (`hotkeyRegistrationPlan`).

/// Bookkeeping for one live Carbon hotkey registration.
@MainActor private struct RegisteredHotKey {
    let ref: EventHotKeyRef
    /// `HotkeyBinding.descriptionWithKeyCode` — the key used to look the binding up in `config` at fire time.
    let bindingId: String
    /// `HotkeyBinding.descriptionWithKeyNotation` — human readable, only used for logging.
    let notation: String
}

/// Maps the Carbon `EventHotKeyID.id` we assign to each registration.
@MainActor private var registeredHotKeys: [UInt32: RegisteredHotKey] = [:]
/// Monotonic id counter for `EventHotKeyID`. Never reused; stale ids are simply absent from the map.
@MainActor private var nextHotKeyId: UInt32 = 0
@MainActor private var eventHandlerInstalled = false

/// Four-char code "ASHk" (AeroSpork HotKey) used as our `EventHotKeyID.signature`.
private let hotKeySignature: UInt32 = 0x4153_486B

private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.command) { result |= UInt32(cmdKey) }
    if flags.contains(.option) { result |= UInt32(optionKey) }
    if flags.contains(.control) { result |= UInt32(controlKey) }
    if flags.contains(.shift) { result |= UInt32(shiftKey) }
    return result
}

@MainActor private func installHotKeyEventHandlerIfNeeded() {
    guard !eventHandlerInstalled else { return }
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &eventType, nil, nil)
    eventHandlerInstalled = true
}

// C callback: Carbon delivers hotkey events on the main run loop. It can't capture context, so it
// reads the hotkey id from the event and hops to the MainActor to look up and run the binding.
private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID,
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    runDetached("hotkey") {
        guard let entry = registeredHotKeys[id], let activeMode else { return }
        let startTime = Date()
        debugLog("HOTKEY: \(entry.notation) pressed")

        debugLog("HOTKEY: Will execute \(config.modes[activeMode]?.bindings[entry.bindingId]?.commands.count ?? 0) command(s)")

        try await runSession(.hotkeyBinding, .checkServerIsEnabledOrDie) { () throws in
            _ = try await config.modes[activeMode]?.bindings[entry.bindingId]?.commands
                .runCmdSeq(.defaultEnv, .emptyStdin)
        }

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        debugLog("HOTKEY: Completed in \(String(format: "%.1f", elapsed))ms")
    }
    return noErr
}

@MainActor var activeMode: String? = mainModeId
@MainActor func activateMode(_ targetMode: String?) {
    // A reload can drop the mode you are in. Staying "in" it registers no hotkeys at all, which
    // includes the one that would get you out. nil is different: it is `enable off`, and stays.
    let targetMode = targetMode.map { config.modes[$0] == nil ? mainModeId : $0 }
    let targetBindings = targetMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    let plan = hotkeyRegistrationPlan(current: registeredHotKeys.mapValues(\.bindingId), target: targetBindings)
    for id in plan.unregister {
        if let entry = registeredHotKeys.removeValue(forKey: id) { UnregisterEventHotKey(entry.ref) }
    }
    installHotKeyEventHandlerIfNeeded()
    for binding in plan.register {
        nextHotKeyId += 1
        let id = nextHotKeyId
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode.carbonKeyCode,
            carbonModifiers(binding.modifiers),
            EventHotKeyID(signature: hotKeySignature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref,
        )
        if status == noErr, let ref {
            registeredHotKeys[id] = RegisteredHotKey(
                ref: ref,
                bindingId: binding.descriptionWithKeyCode,
                notation: binding.descriptionWithKeyNotation,
            )
        } else {
            // Not `debugLog`: its records are not persisted, and "this one key does nothing" is what
            // a bug report asks about after the fact. Usually another app owns the shortcut.
            AppLog.config.error("Hotkey \(binding.descriptionWithKeyNotation, privacy: .public) not registered (status \(status, privacy: .public))")
        }
    }
    let previous = activeMode
    activeMode = targetMode
    // nil is `enable off`, and the reload at startup activates the mode already active: neither fires.
    // A mode change made by an `on-mode-changed` callback does not fire again, or two callbacks that
    // switch A -> B -> A would loop forever.
    if let previous, let targetMode, previous != targetMode, !config.onModeChanged.isEmpty,
       refreshSessionEvent?.isOnModeChanged != true
    {
        runOnModeChanged(previous, targetMode)
    }
}

/// Runs `on-mode-changed` in a session of its own. Detached: `activateMode` runs inside a session,
/// and a session must not wait for another (#refresh-and-layout). A test swaps it, because a real
/// session cannot run headlessly.
@MainActor var runOnModeChanged: @MainActor (_ from: String, _ to: String) -> Void = { from, to in
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    let commands = config.onModeChanged
    runDetached("onModeChangedCallbacks") {
        try await runSession(.onModeChanged, token) {
            _ = try await commands.runCmdSeq(CmdEnv.defaultEnv.copy(\.modeChange, (from: from, to: to)), .emptyStdin)
        }
    }
}

/// The registrations to drop and the bindings to register, to go from `current` (Carbon id to binding
/// id) to `target` (keyed by binding id, as a mode keeps them).
///
/// Unregistering every key and registering again dropped a press queued across the gap (the handler
/// looks its id up later), and let the combo reach the focused app meanwhile. A kept registration
/// behaves the same, because the handler looks the command up in `config` when the key is pressed. A
/// binding another app owns failed to register, so it is not in `current` and is tried again.
// ponytail: a kept registration keeps its old notation, which only debug logs read.
func hotkeyRegistrationPlan(current: [UInt32: String], target: [String: HotkeyBinding]) -> (unregister: [UInt32], register: [HotkeyBinding]) {
    let unregister = current.filter { target[$0.value] == nil }.keys.sorted()
    let kept = Set(current.values)
    let register = target.filter { !kept.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
    return (unregister, register)
}

struct HotkeyBinding: Equatable, Sendable {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: Key
    let commands: [any Command]
    let descriptionWithKeyCode: String
    let descriptionWithKeyNotation: String

    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: [any Command], descriptionWithKeyNotation: String) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.commands = commands
        self.descriptionWithKeyCode = modifiers.isEmpty
            ? keyCode.rawValue
            : modifiers.toString() + "-" + keyCode.rawValue
        self.descriptionWithKeyNotation = descriptionWithKeyNotation
    }

    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.modifiers == rhs.modifiers &&
            lhs.keyCode == rhs.keyCode &&
            lhs.descriptionWithKeyCode == rhs.descriptionWithKeyCode &&
            lhs.commands.count == rhs.commands.count && // `zip` stops at the shorter list
            zip(lhs.commands, rhs.commands).allSatisfy { $0.equals($1) }
    }
}

func parseBindings(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> [String: HotkeyBinding] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: HotkeyBinding] = [:]
    for (binding, rawCommand): (String, TOMLValueConvertible) in rawTable {
        let backtrace = backtrace + .key(binding)
        let binding = parseBinding(binding, backtrace, mapping)
            .flatMap { modifiers, key -> ParsedToml<HotkeyBinding> in
                parseCommandOrCommands(rawCommand).toParsedToml(backtrace).map {
                    HotkeyBinding(modifiers, key, $0, descriptionWithKeyNotation: binding)
                }
            }
            .getOrNil(appendErrorTo: &errors)
        if let binding {
            if result.keys.contains(binding.descriptionWithKeyCode) {
                errors.append(.semantic(backtrace, "'\(binding.descriptionWithKeyCode)' Binding redeclaration"))
            }
            result[binding.descriptionWithKeyCode] = binding
        }
    }
    return result
}

/// The one message for a word that is not a modifier, in a binding and in `mod`.
func modifierError(_ segment: String) -> String {
    "'\(segment)' is not a modifier. Use cmd, alt, ctrl or shift"
}

func parseBinding(_ raw: String, _ backtrace: TomlBacktrace, _ mapping: [String: Key]) -> ParsedToml<(NSEvent.ModifierFlags, Key)> {
    let rawKeys = raw.split(separator: "-")
    let modifiers: ParsedToml<NSEvent.ModifierFlags> = rawKeys.dropLast()
        .mapAllOrFailure {
            modifiersMap[String($0)].orFailure(.semantic(backtrace, modifierError(String($0))))
        }
        .map { NSEvent.ModifierFlags($0) }
    let last = rawKeys.last.map(String.init) ?? ""
    // Single characters are left out of the hint: every word starts with one, so `escape` would get `e`.
    let hint = last.isEmpty ? "" : didYouMeanSuffix(last, from: mapping.keys.filter { $0.count > 1 }.sorted())
    let key: ParsedToml<Key> = mapping[last].orFailure(.semantic(backtrace, "Can't parse the key in '\(raw)' binding" + hint))
    return modifiers.flatMap { modifiers -> ParsedToml<(NSEvent.ModifierFlags, Key)> in
        key.flatMap { key -> ParsedToml<(NSEvent.ModifierFlags, Key)> in
            .success((modifiers, key))
        }
    }
}
