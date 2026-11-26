#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

# Prints Sources/Common/cmdHelpGenerated.swift. generate.sh writes it, only when it changed.

cmd_prefix="aerospork"
____usage_prefix="   USAGE:"
_______or_prefix="      OR:"
____strip_prefix="   "

triple_quote='"""'

cat << EOF
// FILE IS GENERATED FROM docs/aerospork-*.adoc files
// TO REGENERATE THE FILE RUN generate.sh --all

EOF

for file in docs/aerospork-*.adoc; do
    manpage=$(basename "$file" .adoc)
    subcommand=$(sed 's/^aerospork-//; s/-/_/g' <<< "$manpage")
    sed -n -E '/tag::synopsis/, /end::synopsis/ p' "$file" | \
        sed '1d' | \
        sed '$d' | \
        sed '/^$/ d' | \
        sed "1   s/^$cmd_prefix/$____usage_prefix/" | \
        sed "2,$ s/^$cmd_prefix/$_______or_prefix/" | \
        sed     "s/^$____strip_prefix//" | \
        sed "1 s/^/let ${subcommand}_help_generated = $triple_quote\n/" | \
        sed "\$ s/$/\n\nSee: man $manpage\n${triple_quote}/" | \
        sed '2,$ s/^./    &/'
done
