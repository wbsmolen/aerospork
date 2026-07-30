#!/bin/bash
set -e
cd "$(dirname "$0")/.."
source ./script/setup.sh

# Cuts a release: build, tag, publish both archives, sign the appcast, update the tap.
#
# It used to open a browser tab and ask you to drag one zip in. That lost two steps every time,
# because a release is not one artifact:
#
#   * `aerospork-v$V.zip`  -- the distribution package Homebrew and manual installers take.
#   * `AeroSpork-$V.zip`   -- the Sparkle update archive, the .app at the archive root. Sparkle
#                             REFUSES the distribution zip ("only .app bundles are supported"), so
#                             without this one, in-app updates are dead.
#
# and the appcast has to name the second one or nothing is offered at all. v1.1.0 shipped without
# `AeroSpork-1.1.0.zip` -- and with the generated cask file uploaded as a release asset by mistake,
# which is what happens when the step is "drag the right file in".

build_version=""
notes_file=""
cask_git_repo_path=""
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --notes-file) notes_file="$2"; shift 2;;
        --cask-git-repo-path) cask_git_repo_path="$2"; shift 2;;
        *) echo "Unknown option $1"; exit 1;;
    esac
done

if test -z "$build_version"; then
    echo "--build-version flag is mandatory" > /dev/stderr
    exit 1
fi
if test -n "$notes_file" && ! test -f "$notes_file"; then
    echo "--notes-file points at a file that does not exist: $notes_file" > /dev/stderr
    exit 1
fi

repo="wbsmolen/aerospork"
dist_zip=".release/aerospork-v$build_version.zip"
sparkle_zip=".release/AeroSpork-$build_version.zip"

# `setup.sh` replaces PATH with `.deps/bin:/bin:/usr/bin` so a build cannot pick up whatever happens
# to be installed. These three are linked in there alongside the build tools; the check stays because
# failing here costs nothing and failing after the twenty-minute universal build costs the build.
for tool in gh swa az; do
    command -v "$tool" > /dev/null || {
        echo "Required tool not found: $tool" > /dev/stderr
        echo "Install it, then re-run: script/setup.sh links it into .deps/bin." > /dev/stderr
        exit 1
    }
done

# The build embeds `git rev-parse HEAD` and then asserts the binary contains it, so a commit landing
# mid-build fails the release ~20 minutes in. Refuse up front instead.
if test -n "$(git status --porcelain)"; then
    echo "Working tree is dirty. A release must be built from a committed tree." > /dev/stderr
    git status --short > /dev/stderr
    exit 1
fi

./run-tests.sh
./build-release.sh --build-version "$build_version"

for artifact in "$dist_zip" "$sparkle_zip"; do
    test -f "$artifact" || { echo "Missing build artifact: $artifact" > /dev/stderr; exit 1; }
done

git tag -a "v$build_version" -m "v$build_version"
git push origin "v$build_version"

if test -n "$notes_file"; then
    gh release create "v$build_version" --repo "$repo" --title "AeroSpork $build_version" \
        --notes-file "$notes_file" "$dist_zip" "$sparkle_zip"
else
    gh release create "v$build_version" --repo "$repo" --title "AeroSpork $build_version" \
        --generate-notes "$dist_zip" "$sparkle_zip"
fi

##################
### THE APPCAST ##
##################

# Generated from the Sparkle archive, never the distribution zip. `generate_appcast` re-uses an
# appcast already present in the directory, so seeding it with the live one keeps the channel
# metadata and the older items.
appcast_workdir="$(mktemp -d)"
trap 'rm -rf "$appcast_workdir"' EXIT
cp "$sparkle_zip" "$appcast_workdir/"
cp updates-site/appcast.xml "$appcast_workdir/appcast.xml"

# Release notes, so the update dialog is not blank -- without them Sparkle shows an empty pane while
# perfectly good notes sit on the GitHub release doing nothing.
#
# HTML, not Markdown. `generate_appcast` picks up a file named after the archive, but a `.md` beside
# it is silently ignored: only `.html` (without DOCTYPE or body tags) is embedded as CDATA. Tested
# both -- the Markdown run produced an item with no <description> at all and said nothing about it.
if test -n "$notes_file"; then
    python3 - "$notes_file" > "$appcast_workdir/AeroSpork-$build_version.html" <<'PYEOF'
