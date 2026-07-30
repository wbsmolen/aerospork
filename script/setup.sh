#!/bin/bash
set -e # Exit if one of commands exit with non-zero exit code
set -u # Treat unset variables and parameters other than the special parameters ‘@’ or ‘*’ as an error
set -o pipefail # Any command failed in the pipe fails the whole pipe
# set -x # Print shell commands as they are executed (or you can try -v which is less verbose)


add_optional_dep_to_bin() {
    if /usr/bin/which "$1" &> /dev/null; then
        /bin/cat > ".deps/bin/${2:-$1}" <<EOF
#!/bin/bash
exec '$(/usr/bin/which "$1")' "\$@"
EOF
    fi
}

if /bin/test -z "${NUKE_PATH:-}"; then
    /bin/rm -rf .deps/bin
    /bin/mkdir -p .deps/bin

    add_optional_dep_to_bin bash not-outdated-bash # build-shell-completion.sh
    add_optional_dep_to_bin fish # build-shell-completion.sh
    add_optional_dep_to_bin rustc # build-shell-completion.sh
    add_optional_dep_to_bin cargo # build-shell-completion.sh
    add_optional_dep_to_bin brew # install-from-sources.sh
    add_optional_dep_to_bin bundle # build-docs.sh
    add_optional_dep_to_bin bundler # build-docs.sh
    add_optional_dep_to_bin xcbeautify # build-release.sh
    add_optional_dep_to_bin git
    add_optional_dep_to_bin swift
    add_optional_dep_to_bin swiftly
    add_optional_dep_to_bin gh # publish-release.sh
    add_optional_dep_to_bin swa # publish-release.sh
    add_optional_dep_to_bin az # publish-release.sh
    add_optional_dep_to_bin node # swa, in publish-release.sh

    export PATH="${PWD}/.deps/bin:/bin:/usr/bin"
    chmod +x .deps/bin/*
    export NUKE_PATH=1
fi

swift() {
    # Escape hatch: the swiftly-pinned toolchain can't compile against a beta macOS SDK -- the
    # frontend spins at 100% CPU forever on the TOMLKit manifest. Set AEROSPORK_SWIFT=xcrun (with
    # DEVELOPER_DIR pointing at the matching Xcode) to build with the Xcode toolchain instead.
    if /bin/test "${AEROSPORK_SWIFT:-}" = "xcrun"; then
        /usr/bin/xcrun swift "$@"
    elif /usr/bin/which swiftly &> /dev/null; then
        swiftly run swift "$@"
    else
        echo "warning: swiftly is not installed. Fallback to plain swift. Swift compilation might not be reproducible" > /dev/stderr
        /usr/bin/env swift "$@"
    fi
}

xcodebuild-pretty() {
    log_file="$1"
    shift
    # Mute stderr
    # 2024-02-12 23:48:11.713 xcodebuild[60777:7403664] [MT] DVTAssertions: Warning in /System/Volumes/Data/SWE/Apps/DT/BuildRoots/BuildRoot11/ActiveBuildRoot/Library/Caches/com.apple.xbs/Sources/IDEFrameworks/IDEFrameworks-22269/IDEFoundation/Provisioning/Capabilities Infrastructure/IDECapabilityQuerySelection.swift:103
    # Details:  createItemModels creation requirements should not create capability item model for a capability item model that already exists.
    # Function: createItemModels(for:itemModelSource:)
    # Thread:   <_NSMainThread: 0x6000037202c0>{number = 1, name = main}
    # Please file a bug at https://feedbackassistant.apple.com with this warning message and any useful information you can provide.
    if /usr/bin/which xcbeautify &> /dev/null; then
        /usr/bin/xcrun xcodebuild "$@" 2>&1 | tee "$log_file" | xcbeautify --quiet # Only print tasks that have warnings or errors
        echo "The full unmodified xcodebuild log is saved to $log_file"
    else
        /usr/bin/xcrun xcodebuild "$@" 2>&1 | tee "$log_file"
    fi
}
