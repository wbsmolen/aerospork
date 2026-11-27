#!/usr/bin/env python3
"""Converts a release's Markdown notes to the HTML that Sparkle's update dialog embeds.

Usage: release-notes-html.py NOTES.md > notes.html, or --self-check.

HTML, not Markdown: `generate_appcast` picks up a file named after the archive, but a `.md` beside it
is silently ignored. Only `.html` (without DOCTYPE or body tags) is embedded as CDATA. Tested both: the
Markdown run produced an item with no <description> at all and said nothing about it.

Deliberately not a Markdown library: these notes use headings, bullets, links, inline code and fenced
blocks, and pulling in a dependency to render five constructs for a dialog nobody reads twice is not
worth it.
"""
import html
import re
import sys


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def convert(markdown: str) -> str:
    out: list[str] = []
    para: list[str] = []
    in_list, in_code, item = False, False, ""

    def flush():
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para.clear()

    for line in markdown.split("\n"):
        if line.startswith("```"):
            flush()
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append("</pre>" if in_code else "<pre>")
            in_code = not in_code
            continue
        if in_code:
            out.append(html.escape(line))
            continue
        stripped = line.strip()
        if stripped.startswith("- "):
            flush()
            if not in_list:
                out.append("<ul>")
                in_list = True
            item = stripped[2:]
            out.append(f"<li>{inline(item)}</li>")
            continue
        if in_list and stripped and line[0] in " \t":
            # The wrapped second line of a bullet belongs to that bullet, not to a new paragraph.
            item += " " + stripped
            out[-1] = f"<li>{inline(item)}</li>"
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
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
    if in_list:
        out.append("</ul>")
    if in_code:
        out.append("</pre>")
    return "\n".join(out)


def self_check():
    wrapped = convert("- First line of a bullet\n  and its `wrapped` second line.\n- Second bullet\n\nAfter.")
    assert wrapped == (
        "<ul>\n<li>First line of a bullet and its <code>wrapped</code> second line.</li>\n"
        "<li>Second bullet</li>\n</ul>\n<p>After.</p>"
    ), wrapped
    # An unindented line still ends the list.
    assert convert("- Item\nParagraph") == "<ul>\n<li>Item</li>\n</ul>\n<p>Paragraph</p>"
    print("release-notes-html.py: self-check passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        self_check()
    else:
        print(convert(open(sys.argv[1]).read()))
