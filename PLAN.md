# Plan: the duck on your phone, as a remote control for the PC duck

For the agent executing this in `C:\GitHub\godot-desktop-pet` (Godot 4.8.dev6, Windows PC, RTX 4080
Laptop 12 GB; the Mac also runs the duck). `C:\GitHub\CLAUDE.md` applies. Read the README first,
above all "Running it", "Talking to it", "Voices" and "As a rubber duck". Work in the order below;
each phase ends with its tests green and something the user can try. Nothing is committed until the
user asks.

## What it is

An Android app, in this same project, that shows the duck on the top half of the phone and a chat
on the bottom half, like the Claude Code Remote Control app. It is a remote control, not a second
duck: the brain (Foundry or llama.cpp, the 7B model), the duck's folder (`user://duck`: name,
personality, memories, skills, facts told) and the screen reading all stay on the PC. The phone
sends what you type or say and shows and speaks what comes back. So from the phone you talk to the
same duck, with the same memory and the same conversation, and it still sees the PC's screen:
sitting at the PC with the phone in hand, "why does this crash?" reads the editor on the PC.

Decisions already made by the user:
- A remote control, not a standalone phone duck (a phone-sized model could not read code; the
  1.5B already failed at it on the PC).
- The PC speaks for the phone: each sentence is synthesised by Kokoro on the PC and sent to the
  phone as audio, so the phone has the natural voice. System voices are not streamed; with a
  system voice chosen the phone uses its own Android voice.

