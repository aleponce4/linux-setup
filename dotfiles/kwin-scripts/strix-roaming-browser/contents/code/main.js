// One browser window that changes place and size with the virtual desktop.
//
// A window has a single geometry, so this cannot be expressed as a KWin rule. The window
// is marked by being on all desktops -- that flag is the handle, which avoids needing a
// distinct window class (every normal Chrome window reports "google-chrome", so class
// matching cannot separate a side window from a main one).
//
// Chrome applies geometry changes asynchronously: reading frameGeometry back in the same
// tick still shows the old value. Do not "verify" inline and conclude it failed.

var SLOTS = {
    // desktop name -> geometry
    "CODE": { output: "DP-2",     x: 0,    y: 0,   width: 1080, height: 960  },
    "WEB":  { output: "HDMI-A-3", x: 1300, y: 400, width: 2000, height: 1150 }
};
var BROWSER = /^google-chrome$/;

function place() {
    var name = workspace.currentDesktop.name;
    var slot = SLOTS[name];
    if (!slot) { return; }                       // desktop with no opinion: leave it alone
    workspace.windowList().forEach(function (w) {
        if (!w.normalWindow || !w.onAllDesktops) { return; }
        if (!BROWSER.test(w.resourceClass)) { return; }
        if (w.fullScreen) { return; }
        w.setMaximize(false, false);
        // Move to the correct output first. Assigning coordinates alone is unreliable
        // across screens: Chrome takes the size but stays on its current output.
        var target = null;
        workspace.screens.forEach(function (s) { if (s.name === slot.output) { target = s; } });
        if (target && w.output && w.output.name !== slot.output) {
            workspace.sendClientToScreen(w, target);
        }
        w.frameGeometry = { x: slot.x, y: slot.y, width: slot.width, height: slot.height };
    });
}

workspace.currentDesktopChanged.connect(place);
place();
