import AppKit
import Carbon
import Common
import Foundation
import TOMLKit

// Global hotkeys are registered with Carbon's `RegisterEventHotKey`. Only the currently active
// mode's bindings are registered at any time; switching modes unregisters the old set and
// registers the new one (the net effect of the old enable/disable toggling).

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

@MainActor func resetHotKeys() {
    for (_, entry) in registeredHotKeys {
        UnregisterEventHotKey(entry.ref)
    }
    registeredHotKeys = [:]
}

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
    Task { @MainActor in
        guard let entry = registeredHotKeys[id], let activeMode else { return }
        let startTime = Date()
        debugLog("HOTKEY: \(entry.notation) pressed")

        if let commands = config.modes[activeMode]?.bindings[entry.bindingId]?.commands {
            let commandCount = commands.count
            debugLog("HOTKEY: Will execute \(commandCount) command(s)")
        }

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
    resetHotKeys()
    installHotKeyEventHandlerIfNeeded()
    let targetBindings = targetMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    for binding in targetBindings.values {
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
            debugLog("HOTKEY: Failed to register \(binding.descriptionWithKeyNotation) (status \(status))")
        }
    }
    activeMode = targetMode
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
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.descriptionWithKeyNotation = descriptionWithKeyNotation
    }

    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.modifiers == rhs.modifiers &&
            lhs.keyCode == rhs.keyCode &&
            lhs.descriptionWithKeyCode == rhs.descriptionWithKeyCode &&
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

func parseBinding(_ raw: String, _ backtrace: TomlBacktrace, _ mapping: [String: Key]) -> ParsedToml<(NSEvent.ModifierFlags, Key)> {
    let rawKeys = raw.split(separator: "-")
    let modifiers: ParsedToml<NSEvent.ModifierFlags> = rawKeys.dropLast()
        .mapAllOrFailure {
            modifiersMap[String($0)].orFailure(.semantic(backtrace, "Can't parse modifiers in '\(raw)' binding"))
        }
        .map { NSEvent.ModifierFlags($0) }
    let key: ParsedToml<Key> = rawKeys.last.flatMap { mapping[String($0)] }
        .orFailure(.semantic(backtrace, "Can't parse the key in '\(raw)' binding"))
    return modifiers.flatMap { modifiers -> ParsedToml<(NSEvent.ModifierFlags, Key)> in
        key.flatMap { key -> ParsedToml<(NSEvent.ModifierFlags, Key)> in
            .success((modifiers, key))
        }
    }
}
