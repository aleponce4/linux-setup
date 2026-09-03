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
  "applications:com.mitchellh.ghostty.desktop",
  "applications:code.desktop",
  "applications:google-chrome.desktop",
  "applications:org.kde.dolphin.desktop",
  "applications:positron.desktop",
  "applications:rstudio.desktop"
]);
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
