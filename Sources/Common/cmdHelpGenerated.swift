// FILE IS GENERATED FROM docs/aerospork-*.adoc files
// TO REGENERATE THE FILE RUN generate.sh --all

let balance_sizes_help_generated = """
    USAGE: balance-sizes [-h|--help] [--workspace <workspace>]

    See: man aerospork-balance-sizes
    """
let close_all_windows_but_current_help_generated = """
    USAGE: close-all-windows-but-current [-h|--help] [--quit-if-last-window]

    See: man aerospork-close-all-windows-but-current
    """
let close_help_generated = """
    USAGE: close [-h|--help] [--quit-if-last-window] [--window-id <window-id>]

    See: man aerospork-close
    """
let config_help_generated = """
    USAGE: config [-h|--help] --get <name> [--json] [--keys]
       OR: config [-h|--help] --major-keys
       OR: config [-h|--help] --all-keys
       OR: config [-h|--help] --config-path

    See: man aerospork-config
    """
let debug_windows_help_generated = """
    USAGE: debug-windows [-h|--help] [--window-id <window-id>]

    See: man aerospork-debug-windows
    """
let enable_help_generated = """
    USAGE: enable [-h|--help] toggle
       OR: enable [-h|--help] on [--fail-if-noop]
       OR: enable [-h|--help] off [--fail-if-noop]

    See: man aerospork-enable
    """
let exec_and_forget_help_generated = """
    exec-and-forget <bash-script>   # config only, not available in CLI

    See: man aerospork-exec-and-forget
    """
let flatten_workspace_tree_help_generated = """
    USAGE: flatten-workspace-tree [-h|--help] [--workspace <workspace>]

    See: man aerospork-flatten-workspace-tree
    """
let focus_back_and_forth_help_generated = """
    USAGE: focus-back-and-forth [-h|--help]

    See: man aerospork-focus-back-and-forth
    """
let focus_monitor_help_generated = """
    USAGE: focus-monitor [-h|--help] [--wrap-around] (left|down|up|right)
       OR: focus-monitor [-h|--help] [--wrap-around] (next|prev)
       OR: focus-monitor [-h|--help] <monitor-pattern>...

    See: man aerospork-focus-monitor
    """
let focus_help_generated = """
    USAGE: focus [-h|--help] [--ignore-floating]
                 [--boundaries <boundary>] [--boundaries-action <boundary-action>]
                 (left|down|up|right)
       OR: focus [-h|--help] --window-id <window-id>
       OR: focus [-h|--help] --dfs-index <dfs-index>

    See: man aerospork-focus
    """
let fullscreen_help_generated = """
    USAGE: fullscreen [-h|--help]     [--window-id <window-id>] [--no-outer-gaps]
       OR: fullscreen [-h|--help] on  [--window-id <window-id>] [--no-outer-gaps] [--fail-if-noop]
       OR: fullscreen [-h|--help] off [--window-id <window-id>] [--fail-if-noop]

    See: man aerospork-fullscreen
    """
let join_with_help_generated = """
    USAGE: join-with [-h|--help] [--window-id <window-id>] (left|down|up|right)

    See: man aerospork-join-with
    """
let layout_help_generated = """
    USAGE: layout [-h|--help] [--window-id <window-id>]
                  (h_tiles|v_tiles|h_accordion|v_accordion|tiles|accordion|horizontal|vertical|tiling|floating)...

    See: man aerospork-layout
    """
let list_apps_help_generated = """
    USAGE: list-apps [-h|--help] [--macos-native-hidden [no]] [--format <output-format>] [--count] [--json]

    See: man aerospork-list-apps
    """
let list_exec_env_vars_help_generated = """
    USAGE: list-exec-env-vars [-h|--help] [--show-secrets]

    See: man aerospork-list-exec-env-vars
    """
let list_modes_help_generated = """
    USAGE: list-modes [-h|--help] [--current]

    See: man aerospork-list-modes
    """
let list_monitors_help_generated = """
    USAGE: list-monitors [-h|--help] [--focused [no]] [--mouse [no]] [--format <output-format>] [--count] [--json]

    See: man aerospork-list-monitors
    """
