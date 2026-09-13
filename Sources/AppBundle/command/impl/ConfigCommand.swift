import AppKit
import Common

struct ConfigCommand: Command {
    let args: ConfigCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        switch args.mode {
            case .getKey(let key):
                return getKey(io, args: args, key: key)
            case .majorKeys:
                let out = """
                    .
                    mode
                    \(config.modes.keys.map { "mode.\($0).binding" }.joined(separator: "\n"))
                    """
                return io.out(out)
            case .allKeys:
                let configMap = buildConfigMap()
                var allKeys: [String] = []
                configMap.dumpAllKeysRecursive(path: ".", result: &allKeys)
                return io.out(allKeys.joined(separator: "\n"))
            case .configPath:
                return io.out(configUrl.absoluteURL.path)
        }
    }
}

extension String {
    fileprivate func toKeyPath() -> Result<[String], String> {
        if self == "." { return .success([]) }
        if isEmpty { return .failure("Invalid empty key") }
        if self.contains("..") { return .failure("Invalid key '\(self)'") }
        if self.hasSuffix(".") { return .failure("Invalid key '\(self)'") }
        return .success(self.split(separator: ".", omittingEmptySubsequences: false).map(String.init))
    }
}

@MainActor private func getKey(_ io: CmdIo, args: ConfigCmdArgs, key: String) -> Bool {
    let keyPath: [String]
    switch key.toKeyPath() {
        case .success(let _keyPath): keyPath = _keyPath
        case .failure(let error):
            return io.err(error)
    }
    var configMap: ConfigMapValue
    switch buildConfigMap().find(keyPath: keyPath) {
        case .success(let value):
            configMap = value
        case .failure(let error):
            return io.err(error)
    }
    if args.keys {
        switch configMap {
            case .scalar(let scalar):
                return io.err("--keys flag cannot be applied to scalar object '\(scalar)'")
            case .map(let map):
                configMap = .array(map.keys.map { .scalar(.string($0)) })
            case .array(let array):
                configMap = .array((0 ..< array.count).map { .scalar(.int($0)) })
        }
    }
    if args.json {
        if let json = JSONEncoder.aeroSporkDefault.encodeToString(configMap) {
            return io.out(json)
        } else {
            return io.err("Can't convert json Data to String")
        }
    } else {
        switch configMap {
            case .scalar(let scalar):
                return io.out(scalar.describe)
            case .map:
                return io.err("Complicated objects can be printed only with --json flag. " +
                    "Alternatively, you can try to inspect keys of the object with --keys flag")
            case .array(let array):
                let plainArray: Result<[String], String> = array.mapAllOrFailure {
                    switch $0 {
                        case .scalar(let scalar): .success(scalar.describe)
                        default: .failure("Printing array of non-string objects is supported only with --json flag." +
                                "Alternatively, you can try to inspect keys of the object with --keys flag")
                    }
                }
                return switch plainArray {
                    case .success(let array): io.out(array.sorted().joined(separator: "\n"))
                    case .failure(let error): io.err(error)
                }
        }
    }
}

extension ConfigMapValue {
    func find(keyPath: [String]) -> Result<ConfigMapValue, String> {
        if let key = keyPath.first {
            switch self {
                case .scalar(let scalar):
                    return .failure("Can't dereference scalar value '\(scalar.describe)'")
                case .map(let map):
                    if let child = map[key] {
                        return child.find(keyPath: Array(keyPath[1...]))
                    } else {
                        return .failure("No value at key token '\(key)'")
                    }
                case .array(let array):
                    if let key = Int(key) {
                        if let child = array.getOrNil(atIndex: key) {
                            return child.find(keyPath: Array(keyPath[1...]))
                        } else {
                            return .failure("Index out of bounds. Index: \(key), Size: \(array.count)")
                        }
                    } else {
                        return .failure("Can't convert key token '\(key)' to Int")
                    }
            }
        } else {
            return .success(self)
        }
    }

    func dumpAllKeysRecursive(path: String, result: inout [String]) {
        result.append(path)
        switch self {
            case .scalar: break
            case .map(let map):
                for (key, value) in map {
                    let path = path == "." ? key : path + "." + key
                    value.dumpAllKeysRecursive(path: path, result: &result)
                }
            case .array(let array):
                for (index, value) in array.enumerated() {
                    let path = path == "." ? String(index) : path + "." + String(index)
                    value.dumpAllKeysRecursive(path: path, result: &result)
                }
        }
    }
}

extension [Command] {
    var prettyDescription: String {
        map { $0.args.description }.joined(separator: "; ")
    }
}

