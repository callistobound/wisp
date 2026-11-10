#!/usr/bin/env bash

set -euxo pipefail

old_pot=$(mktemp)
cp po/com.jamesboehmer.wisp.pot "$old_pot"
zig build update-translations

# Compare previous POT to current POT
msgcmp "$old_pot" po/com.jamesboehmer.wisp.pot --use-untranslated

# Compare all other POs to current POT
for f in po/*.po; do
  # Ignore untranslated entries
  msgcmp --use-untranslated "$f" po/com.jamesboehmer.wisp.pot;
done
