# Design system: a bespoke modern workstation, not a rice project

Target: Omarchy-level cohesion and intent, KDE flexibility, Ubuntu stability. Omarchy looks good because one hand controls the
whole visual language; Plasma looks bad the moment unrelated themes, widgets, docks, icon packs and scripts pile up. So the
build is constrained: exactly one of each thing, applied by `setup.d/30-desktop-kde.sh`, and nothing added outside it.

## The constraints (one of each)

| Layer | Choice | Rule |
|---|---|---|
| Fonts | Inter (UI), JetBrainsMono Nerd Font (mono) | no other font families anywhere: terminal, editor, browser UI, SDDM all use these two |
| Icons | Papirus-Dark | no second icon set, no per-app icon packs |
| Colors | one palette, wallpaper-derived (see decision below) | terminal, editor and browser follow the same dark palette; no hand-picked per-app themes that clash |
| Window style | one decoration + one application style (see decision below) | never mix decoration from one theme with widgets from another |
| Panel | one floating, icon-only bottom panel, native Plasma widgets only (launcher, tasks, tray, clock, show-desktop) | no dock, no Latte, no panel colorizer, no second panel |
| Launcher | KRunner on Meta | the app menu stays on the panel for the mouse only; no start-menu clones |
| Desktop | empty: wallpaper only | no icons, no widgets, no folder view |
| Effects | subtle blur and translucency, modest rounding, soft shadow | no wobbly windows, no magic lamp, no glow, no animated cursors |
| Third-party Plasma components | at most: one window style (if verified), Polonium (off by default), the KRunner agent plugin (ours) | every addition needs a line in this file and a removal of whatever it replaces |
| Lock and login | same wallpaper, same fonts, same palette as the desktop; no clutter | SDDM Breeze theme with our wallpaper; lock screen without media controls |
| Tiling | Plasma's manual snapping + window rules + named workspaces; auto-tiling optional | tiling is a mode you can switch on, not the interaction model |

Where this build beats Omarchy: full KDE settings, multi-monitor that works, Dolphin, KDE Connect, floating windows by default,
GUI configuration when it is faster, Ubuntu package compatibility, agent-driven administration, and an Intel Arc-friendly stack.

## Decisions requiring third-party components

Settled 2026-09-03 after research and adversarial verification. Rule of thumb: on Kubuntu 26.04 LTS Plasma stays at 6.6.x for the
life of the release, so a *packaged* third-party theme is low risk; a *daemon that rewrites config files at runtime* is not.

### Window style: Klassy (adopted)

Klassy 6.7.2 targets Plasma 6.6.1 and newer, and upstream publishes an official Ubuntu 26.04 build at
`download.opensuse.org/repositories/home:/paulmcauley/xUbuntu_26.04/` (repository dated 2026-09-02, with `Release.key` and an
`amd64` tree). That removes the objection that mattered: no source build, no unmaintained community package, no PPA archaeology.
Verification also established what is *not* true: Klassy is absent from the Ubuntu archive and from Debian, and the only Launchpad
PPA carrying the name ships a Plasma 5.27-era build that would not work here.

`setup.d/30-desktop-kde.sh` adds that repo, installs `klassy`, and sets it as both window decoration and application style, writing
the `org.kde.kdecoration2` and `org.kde.kdecoration3` groups so a KWin group rename cannot silently strand the setting. If the repo
is unreachable or the package fails, the module logs a warning and Breeze stays in place: the desktop is never left half-themed.
Set `ENABLE_KLASSY="no"` to opt out. Klassy's own settings stay at their restrained defaults; tune with `klassy-settings`, never by
hand-editing `klassyrc`, and keep the look modest: small radius, no borders, thin titlebar, soft shadow, no glow.

### Color system: native Plasma, wallpaper-derived (kde-material-you-colors rejected)

Plasma 6.6 derives the accent colour from the wallpaper natively (`kdeglobals` > `General` > `AccentColorFromWallpaper`, plus
optional tinting), which already satisfies "one colour system, wallpaper-derived". `kde-material-you-colors` would add a
background Python daemon that rewrites colour schemes and per-app config on every wallpaper change: more reach (it can also theme
Konsole and friends), but it is exactly the runtime-mutating component this document exists to keep out, and it fails in ways that
are tedious to debug. Native it is, with app-level consistency handled once, statically: Chrome follows the system scheme, VS Code
uses `window.autoDetectColorScheme`, Ghostty and Konsole carry a matching dark palette.

## Consistency across apps (the part people forget)

- Chrome: system title bar and borders on, theme "Device" so it follows Plasma's dark mode; minimal toolbar.
- VS Code: `window.autoDetectColorScheme` on, a dark theme tonally close to the Plasma palette, same mono font.
- Ghostty: theme tonally matched to the Plasma palette, same mono font, no bell, thin padding.
- Konsole (fallback terminal): profile with the same font and a matching color scheme.
- Zoom, Spotify, Obsidian, Mark Text: dark mode on; nothing else.

## How agents must treat this

- Before adding any theme, widget, KWin script, effect, dock, icon set or font: check this file. If it is not one of the chosen
  components, do not add it; propose a replacement of the existing choice instead, in a commit that removes the old one.
- Changes go into `setup.d/30-desktop-kde.sh` (and `dotfiles/kde/panel.js`), never into a live session only.
- Screenshots that look impressive are not the goal; a desktop that looks the same in three years is.