import html, re, sys

# Deliberately not a Markdown library: these notes use headings, bullets, links, inline code and
# fenced blocks, and pulling in a dependency to render five constructs for a dialog nobody reads
# twice is not worth it.
lines = open(sys.argv[1]).read().split("\n")
out, in_list, in_code = [], False, False
para: list[str] = []

def flush():
    if para:
        out.append(f"<p>{inline(' '.join(para))}</p>")
        para.clear()

def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text

for line in lines:
    if line.startswith("```"):
        flush()
        if in_list: out.append("</ul>"); in_list = False
        out.append("</pre>" if in_code else "<pre>")
        in_code = not in_code
        continue
    if in_code:
        out.append(html.escape(line))
        continue
    stripped = line.strip()
    if stripped.startswith("- "):
        flush()
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(stripped[2:])}</li>")
        continue
    if in_list: out.append("</ul>"); in_list = False
    if stripped.startswith("#"):
        flush()
        level = min(len(stripped) - len(stripped.lstrip("#")), 6)
        out.append(f"<h{level}>{inline(stripped.lstrip('#').strip())}</h{level}>")
    elif stripped:
        # Accumulated, not emitted per line: these notes are hard-wrapped, and one <p> per source
        # line renders as a column of one-sentence fragments.
        para.append(stripped)
    else:
        flush()
flush()
if in_list: out.append("</ul>")
if in_code: out.append("</pre>")
print("\n".join(out))
PYEOF
fi

sparkle_bin="$(find .build/artifacts -type d -name bin -path '*sparkle*' | head -1)"
test -n "$sparkle_bin" || { echo "Sparkle tools not found; run a build first" > /dev/stderr; exit 1; }

"$sparkle_bin/generate_appcast" \
    --embed-release-notes \
    --download-url-prefix "https://github.com/$repo/releases/download/v$build_version/" \
    --link "https://github.com/$repo" \
    "$appcast_workdir"
cp "$appcast_workdir/appcast.xml" updates-site/appcast.xml

# The signature has to verify against the asset GitHub actually serves, not the local copy. A wrong
# enclosure URL, a re-zipped artifact or a mismatched key all show up here and nowhere else.
signature="$(grep -m1 -o 'edSignature="[^"]*"' updates-site/appcast.xml | sed 's/edSignature="//; s/"$//')"
published="$appcast_workdir/published.zip"
curl -fsSL -o "$published" "https://github.com/$repo/releases/download/v$build_version/AeroSpork-$build_version.zip"
if ! "$sparkle_bin/sign_update" --verify "$published" "$signature" > /dev/null 2>&1; then
    echo "!!! The appcast signature does not verify against the published asset !!!" > /dev/stderr
    exit 1
fi

swa deploy updates-site \
    --deployment-token "$(az staticwebapp secrets list --name aerospork-updates \
        --resource-group aerospork-updates --query 'properties.apiKey' -o tsv)" \
    --env production

################
### THE CASK ###
################

./script/build-brew-cask.sh \
    --cask-name aerospork \
    --zip-uri "https://github.com/$repo/releases/download/v$build_version/aerospork-v$build_version.zip" \
    --build-version "$build_version"

if test -n "$cask_git_repo_path"; then
    if ! test -d "$cask_git_repo_path"; then
        echo "--cask-git-repo-path points at a directory that does not exist" > /dev/stderr
        exit 1
    fi
    cp .release/aerospork.rb "$cask_git_repo_path/Casks/aerospork.rb"
    echo "Cask copied into $cask_git_repo_path -- commit and push it there."
else
    # No local clone needed for a one-file change.
    gh api -X PUT "repos/wbsmolen/homebrew-tap/contents/Casks/aerospork.rb" \
        -f message="aerospork $build_version" \
        -f content="$(base64 -i .release/aerospork.rb | tr -d '\n')" \
        -f sha="$(gh api repos/wbsmolen/homebrew-tap/contents/Casks/aerospork.rb -q .sha)" > /dev/null
    echo "Tap updated to $build_version."
fi

echo
echo "Published v$build_version. Remaining by hand:"
echo "  * commit updates-site/appcast.xml"
