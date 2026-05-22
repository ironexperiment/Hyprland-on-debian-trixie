#!/usr/bin/env bash
# Re-apply GCC 14 / libstdc++ 14 compatibility patches for Hyprland on Debian Trixie.
# Run from inside the Hyprland source tree. Pass the path to the .patch file as
# the first argument (defaults to ./hyprland-gcc14-compat.patch).
set -euo pipefail

PATCH="${1:-hyprland-gcc14-compat.patch}"

if [[ ! -f "$PATCH" ]]; then
  echo "error: patch file not found: $PATCH" >&2
  echo "usage: $0 [path/to/hyprland-gcc14-compat.patch]" >&2
  exit 1
fi

# 1. Regenerate the byte-array include (replaces C++26 #embed in defaultConfig.hpp)
python3 -c "
import pathlib
data = pathlib.Path('example/hyprland.conf').read_bytes()
rows = []
for i in range(0, len(data), 16):
    rows.append(', '.join(f'0x{b:02x}' for b in data[i:i+16]))
pathlib.Path('src/config/example_hyprland_conf_bytes.inc').write_text(',\n'.join(rows) + '\n')
print(f'wrote {len(data)} bytes -> src/config/example_hyprland_conf_bytes.inc')
"

# 2. Apply source patches (#embed -> #include, ternary cast, insert_range, string+string_view)
git apply "$PATCH"
echo "Patches applied."