/// The runtime view of the *effective* config, as `config --get`/`--all-keys` sees it.
///
/// This used to expose only `mode`, so 18 of the 20 live top-level keys were uninspectable and
/// `config --get gaps` answered "No value at key token 'gaps'" — which reads like "that key does
/// not exist" rather than "introspection is not implemented". That made it impossible to confirm a
/// hot-reload had taken effect or to debug why an assignment was not applying.
///
/// Everything here comes from the parsed `config`, not the file, so it reflects what the WM is
/// actually using right now.
@MainActor func buildConfigMap() -> ConfigMapValue {
    func str(_ s: String) -> ConfigMapValue { .scalar(.string(s)) }
    func int(_ i: Int) -> ConfigMapValue { .scalar(.int(i)) }
    func flag(_ b: Bool) -> ConfigMapValue { str(b ? "true" : "false") }
    func commands(_ c: [any Command]) -> ConfigMapValue { .array(c.map { str($0.args.description) }) }

    func gap(_ v: DynamicConfigValue<Int>) -> ConfigMapValue {
        switch v {
            case .constant(let i): return int(i)
            case .perMonitor(let per, let def):
                return .map([
                    "default": int(def),
                    "per-monitor": .array(per.map { str("\($0.description): \($0.value)") }),
                ])
        }
    }

    let mode = config.modes.mapValues { (mode: Mode) -> ConfigMapValue in
        var keyNotationToScript: [String: ConfigMapValue] = [:]
        for binding in mode.bindings.values {
            keyNotationToScript[binding.descriptionWithKeyNotation] =
                .scalar(.string(binding.commands.prettyDescription))
        }
        return .map(["binding": .map(keyNotationToScript)])
    }

    // `key-mapping` retains real effective state (the preset actually in force plus any custom
    // notation), and was missing from this map -- so `config --get key-mapping.preset` could not
    // answer a question the user can definitely have.
    let keyMapping: ConfigMapValue = .map([
        "preset": .scalar(.string(config.keyMapping.presetName)),
        "key-notation-to-key-code": .map(
            config.keyMapping.customKeyNotations.mapValues { .scalar(.string(String(describing: $0))) },
        ),
    ])

    return .map([
        "mode": .map(mode),
        "key-mapping": keyMapping,

        "start-at-login": flag(config.startAtLogin),
        "show-menu-bar-icon": flag(config.showMenuBarIcon),
        "show-dock-icon": flag(config.showDockIcon),
        "automatically-unhide-macos-hidden-apps": flag(config.automaticallyUnhideMacosHiddenApps),
        "auto-move-workspaces-on-monitor-connect": flag(config.autoMoveWorkspacesOnMonitorConnect),
        "enable-normalization-flatten-containers": flag(config.enableNormalizationFlattenContainers),
        "enable-normalization-opposite-orientation-for-nested-containers":
            flag(config.enableNormalizationOppositeOrientationForNestedContainers),
        "default-root-container-layout": str(config.defaultRootContainerLayout.rawValue),
        "default-root-container-orientation": str(config.defaultRootContainerOrientation.rawValue),
        "accordion-padding": int(config.accordionPadding),
        "persistent-workspaces": .array(
            config.persistentWorkspaces.sorted { $0.toLogicalSegments() < $1.toLogicalSegments() }.map { str($0) },
        ),

        "after-startup-command": commands(config.afterStartupCommand),
        "on-focus-changed": commands(config.onFocusChanged),
        "on-focused-workspace-changed": commands(config.onFocusedWorkspaceChanged),
        "on-focused-monitor-changed": commands(config.onFocusedMonitorChanged),

        "gaps": .map([
            "inner": .map(["horizontal": gap(config.gaps.inner.horizontal), "vertical": gap(config.gaps.inner.vertical)]),
            "outer": .map([
                "left": gap(config.gaps.outer.left), "right": gap(config.gaps.outer.right),
                "top": gap(config.gaps.outer.top), "bottom": gap(config.gaps.outer.bottom),
            ]),
        ]),

        "workspace-to-monitor-force-assignment": .map(
            config.workspaceToMonitorForceAssignment.mapValues { descriptions in
                ConfigMapValue.array(descriptions.map { str($0.humanDescription) })
            },
        ),

        "on-window-detected": .array(config.onWindowDetected.map { str(String(describing: $0.matcher)) }),

        "exec": .map([
            "env-vars": .map(config.execConfig.envVariables.mapValues { str($0) }),
        ]),
    ])
}

extension MonitorDescription {
    /// `config --get` is a debugging tool, so the default Swift `describe` (which dumps a struct
    /// with every nil field) is actively unhelpful. Render only what was actually specified.
    var humanDescription: String {
        switch self {
            case .main: return "main"
            case .secondary: return "secondary"
            case .sequenceNumber(let n): return "monitor #\(n)"
            case .pattern(let raw, _): return "pattern '\(raw)'"
            case .fingerprint(let d):
                var parts: [String] = []
                if let v = d.vendorID { parts.append(String(format: "vendor 0x%X", v)) }
                if let m = d.modelID { parts.append(String(format: "model 0x%X", m)) }
                if let s = d.serialNumber { parts.append("serial \(s)") }
                if let n = d.displayNamePattern { parts.append("name '\(n)'") }
                if let w = d.widthPixels, let h = d.heightPixels { parts.append("\(w)x\(h)") }
                if let u = d.displayUUID { parts.append("uuid \(u)") }
                return "fingerprint(" + (parts.isEmpty ? "empty" : parts.joined(separator: ", ")) + ")"
        }
    }
}

enum ConfigScalarValue: Encodable {
    case string(String)
    case int(Int)

    var describe: String {
        return switch self {
            case .string(let string): string
            case .int(let int): String(int)
        }
    }

    func encode(to encoder: Encoder) throws {
        let value: Encodable = switch self {
            case .string(let string): string
            case .int(let int): int
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum ConfigMapValue: Encodable {
    case scalar(ConfigScalarValue)
    case map([String: ConfigMapValue])
    case array([ConfigMapValue])

    func encode(to encoder: Encoder) throws {
        let value: Encodable = switch self {
            case .scalar(let scalar): scalar
            case .map(let map): map
            case .array(let array): array
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
