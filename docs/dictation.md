# Dictation (Speech Note)

Press **Pause** and talk; the text lands in whatever window has focus.

## The one thing that will confuse you later

There are **two independent shortcut systems**, and Speech Note uses only one of them.

| System | Where it lives | Used by Speech Note? |
|---|---|---|
| KDE global shortcuts | `~/.config/kglobalshortcutsrc`, `[net.mkiol.SpeechNote]` | **No** |
| Speech Note's own hotkeys (xdg-desktop-portal GlobalShortcuts) | `~/.var/app/net.mkiol.SpeechNote/config/net.mkiol/dsnote/settings.conf` | **Yes** |

The `[net.mkiol.SpeechNote]` section in `kglobalshortcutsrc` looks authoritative and is
not. Editing it changes nothing. The key that actually fires dictation is:

    hotkey_start_listening_active_window=Pause

in `settings.conf`. Stop the app before editing that file -- it rewrites it on exit and
will discard your change, exactly like `kglobalshortcutsrc` does while Plasma is running.

    flatpak kill net.mkiol.SpeechNote
    # edit settings.conf
    flatpak run net.mkiol.SpeechNote

## It must be running

The hotkey is registered by the app at startup. If Speech Note is not running, the key
does nothing and there is no error anywhere. `dotfiles/autostart/strix-speechnote.desktop`
starts it at login; it was not autostarted before 2026-09-06 and a KWin crash on that date
killed it, which presented as "the dictation key stopped working".

`--service` mode starts it headless but does **not** answer `--print-state` or `--action`,
so autostart uses normal (standalone) mode.

## Scripted control

`productivity/bin/dictate-toggle` (installed as `~/.local/bin/dictate-toggle`) is a
press-to-start / press-to-stop toggle that talks to the running app over D-Bus:

    flatpak run --command=dsnote net.mkiol.SpeechNote --print-state task
    flatpak run --command=dsnote net.mkiol.SpeechNote --action start-listening-active-window

This path does not depend on the portal registration, so it is the reliable way to bind
dictation to a KDE shortcut if the app's own hotkey ever misbehaves.

## Model

Active STT model is `en_whisper_distil_large3` (WhisperCpp Distil Large-v3), which can use
the Arc B570 through Vulkan. FasterWhisper is CPU-only. Check with:

    flatpak run --command=dsnote net.mkiol.SpeechNote --print-active-model stt

## Vocabulary corrections

`productivity/dictation/vocabulary.tsv` holds the replacement rules (Onteko, ProLIBSpector,
etc.); `productivity/bin/dictation-rules-apply` compiles them into `settings.conf`. Keep the
list short -- opening the GUI Rules page with many rules has corrupted the list before.
