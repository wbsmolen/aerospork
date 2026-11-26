#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

# Completions are VENDORED into ./shell-completion (tracked in git), not generated during the
# release build. Generating them needs complgen (a Rust build), fish, and bash >= 5 -- none of which
# ship with macOS, and setup.sh resets PATH so a Homebrew bash 5 isn't visible either. That made
# build-release.sh unrunnable on a stock machine to produce three files that change only when
# grammar/commands-bnf-grammar.txt changes.
#
# So: run this script by hand after editing the grammar, and commit the result. build-release.sh
# just copies ./shell-completion.
#
# Drift is caught by hash, not by running complgen in the tests: this script records the grammar's
# SHA-256 in shell-completion/.grammar-sha256, and ShellCompletionGrammarTest fails when the grammar
# no longer matches it. Only a regeneration writes the hash. A hand edit of the vendored files is
# not caught.

./script/install-dep.sh --complgen

rm -rf shell-completion && mkdir -p \
    shell-completion/zsh \
    shell-completion/fish \
    shell-completion/bash

./.deps/cargo-root/bin/complgen aot ./grammar/commands-bnf-grammar.txt \
    --zsh-script shell-completion/zsh/_aerospork \
    --fish-script shell-completion/fish/aerospork.fish \
    --bash-script shell-completion/bash/aerospork
shasum -a 256 grammar/commands-bnf-grammar.txt > shell-completion/.grammar-sha256

# Syntax-check with whatever shells are actually present. A missing shell is a skip, not a failure:
# the generated file is still correct, it just can't be checked here. Previously a missing fish or
# an old bash aborted the whole release build.
checked=0

zsh -c 'autoload -Uz compinit; compinit -u; source ./shell-completion/zsh/_aerospork' && checked=$((checked + 1))

# not-outdated-bash is a setup.sh shim over whatever `bash` was on PATH before it got reset.
if /usr/bin/which not-outdated-bash > /dev/null && not-outdated-bash --version | grep -q 'version [5-9]'; then
    not-outdated-bash -c 'source ./shell-completion/bash/aerospork' && checked=$((checked + 1))
else
    echo "skip: bash >= 5 not found, cannot syntax-check shell-completion/bash/aerospork" > /dev/stderr
fi

if /usr/bin/which fish > /dev/null; then
    fish -c 'source ./shell-completion/fish/aerospork.fish' && checked=$((checked + 1))
else
    echo "skip: fish not found, cannot syntax-check shell-completion/fish/aerospork.fish" > /dev/stderr
fi

echo "shell-completion/ regenerated ($checked/3 syntax-checked). Commit it."
