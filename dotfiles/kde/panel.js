// Plasma scripting API (run through: qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat panel.js)")
// One floating bottom panel: app menu (mouse fallback; Meta opens KRunner), icon-only task manager with pinned apps,
// system tray, clock, show-desktop. Re-applied only when ~/.config/.linux-setup-panel-applied is deleted.
var existing = panels();
for (var i = 0; i < existing.length; i++) { existing[i].remove(); }

var p = new Panel();
p.location = "bottom";
p.height = 44;
p.alignment = "center";
p.lengthMode = "fill";
p.hiding = "none";
p.floating = true;

var menu = p.addWidget("org.kde.plasma.kickoff");
menu.currentConfigGroup = ["General"];
menu.writeConfig("icon", "start-here-kde-symbolic");

var tasks = p.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
  // Pinned = always visible, click to launch. Only apps opened constantly earn a slot;
  // everything else is one KRunner keystroke away (Meta, then type). Chosen 2026-09-05
  // from actual use: RStudio/Positron/Obsidian were dropped as they are launched rarely.
  "applications:com.mitchellh.ghostty.desktop",   // terminal
  "applications:google-chrome.desktop",           // browser
  "applications:code.desktop",                    // editor
  "applications:org.kde.dolphin.desktop",         // file manager
  "applications:com.spotify.Client.desktop"       // music
].join(","));
tasks.writeConfig("groupingStrategy", 0);
tasks.writeConfig("middleClickAction", "NewInstance");
tasks.writeConfig("showOnlyCurrentScreen", false);

p.addWidget("org.kde.plasma.marginsseparator");
var tray = p.addWidget("org.kde.plasma.systemtray");
var clock = p.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
p.addWidget("org.kde.plasma.showdesktop");