let list_windows_help_generated = """
    USAGE: list-windows [-h|--help] (--workspace <workspace>...|--monitor <monitor>...)
                        [--monitor <monitor>...] [--workspace <workspace>...]
                        [--pid <pid>] [--app-bundle-id <app-bundle-id>] [--format <output-format>]
                        [--count] [--json]
       OR: list-windows [-h|--help] --all [--format <output-format>] [--count] [--json]
       OR: list-windows [-h|--help] --focused [--format <output-format>] [--count] [--json]

    See: man aerospork-list-windows
    """
let list_workspaces_help_generated = """
    USAGE: list-workspaces [-h|--help] --monitor <monitor>... [--visible [no]] [--empty [no]] [--format <output-format>] [--count] [--json]
       OR: list-workspaces [-h|--help] --all [--format <output-format>] [--count] [--json]
       OR: list-workspaces [-h|--help] --focused [--format <output-format>] [--count] [--json]

    See: man aerospork-list-workspaces
    """
let macos_native_fullscreen_help_generated = """
    USAGE: macos-native-fullscreen [-h|--help] [--window-id <window-id>]
       OR: macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] on
       OR: macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] off

    See: man aerospork-macos-native-fullscreen
    """
let macos_native_minimize_help_generated = """
    USAGE: macos-native-minimize [-h|--help] [--window-id <window-id>]

    See: man aerospork-macos-native-minimize
    """
let mode_help_generated = """
    USAGE: mode [-h|--help] <binding-mode>

    See: man aerospork-mode
    """
let move_mouse_help_generated = """
    USAGE: move-mouse [-h|--help] [--fail-if-noop] <mouse-position>

    See: man aerospork-move-mouse
    """
let move_node_to_monitor_help_generated = """
    USAGE: move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                                [--wrap-around] (left|down|up|right|next|prev)
       OR: move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                                [--fail-if-noop] <monitor-pattern>...

    See: man aerospork-move-node-to-monitor
    """
let move_node_to_workspace_help_generated = """
    USAGE: move-node-to-workspace [-h|--help] [--focus-follows-window] [--wrap-around]
                                  (next|prev)
       OR: move-node-to-workspace [-h|--help] [--focus-follows-window] [--fail-if-noop]
                                  [--window-id <window-id>] <workspace>

    See: man aerospork-move-node-to-workspace
    """
let move_workspace_to_monitor_help_generated = """
    USAGE: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (left|down|up|right)
       OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (next|prev)
       OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] <monitor-pattern>...

    See: man aerospork-move-workspace-to-monitor
    """
let move_help_generated = """
    USAGE: move [-h|--help] [--window-id <window-id>] [--boundaries <boundary>] [--boundaries-action <boundary-action>] (left|down|up|right)

    See: man aerospork-move
    """
let open_settings_help_generated = """
    USAGE: open-settings [-h|--help]

    See: man aerospork-open-settings
    """
let reload_config_help_generated = """
    USAGE: reload-config [-h|--help] [--no-gui] [--dry-run]

    See: man aerospork-reload-config
    """
let resize_help_generated = """
    USAGE: resize [-h|--help] [--window-id <window-id>] (smart|smart-opposite|width|height) [+|-]<number>

    See: man aerospork-resize
    """
let split_help_generated = """
    USAGE: split [-h|--help] [--window-id <window-id>] (horizontal|vertical|opposite)

    See: man aerospork-split
    """
let summon_workspace_help_generated = """
    USAGE: summon-workspace [-h|--help] [--fail-if-noop] <workspace>

    See: man aerospork-summon-workspace
    """
let trigger_binding_help_generated = """
    USAGE: trigger-binding [-h|--help] <binding> --mode <binding-mode>

    See: man aerospork-trigger-binding
    """
let volume_help_generated = """
    USAGE: volume [-h|--help] (up|down)
       OR: volume [-h|--help] (mute-toggle|mute-off|mute-on)
       OR: volume [-h|--help] set <number>

    See: man aerospork-volume
    """
let workspace_back_and_forth_help_generated = """
    USAGE: workspace-back-and-forth [-h|--help]

    See: man aerospork-workspace-back-and-forth
    """
let workspace_help_generated = """
    USAGE: workspace [-h|--help] [--auto-back-and-forth] [--fail-if-noop] <workspace>
       OR: workspace [-h|--help] [--wrap-around] (next|prev)

    See: man aerospork-workspace
    """