Not in this plan: reading the phone's screen (no use for it), running without the PC duck, and
reaching the PC from outside the home network (Tailscale does that with no code: the phone then
types the PC's Tailscale name into the address field in step 9).

## Baseline, what exists and is reused

- `Brain` already streams: `sentence(text)` as each sentence is written, `replied(text)` at the
  end, `status_changed(text)` while waking. First sentence on the PC in about 0.7 s. `Brain.ask`
  takes the line and the screen text; `Pet._send` does the whole turn (heed, search, screen read,
  ask) and `Pet._on_brain_sentence` shows and speaks each sentence.
- `Kokoro` synthesises sentence by sentence into `user://kokoro/say_N.wav` (0.3 to 1.6 s a
  sentence, `kokoro-server` kept loaded) and plays them in order; `Kokoro._synthesized(wav, batch,
  index, ok)` is where a finished WAV lands.
- `Listener` records the mic into a 16 kHz WAV (`to_wav`, `resample`, the pause rule) and
  transcribes it with `foundry transcribe` on a thread (`_transcribe` writes the WAV, `_run`
  transcribes, `heard(text)` reports). Parakeet takes 0.1 to 0.3 s. The split for the phone is at
  `_transcribe`: the phone makes the WAV, the PC transcribes it.
- `scenes/duck.tscn` is the 3D duck in its own scene, already shown through a SubViewport in
  `pet.tscn`; `Duck.play(&"sleep" | &"wake" | &"idle" | &"think" | &"talk" | &"squeeze" | ...)`
  poses it. It runs on the Compatibility renderer, which is what Android gets.
- Godot has what the network needs built in, no addon: `TCPServer` plus `WebSocketPeer.accept_stream`
  make a WebSocket server (the pattern in Godot's own websocket demo), `WebSocketPeer` is the
  client, `PacketPeerUDP` with `set_broadcast_enabled(true)` is the beacon, `AudioStreamWAV`
  `load_from_buffer` plays received audio, `AudioStreamMicrophone` records on Android,
  `DisplayServer.tts_*` speaks there. `OS.request_permission("RECORD_AUDIO")` asks for the mic.
- Not set up on the PC: an Android SDK, a JDK, the 4.8.dev6 export templates and any export preset
  (`export_presets.cfg` does not exist). `export/android/debug_keystore` is already set in the
  editor settings. That setup is phase 1.
- `project.godot` sets the desktop window at the top level: 144 px, borderless, transparent,
  always on top, `viewport/transparent_background`. Android must not inherit those: override
  them with feature tags (`display/window/size/transparent.android=false`, and so on; Godot
  reads `setting.android` on Android), and set `application/run/main_scene.android` to the phone
  scene the same way, so one project serves both.

## Protocol

One WebSocket connection from the phone to the PC on port 39842 (Foundry has 39839, the Mac's
llama-server 39841). Text frames are JSON, one object each; binary frames carry audio with a
one-byte kind in front. Keep it this small:

| From | Frame | Meaning |
| --- | --- | --- |
| phone | `{"hello": "<pairing code>", "name": "<phone model>"}` | first frame; a wrong code is answered with `{"bye": "wrong code"}` and the socket closed |
| PC | `{"welcome": "<duck name>", "status": "<Brain.status>", "state": "sleep\|idle\|think\|talk", "speaks": true}` | `speaks` is whether audio will be streamed (a Kokoro voice is chosen on the PC) |
| phone | `{"say": "<line>"}` | typed on the phone; the PC runs its full turn, screen read included |
| phone | binary `0x01` + WAV bytes | a spoken sentence from the phone's mic, 16 kHz mono, as `Listener.to_wav` makes it |
| PC | `{"you": "<text>"}` | what the PC transcribed from that WAV; "" with `"error"` when nothing was heard |
| PC | `{"sentence": "<text>", "index": n}` | each sentence as `Brain.sentence` emits it |
| PC | binary `0x02` + index as uint32 little-endian + WAV bytes | that sentence's audio, when `speaks` |
| PC | `{"replied": "<text>", "notes": "<what was remembered>"}` | the whole answer, `Brain.replied` plus `Pet._take_notes` |
| PC | `{"state": "...", "status": "..."}` | whenever the duck's state or the brain's status changes |
| either | `{"ping": t}` / `{"pong": t}` | every 5 s from the phone; three misses and the phone shows "lost the PC" and reconnects |

The pairing code is six digits made on first run, kept in `user://settings.cfg` under
`[remote] code`, shown on the PC's Settings tab beside the port and the PC's addresses. It stops
anyone else on the Wi-Fi from chatting with the duck (and reading the screen through it).

The beacon: the PC sends `duck 39842 <duck name>` by UDP broadcast to port 39843 once a second
while running. The phone listens on 39843 and offers the PCs it hears; it also keeps an address
field for a PC it cannot hear (another network, Tailscale).

## Phase 0: the PC side, testable without a phone

1. **`scripts/remote.gd` (`Remote`, a node in `pet.tscn`).** Owns a `TCPServer` on `port`
   (export, 39842), accepts connections in `_process`, wraps each in `WebSocketPeer.accept_stream`,
   polls them, reads frames, and keeps a list of paired clients. A client is paired once its
   `hello` carried the code. It connects to `Brain.sentence`, `Brain.replied`,
   `Brain.status_changed` and a new `Pet.state_changed(state)` signal (emit it from the `state`
   setter), and relays them. A `say` from the phone calls `Pet.send_remote(line)`, which is
   `_send` without the bubble (same heed, search, screen read and ask; the bubble shows it too if
   open, under "You (phone): ..."). Only one turn at a time: a `say` while `Pet.is_thinking()` is
   answered `{"busy": true}`. The beacon lives here too: a `PacketPeerUDP` with broadcast on,
   sending once a second from a Timer. Exports: `port`, `beacon_port`, `enabled`.
2. **Pairing code and the Settings tab.** `Remote.code()` makes and keeps the code in
   `settings.cfg`. The Settings tab gets a "Phone" row: `Pair code 123456  ·  192.168.4.63:39842`
   (every `IP.get_local_addresses()` that is private IPv4), greyed with "no phone" or showing the
   phone's name when one is connected. A test asserts the tab still fits the 340 by 240 bubble
   (`test_the_settings_tab_fits_with_room_for_the_status_line` in test_kokoro.gd is the pattern).
3. **Audio out.** When a Kokoro voice is chosen and a phone is connected, each sentence's WAV goes
   to the phone with its index, and the PC does not play it unless `Remote.speak_here_too` (export,
   default off) is on. Hook: give `Kokoro` a signal `sentence_ready(index, wav_path)` emitted in
   `_synthesized` before it queues playback, and let `Remote` read the file and send it; `Voice`
   gets `play_locally: bool` that `Kokoro._play_next` honours. With a system voice, the PC sends no
   audio and `welcome.speaks` is false.
4. **Audio in.** `Listener.transcribe_wav(bytes)` writes them to `WAV_PATH` and runs the existing
   `_run` on the thread; `Remote` calls it for a `0x01` frame and sends `you` with the result, then
   `Pet.send_remote(text)` as if typed. While it transcribes, the PC's own mic is paused.
5. **Tests.** `tests/unit/test_remote.gd`: frames parse and build (`Remote.parse_frame`,
   `Remote.audio_frame(index, bytes)` and its reverse); a wrong code is refused; the beacon line;
   the code is six digits and kept. An integration test runs a `Remote` on a free port and a
   `WebSocketPeer` client in the same test, sends `hello` and `say`, and asserts the relayed
   `sentence` and `replied` from a stub Brain (emit the signals by hand; no model). Loopback TCP
   works headless. Keep the model out of unit tests.
6. **A PC-side client, `tools/remote_client.gd`**, run with `godot --headless --path . -s`, that
   pairs, sends a line, prints the sentences and timings, and saves the audio frames to WAVs: the
   way to check the PC side end to end with the real brain, before any phone exists. Run it under
   the watchdog, model loaded, unload after.

## Phase 1: the Android toolchain, once

7. **Set up and prove an export.** JDK 17 (`winget install Microsoft.OpenJDK.17`), Android
   command-line tools into `C:\Android\cmdline-tools\latest`, then `sdkmanager "platform-tools"
   "build-tools;35.0.0" "platforms;android-35"` and accept the licences; set
   `export/android/java_sdk_path` and `android_sdk_path` in the editor settings; install the
   4.8.dev6 export templates (Editor > Manage Export Templates, or the `.tpz` from the
   godot-builds release for 4.8-dev6). Add an `Android` preset in `export_presets.cfg` (debug
   keystore as set, package `com.kirbycope.duck`, permissions `INTERNET`, `RECORD_AUDIO`,
   `ACCESS_WIFI_STATE`, portrait, min SDK 24). Export a debug APK of a one-label scene first, and
   install it on the user's phone with `adb install` over USB debugging, or send the APK with
   SendUserFile for them to sideload. Record each command in the README's "On your phone" section.
   This phase is the one with the unknowns (versions, the dev6 templates); do it before writing
   the phone UI, and stop and ask if a step needs an account or a download the agent cannot do.

## Phase 2: the phone app

8. **`scenes/remote.tscn` and `scripts/remote_app.gd`.** A portrait Control scene: top half a
   `SubViewportContainer` with `duck.tscn` (camera straight on, the duck turned to the viewer as
   in chat, `Duck.looking_at_viewer`), bottom half the chat: a scrolling `RichTextLabel` of the
   conversation, a `LineEdit`, a mic button with the red dot, Send, and a status line (Waking up,
   Thinking, Talking, Lost the PC). Tapping the duck squeezes it with the squeak, as on the PC.
   The duck plays `sleep` while the PC brain wakes, `think` after a line is sent, `talk` while
   audio plays, `idle` otherwise, from `state` frames. `application/run/main_scene.android` points
   here; `low_processor_mode.android=true` so it does not render at 60 fps on battery.
9. **Finding and pairing.** On start the app listens for the beacon for 3 s and lists the PCs it
   hears, with an address field for one it cannot; it asks for the code once and keeps it with the
   address in `user://remote.cfg`. Reconnects by itself when the socket drops.
10. **Text in, text out.** Typing a line sends `say`; `you`, `sentence` and `replied` fill the
    conversation. The last three exchanges are also fetched on connect, so the phone shows where
    the conversation was (`Mind.recent` already provides them; send them in `welcome`).

## Phase 3: voice

11. **Audio out on the phone.** A `0x02` frame becomes an `AudioStreamWAV` through
    `load_from_buffer`, queued by index and played in order on an `AudioStreamPlayer`, with the
    duck in `talk` while it plays. When `welcome.speaks` is false, the phone speaks each
    `sentence` with `DisplayServer.tts_speak` instead.
12. **Mic on the phone.** The `Listener` scene runs on the phone as it does on the PC (`Mic` bus
    and `AudioEffectCapture` are in `default_bus_layout.tres`; request `RECORD_AUDIO` first), but
    `_transcribe` sends the WAV as a `0x01` frame instead of running foundry: add `remote: bool` to
    `Listener`, or a `wav_ready(bytes)` signal the app connects. The phone's listener pauses while
    the duck talks and resumes after, with the same `pause_seconds` rule.

## Phase 4: close

13. README: an "On your phone" section (what it is, pairing, the beacon, Tailscale for away from
    home, the voice rule, the toolchain commands, the protocol table), the Settings tab row, and
    the settings table entries (`Remote.port`, `beacon_port`, `enabled`, `speak_here_too`). No new
    credits unless an asset is added. Full GUT suite green; the MCP verification runs `pet.tscn`
    on the PC with `tools/remote_client.gd` connected and screenshots the Settings tab; the phone
    gets screenshots from the device (`adb exec-out screencap -p`) in portrait, and an MP4 of a
    spoken turn if the user is there to speak. Send them to the user.

## Working notes

- Run anything over a minute under `../.claude/skills/watchdog/watchdog.sh`, in the background.
  GUT: `godot --headless --audio-driver Dummy --path . -s addons/gut/gut_cmdln.gd -gexit`,
  narrow with `-gselect=test_x.gd`. 221 tests pass now.
- The user's Godot editor is running (`godot.exe --editor`, the `pet.tscn` window); never kill it.
  Stop only processes you started. The PC duck started from the editor keeps the model loaded on
  close; a bench or client run from the command line unloads it, so expect a 45 s load.
- Python edit scripts: write them with the Write tool and use raw strings. A bash heredoc turns
  `\n` inside a Python string into a real line break and breaks GDScript literals.
- Live chat tests go through a scratch mind folder (`mind.root = "user://chat_test"` on the
  instanced `pet.tscn`), never the user's `user://duck`.
- The Mac session works in the same repository on the Mac side (llama.cpp, listening). Tell it
  before touching `Brain._boot`, `_exit_tree`, `Listener` or `Pet._send`, and pull its changes
  first; it is reachable through ListAgents as "MacBook - Duck".
- No emoji anywhere. Commit only when the user asks.
