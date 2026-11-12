import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from docs_from_webdata import PAGES, convert, main  # noqa: E402

MDX = """---
title: Reference
description: Reference of all Wisp configuration options.
editOnGithubLink: https://github.com/callistobound/wisp/edit/downstream/src/config/Config.zig
---

## `font-size`
Font size in points.

<Note>
Only whole points on macOS.
</Note>

<Warning>
Large sizes are slow.
</Warning>
"""


class ConvertTest(unittest.TestCase):
    def test_frontmatter(self):
        out = convert(MDX, "Configuration")
        self.assertTrue(out.startswith("---\ntitle: Configuration\n"))
        self.assertIn("description: Reference of all Wisp configuration options.\n", out)
        self.assertNotIn("editOnGithubLink", out)

    def test_callouts_become_asides(self):
        out = convert(MDX, "Configuration")
        self.assertIn(":::note\nOnly whole points on macOS.\n:::\n", out)
        self.assertIn(":::caution\nLarge sizes are slow.\n:::\n", out)
        self.assertNotIn("<Note>", out)
        self.assertNotIn("</Warning>", out)

    def test_body_kept(self):
        self.assertIn("## `font-size`\nFont size in points.\n", convert(MDX, "Configuration"))


class MainTest(unittest.TestCase):
    def test_writes_every_page(self):
        with tempfile.TemporaryDirectory() as src, tempfile.TemporaryDirectory() as out:
            for name in PAGES:
                with open(os.path.join(src, f"{name}.mdx"), "w") as f:
                    f.write(MDX)
            main([src, out])
            self.assertEqual(sorted(os.listdir(out)), sorted(f"{name}.md" for name in PAGES))
            with open(os.path.join(out, "actions.md")) as f:
                self.assertIn("title: Keybinding Actions\n", f.read())


if __name__ == "__main__":
    unittest.main()
