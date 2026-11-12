"""
Turns `zig build -Demit-webdata` output into Starlight pages.

Usage: docs_from_webdata.py WEBDATA_DIR OUT_DIR
"""

import os
import sys

# Generated page name -> site title.
PAGES = {
    "config": "Configuration",
    "actions": "Keybinding Actions",
    "commands": "CLI Commands",
}

# The generators' callout tags, each on its own line.
CALLOUTS = {
    "<Note>": ":::note",
    "<Warning>": ":::caution",
    "</Note>": ":::",
    "</Warning>": ":::",
}


def convert(mdx, title):
    _, frontmatter, body = mdx.split("---\n", 2)
    fields = [f"title: {title}"]
    for line in frontmatter.splitlines():
        if line.startswith("description:"):
            fields.append(line)
    lines = [CALLOUTS.get(line, line) for line in body.split("\n")]
    return "---\n" + "\n".join(fields) + "\n---\n" + "\n".join(lines)


def main(argv):
    src, out = argv
    os.makedirs(out, exist_ok=True)
    for name, title in PAGES.items():
        with open(os.path.join(src, f"{name}.mdx")) as f:
            page = convert(f.read(), title)
        with open(os.path.join(out, f"{name}.md"), "w") as f:
            f.write(page)


if __name__ == "__main__":
    main(sys.argv[1:])
