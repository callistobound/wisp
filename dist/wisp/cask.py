"""
Prints Wisp's Homebrew cask for callistobound/homebrew-tap.

Usage:
    cask.py tip
    cask.py stable VERSION SHA256     # VERSION like 1.4.1-wisp.1
"""

import sys

RELEASES = "https://github.com/callistobound/wisp/releases/download"
APP_ID = "com.callistobound.wisp"

HEADER = {
    "stable": """cask "wisp" do
  version "{version}"
  sha256 "{sha256}"

  url "{releases}/v#{{version}}/Wisp.dmg"
""",
    "tip": """cask "wisp@tip" do
  version :latest
  sha256 :no_check

  url "{releases}/tip/Wisp.dmg"
""",
}

BODY = """  name "Wisp"
  desc "Terminal emulator, a downstream fork of Ghostty"
  homepage "https://github.com/callistobound/wisp"

{auto_updates}  conflicts_with cask: "{other}"
  depends_on macos: :ventura

  app "Wisp.app"
  binary "#{{appdir}}/Wisp.app/Contents/MacOS/wisp"
  bash_completion "#{{appdir}}/Wisp.app/Contents/Resources/bash-completion/completions/wisp.bash"
  zsh_completion "#{{appdir}}/Wisp.app/Contents/Resources/zsh/site-functions/_wisp"
  fish_completion "#{{appdir}}/Wisp.app/Contents/Resources/fish/vendor_completions.d/wisp.fish"

  uninstall quit: "{app_id}"

  zap trash: [
    "~/.cache/wisp",
    "~/.config/wisp",
    "~/Library/Application Support/{app_id}",
    "~/Library/Caches/{app_id}",
    "~/Library/HTTPStorages/{app_id}",
    "~/Library/Preferences/{app_id}.plist",
    "~/Library/Saved Application State/{app_id}.savedState",
    "~/Library/WebKit/{app_id}",
  ]
end
"""


def render(channel, version=None, sha256=None):
    if channel == "stable" and not (version and sha256):
        raise ValueError("a stable cask needs a version and a sha256")
    other = "wisp@tip" if channel == "stable" else "wisp"
    head = HEADER[channel].format(version=version, sha256=sha256, releases=RELEASES)
    # Homebrew only skips upgrades for auto_updates casks with a real version.
    auto_updates = "  auto_updates true\n" if channel == "stable" else ""
    return head + BODY.format(other=other, app_id=APP_ID, auto_updates=auto_updates)


def main(argv):
    if argv[:1] == ["tip"] and len(argv) == 1:
        print(render("tip"), end="")
    elif argv[:1] == ["stable"] and len(argv) == 3:
        print(render("stable", version=argv[1], sha256=argv[2]), end="")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
