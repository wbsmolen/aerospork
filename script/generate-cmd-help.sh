#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

# Prints Sources/Common/cmdHelpGenerated.swift from the synopsis of each docs/aerospork-*.adoc page.
# generate.sh writes it, only when it changed. It is one awk pass, not a sed pipeline per page, so it
# is cheap enough for every ./generate.sh, including the one in build-debug.sh.

cat << EOF
// FILE IS GENERATED FROM docs/aerospork-*.adoc files
// TO REGENERATE THE FILE RUN generate.sh --all

EOF

# For each page: the lines between `tag::synopsis` and `end::synopsis`, blank lines dropped. The
# first `aerospork` becomes `USAGE:`, the others `OR:`, then three leading spaces go, and every line
# after the `let` is indented by four.
awk '
function emit(file,   manpage, name, k, i, line, body) {
    manpage = file; sub(/.*\//, "", manpage); sub(/\.adoc$/, "", manpage)
    name = manpage; sub(/^aerospork-/, "", name); gsub(/-/, "_", name)
    k = 0
    for (i = 2; i < n; i++) if (c[i] != "") body[++k] = c[i]
    if (k == 0) return
    print "let " name "_help_generated = \"\"\""
    for (i = 1; i <= k; i++) {
        line = body[i]
        if (line ~ /^aerospork/) line = (i == 1 ? "   USAGE:" : "      OR:") substr(line, 10)
        if (substr(line, 1, 3) == "   ") line = substr(line, 4)
        print (line == "" ? "" : "    " line)
    }
    print ""
    print "    See: man " manpage
    print "    \"\"\""
}
FNR == 1 { if (NR > 1) emit(file); file = FILENAME; n = 0; inside = 0 }
inside { c[++n] = $0; if ($0 ~ /end::synopsis/) inside = 0; next }
/tag::synopsis/ { inside = 1; c[++n] = $0 }
END { if (NR > 0) emit(file) }
' docs/aerospork-*.adoc
