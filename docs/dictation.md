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

## Model: only WhisperCpp, never FasterWhisper

**Engine choice is a GPU decision, not an accuracy decision.** Measured difference on this
machine was roughly tenfold.

| Engine | Prefix | GPU on the B570? |
|---|---|---|
| WhisperCpp | `stt_whisper` | **Yes** -- Vulkan, via `whispercpp_use_gpu=true` |
| FasterWhisper | `stt_fasterwhisper` | No -- CTranslate2 has CUDA/CPU only, no Vulkan or Arc |

So every `stt_fasterwhisper` model is disqualified here no matter how it scores on accuracy.

Installed, best first:

| Model | Size | Notes |
|---|---|---|
| `multilang_whisper_large3_turbo` | 574 MB | **default** -- Large-v3 Turbo, near Large-v3 accuracy at Distil speed |
| `multilang_whisper_large` | 1.08 GB | full Large-v3, most accurate, slower |
| `en_whisper_distil_large3` | 538 MB | previous default; distilled, trades accuracy for speed |

    flatpak run --command=dsnote net.mkiol.SpeechNote --print-active-model stt

### Why the good models were invisible

Every multilingual WhisperCpp model ships with `"hidden": true` in `models.json`, so the
English model list shows only the distil variants and there is no full Large-v3 under `en_`.
Setting `default_model` to a hidden model silently reverts on restart -- which is what the
"the model keeps going back to FasterWhisper" symptom actually was.

Fix is to unhide it in `~/.var/app/net.mkiol.SpeechNote/data/net.mkiol/dsnote/models.json`
(app stopped), after placing the blob in
`~/.var/app/net.mkiol.SpeechNote/cache/net.mkiol/dsnote/speech-models/<model_id>.ggml`.
Download URLs and sizes are in `models.json`; the file size must match `size` exactly.

## Punctuation

`restore_punctuation` was `false`, which is a large part of why output read worse than a
commercial dictation tool. Now `true`.

Raw Whisper is verbatim: it keeps disfluencies and does not adapt casing or phrasing to
context. Tools like Wispr Flow run an LLM cleanup pass over the transcript afterwards, which
is a separate step from ASR and is not something a better Whisper model provides.

## Vocabulary corrections

`productivity/dictation/vocabulary.tsv` holds the replacement rules (Onteko, ProLIBSpector,
etc.); `productivity/bin/dictation-rules-apply` compiles them into `settings.conf`. Keep the
list short -- opening the GUI Rules page with many rules has corrupted the list before.
