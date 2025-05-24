#!/usr/bin/env bash

# Script to set up Anki theming with Wallbash using ReColor add-on
# Creates anki.dcol and anki.sh, patches colors.py, and generates wallbash.json
# Run with -remove to revert all changes, restoring Anki to a fresh state

set -e

WALLBASH_ALWAYS_DIR="$HOME/.config/hyde/wallbash/always"
WALLBASH_SCRIPTS_DIR="$HOME/.config/hyde/wallbash/scripts"
ANKI_DCOL="$WALLBASH_ALWAYS_DIR/anki.dcol"
ANKI_SH="$WALLBASH_SCRIPTS_DIR/anki.sh"
RECOLOR_DIR="$HOME/.local/share/Anki2/addons21/688199788"
RECOLOR_THEME_DIR="$RECOLOR_DIR/themes"
RECOLOR_JSON="$RECOLOR_THEME_DIR/wallbash.json"
COLORS_CONF="$HOME/.config/hypr/themes/colors.conf"
META_JSON="$RECOLOR_DIR/meta.json"
PREFS_DB="$HOME/.local/share/Anki2/User 1/prefs21.db"
COLORS_PY="$RECOLOR_DIR/colors.py"
COLORS_PY_BAK="$COLORS_PY.bak"
CACHE_DIR="$HOME/.cache/hyde/wallbash"

remove_changes() {
  echo "Removing all changes made by the script..."

  for file in "$ANKI_DCOL" "$ANKI_SH" "$RECOLOR_JSON"; do
    if [[ -f "$file" ]]; then
      rm "$file"
      echo "Removed $file"
    else
      echo "File not found, skipping: $file"
    fi
  done

  if [[ -f "$COLORS_PY_BAK" ]]; then
    mv "$COLORS_PY_BAK" "$COLORS_PY"
    echo "Restored original $COLORS_PY from backup"
  else
    echo "Backup $COLORS_PY_BAK not found, skipping"
  fi

  if [[ -f "$META_JSON" ]] && [[ -f "$RECOLOR_DIR/config.json" ]] && command -v jq >/dev/null 2>&1; then
    cp "$META_JSON" "${META_JSON}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Backed up $META_JSON"
    jq --argjson config_colors "$(jq .colors "$RECOLOR_DIR/config.json")" \
       '.config.colors = $config_colors' "$META_JSON" > "${META_JSON}.tmp" && \
       mv "${META_JSON}.tmp" "$META_JSON"
    echo "Reset $META_JSON colors to default from config.json"
  else
    echo "Warning: Cannot reset $META_JSON (missing file or jq)"
  fi

  if [[ -f "$PREFS_DB" ]] && command -v sqlite3 >/dev/null 2>&1; then
    cp "$PREFS_DB" "${PREFS_DB}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Backed up $PREFS_DB"
    sqlite3 "$PREFS_DB" "UPDATE prefs SET value = json_remove(value, '$.688199788.theme') WHERE key = 'add-ons';"
    echo "Removed wallbash theme from $PREFS_DB"
  else
    echo "Warning: Cannot update $PREFS_DB (missing file or sqlite3)"
  fi

  echo "Removal complete! Anki should be restored to a fresh state."
  echo "You may need to restart Anki and reselect a theme in ReColor."
  exit 0
}

if [[ "$1" == "-remove" ]]; then
  remove_changes
fi

if [[ $EUID -eq 0 ]]; then
  echo "This script should not be run as root."
  exit 1
fi

echo "Patching $COLORS_PY to handle KeyError for BUTTON_HOVER..."
if [[ -f "$COLORS_PY" ]]; then
  cp "$COLORS_PY" "$COLORS_PY_BAK"
  sed -i '/replace_color(color_entries, "BUTTON_GRADIENT_END", "BUTTON_HOVER")/d' "$COLORS_PY"
  sed -i '/def replace_color(color_entries, anki_name, addon_name=None):/a\
    if addon_name and addon_name not in color_entries:\
        print(f"Warning: Color key {addon_name} not found in color_entries")\
        return' "$COLORS_PY"
  echo "Patched $COLORS_PY successfully"
else
  echo "Error: $COLORS_PY not found, cannot patch"
  exit 1
fi

echo "Creating $ANKI_DCOL..."
cat > "$ANKI_DCOL" << 'EOF'
/home/$USER/.local/share/Anki2/addons21/688199788/themes/wallbash.json|${WALLBASH_SCRIPTS}/anki.sh
{
    "colors": {
        "CANVAS": ["Background", "#<wallbash_pry1>", "#<wallbash_pry1>", ["--canvas", "--bs-body-bg"]],
        "CANVAS_ELEVATED": ["Review", "#<wallbash_pry1>", "#<wallbash_pry1>", "--canvas-elevated"],
        "CANVAS_GLASS": ["Background (transparent text surface)", "#<wallbash_pry1>66", "#<wallbash_pry1>66", "--canvas-glass"],
        "FG": ["Text", "#<wallbash_txt1>", "#<wallbash_txt1>", ["--fg", "--bs-body-color"]],
        "FG_SUBTLE": ["Text (subtle)", "#<wallbash_txt4>", "#<wallbash_txt4>", "--fg-subtle"],
        "BUTTON_BG": ["Button background", "#<wallbash_pry1>", "#<wallbash_pry1>", "--button-bg"],
        "ACCENT_CARD": ["Card mode", "#89b4fa", "#89b4fa", "--accent-card"]
    },
    "version": {
        "major": 3,
        "minor": 0
    }
}
EOF

