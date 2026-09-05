#!/usr/bin/env bash
# app-categories.sh - regroup the application menu around how this machine is used.
#
# Kubuntu ships ~213 menu entries in generic XDG categories (Utility, System, Qt...), 82 of
# them with no category at all. This replaces that with categories that match the work:
# AI, IDEs, Science, Containers, Terminal.
#
# Nothing in /usr is modified. For each app a *copy* of its .desktop file is written to
# ~/.local/share/applications/ with an added X- category, which takes precedence for this
# user only. Uninstalling or reinstalling the app never conflicts, and deleting the files
# this script creates restores the stock menu exactly.
#
# Idempotent: re-run after installing new apps.
set -euo pipefail

APPS="$HOME/.local/share/applications"
DIRS="$HOME/.local/share/desktop-directories"
MENUS="$HOME/.config/menus"
mkdir -p "$APPS" "$DIRS" "$MENUS"

# category|icon|desktop-file-ids (space separated; missing ones are skipped)
CATEGORIES=$(cat <<'EOF'
AI|preferences-desktop-ai|net.mkiol.SpeechNote.desktop
IDEs|applications-development|code.desktop rstudio.desktop positron.desktop com.github.marktext.marktext.desktop md.obsidian.Obsidian.desktop cursor.desktop
Science|applications-science|R.desktop rstudio.desktop positron.desktop quarto.desktop jupyter.desktop org.pymol.PyMOL.desktop
Containers|applications-development|docker-desktop.desktop distrobox.desktop
Terminal|utilities-terminal|com.mitchellh.ghostty.desktop org.kde.konsole.desktop
EOF
)

# Entries that exist only to register a MIME type or URL scheme. They are not applications
# and only add noise to the launcher; hidden per-user, never uninstalled.
NOISE=$(cat <<'EOF'
okularApplication_comicbook.desktop okularApplication_djvu.desktop okularApplication_dvi.desktop
okularApplication_epub.desktop okularApplication_fax.desktop okularApplication_fb.desktop
okularApplication_ghostview.desktop okularApplication_kimgio.desktop okularApplication_md.desktop
okularApplication_mobi.desktop okularApplication_tiff.desktop okularApplication_txt.desktop
okularApplication_xps.desktop
code-url-handler.desktop claude-code-url-handler.desktop google-maps-geo-handler.desktop
openstreetmap-geo-handler.desktop org.kde.baloorunner.desktop
EOF
)

find_desktop() {
  local id="$1" d
  for d in /usr/share/applications ~/.local/share/applications \
           /var/lib/flatpak/exports/share/applications \
           ~/.local/share/flatpak/exports/share/applications \
           /usr/local/share/applications; do
    [[ -f "$d/$id" ]] && { printf '%s\n' "$d/$id"; return 0; }
  done
  return 1
}

echo "== categorising =="
while IFS='|' read -r cat icon ids; do
  [[ -n "${cat:-}" ]] || continue
  n=0
  for id in $ids; do
    src="$(find_desktop "$id")" || continue
    # A file already in $APPS is edited in place; anything else is copied there first.
    dest="$APPS/$id"
    [[ "$src" == "$dest" ]] || cp -f "$src" "$dest"
    # Append the category rather than replacing, so the app keeps its stock groupings too.
    if grep -q "^Categories=" "$dest"; then
      grep -q "X-$cat;" "$dest" || sed -i "0,/^Categories=/s//Categories=X-$cat;/" "$dest"
    else
      printf 'Categories=X-%s;\n' "$cat" >>"$dest"
    fi
    n=$((n+1))
  done
  [[ $n -gt 0 ]] && printf '  %-11s %d app(s)\n' "$cat" "$n"

  cat >"$DIRS/linux-setup-${cat,,}.directory" <<EOF
[Desktop Entry]
Type=Directory
Name=$cat
Icon=$icon
EOF
done <<<"$CATEGORIES"

echo "== hiding MIME/URL-handler stubs =="
h=0
for id in $NOISE; do
  src="$(find_desktop "$id")" || continue
  dest="$APPS/$id"
  [[ "$src" == "$dest" ]] || cp -f "$src" "$dest"
  grep -q '^NoDisplay=true' "$dest" || printf 'NoDisplay=true\n' >>"$dest"
  h=$((h+1))
done
echo "  hid $h stub entries (packages untouched; they still handle their file types)"

echo "== writing the menu layout =="
{
  cat <<'EOF'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
<Menu>
  <Name>Applications</Name>
  <MergeFile type="parent">/etc/xdg/menus/applications.menu</MergeFile>
EOF
  while IFS='|' read -r cat icon ids; do
    [[ -n "${cat:-}" ]] || continue
    cat <<EOF
  <Menu>
    <Name>$cat</Name>
    <Directory>linux-setup-${cat,,}.directory</Directory>
    <Include><Category>X-$cat</Category></Include>
  </Menu>
EOF
  done <<<"$CATEGORIES"
  echo '</Menu>'
} > "$MENUS/applications.menu"
echo "  wrote $MENUS/applications.menu"

update-desktop-database "$APPS" 2>/dev/null || true
kbuildsycoca6 --noincremental >/dev/null 2>&1 || kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
echo "== done. Open the launcher (Meta) to see the new groups. =="
echo "   To undo entirely:  rm -f $MENUS/applications.menu $DIRS/linux-setup-*.directory"
