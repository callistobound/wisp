import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from cask import render  # noqa: E402

SHA = "01037165a699b09d464f0e858cd9867cb45d4a491d0cea261dcd4319772263b0"


class CaskTest(unittest.TestCase):
    def test_stable(self):
        rb = render("stable", version="1.4.1-wisp.1", sha256=SHA)
        self.assertTrue(rb.startswith('cask "wisp" do\n'))
        self.assertIn('version "1.4.1-wisp.1"\n', rb)
        self.assertIn(f'sha256 "{SHA}"\n', rb)
        self.assertIn(
            'url "https://github.com/callistobound/wisp/releases/download/v#{version}/Wisp.dmg"\n', rb
        )
        self.assertIn('conflicts_with cask: "wisp@tip"\n', rb)

    def test_tip(self):
        rb = render("tip")
        self.assertTrue(rb.startswith('cask "wisp@tip" do\n'))
        self.assertIn("version :latest\n", rb)
        self.assertIn("sha256 :no_check\n", rb)
        self.assertIn('url "https://github.com/callistobound/wisp/releases/download/tip/Wisp.dmg"\n', rb)
        self.assertIn('conflicts_with cask: "wisp"\n', rb)

    def test_installs_app_command_and_completions(self):
        for rb in (render("tip"), render("stable", version="1.4.1-wisp.1", sha256=SHA)):
            self.assertIn('app "Wisp.app"\n', rb)
            self.assertIn('binary "#{appdir}/Wisp.app/Contents/MacOS/wisp"\n', rb)
            self.assertIn("bash-completion/completions/wisp.bash", rb)
            self.assertIn("zsh/site-functions/_wisp", rb)
            self.assertIn("fish/vendor_completions.d/wisp.fish", rb)
            self.assertIn('uninstall quit: "com.callistobound.wisp"\n', rb)
            self.assertIn('"~/Library/Preferences/com.callistobound.wisp.plist"', rb)
            # A ghostty config may be the user's own; only Wisp's is removed.
            self.assertNotIn("~/.config/ghostty", rb)

    def test_stable_needs_version_and_checksum(self):
        with self.assertRaises(ValueError):
            render("stable", version="1.4.1-wisp.1")
        with self.assertRaises(ValueError):
            render("stable", sha256=SHA)


if __name__ == "__main__":
    unittest.main()