echo "Creating or overwriting $ANKI_SH..."
cat > "$ANKI_SH" << 'EOF'
#!/usr/bin/env bash
# Updates wallbash.json, merges colors into meta.json, and logs details
json_file="${HOME}/.local/share/Anki2/addons21/688199788/themes/wallbash.json"
meta_json="${HOME}/.local/share/Anki2/addons21/688199788/meta.json"
prefs_db="${HOME}/.local/share/Anki2/User 1/prefs21.db"
cache_dir="${HOME}/.cache/hyde/wallbash"
colors_conf="${HOME}/.config/hypr/themes/colors.conf"
mkdir -p "${cache_dir}"

if [[ -f "${json_file}" ]]; then
  cp "${json_file}" "${cache_dir}/anki-wallbash.json"
  echo "Anki ReColor theme updated with Wallbash colors: ${json_file}"
  echo "JSON content:" >> "${cache_dir}/anki-wallbash.log"
  cat "${json_file}" >> "${cache_dir}/anki-wallbash.log"

  # Merge wallbash.json colors into meta.json
  if [[ -f "${meta_json}" ]] && command -v jq >/dev/null 2>&1; then
    jq --argjson new_colors "$(jq .colors "${json_file}")" \
       '.config.colors |= ($new_colors + .config.colors)' "${meta_json}" > "${cache_dir}/meta.json.tmp" && \
       mv "${cache_dir}/meta.json.tmp" "${meta_json}"
    echo "Merged wallbash.json colors into meta.json" >> "${cache_dir}/anki-wallbash.log"
  else
    echo "Warning: meta.json not found or jq not installed, cannot update colors" >> "${cache_dir}/anki-wallbash.log"
  fi

  # Update prefs21.db to ensure wallbash is selected
  if [[ -f "${prefs_db}" ]] && command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "${prefs_db}" "INSERT OR IGNORE INTO prefs (key, value) VALUES ('add-ons', '{}');"
    sqlite3 "${prefs_db}" "UPDATE prefs SET value = json_set(value, '$.688199788.theme', 'wallbash') WHERE key = 'add-ons';"
    echo "Updated prefs21.db to set ReColor theme: wallbash" >> "${cache_dir}/anki-wallbash.log"
  else
    echo "Warning: prefs21.db not found or sqlite3 not installed, cannot update theme" >> "${cache_dir}/anki-wallbash.log"
  fi

  # Log colors.conf
  echo "colors.conf content:" >> "${cache_dir}/anki-wallbash.log"
  if [[ -f "${colors_conf}" ]]; then
    cat "${colors_conf}" >> "${cache_dir}/anki-wallbash.log"
  else
    echo "colors.conf not found at ${colors_conf}" >> "${cache_dir}/anki-wallbash.log"
  fi

  # Validate JSON
  if command -v jq >/dev/null 2>&1; then
    if jq . "${json_file}" >/dev/null 2>&1; then
      echo "JSON is valid" >> "${cache_dir}/anki-wallbash.log"
    else
      echo "Error: Invalid JSON in ${json_file}" >> "${cache_dir}/anki-wallbash.log"
    fi
    if jq . "${meta_json}" >/dev/null 2>&1; then
      echo "meta.json is valid" >> "${cache_dir}/anki-wallbash.log"
    else
      echo "Error: Invalid JSON in ${meta_json}" >> "${cache_dir}/anki-wallbash.log"
    fi
  else
    echo "jq not installed, skipping JSON validation" >> "${cache_dir}/anki-wallbash.log"
  fi
else
  echo "Error: Anki ReColor JSON file not found at ${json_file}"
  echo "Error: Check Wallbash execution, permissions, or anki.dcol syntax" >> "${cache_dir}/anki-wallbash.log"
fi
EOF
chmod +x "$ANKI_SH"

echo "Verifying created files..."
ls -l "$ANKI_DCOL"
ls -l "$ANKI_SH"
ls -l "$COLORS_PY"

if [[ -w "$RECOLOR_THEME_DIR" ]]; then
  echo "Themes directory is writable: $RECOLOR_THEME_DIR"
else
  echo "Warning: Themes directory is not writable, attempting to fix permissions..."
  chmod -R u+rw "$RECOLOR_THEME_DIR"
fi

if [[ -f "$COLORS_CONF" ]]; then
  for var in wallbash_pry1 wallbash_txt1 wallbash_txt4; do
    if grep -q "$var" "$COLORS_CONF"; then
      echo "$var defined in colors.conf"
    else
      echo "Warning: $var not defined in colors.conf, may cause substitution issues"
    fi
  done
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not installed, required for updating meta.json"
  echo "Install it with: sudo pacman -S jq"
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: sqlite3 not installed, required for updating prefs21.db"
  echo "Install it with: sudo pacman -S sqlite"
fi

echo "Setup complete! Please follow these steps to test:"
echo "To test make sure to reload wallbash/change wallpapers"
echo "Run anki and verify changes"
echo "To remove all changes: $0 -remove"
