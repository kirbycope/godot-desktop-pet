# Desktop Pet: a 3D rubber duck debugger

A Godot 4 desktop pet that keeps you company and that you can explain your code to. It chats
happily about anything, and turns into a proper rubber duck when you bring it a bug. A 3D rubber duck lives in its own transparent,
borderless, always-on-top window and waddles along the edges of your screen: across the top of the
taskbar or Dock, up the sides and upside down along the top. Click it and it quacks a greeting out
loud. Tell it what your code is meant to do; with every message it reads the text on your screen
with the operating system's OCR, so it can see the code and the error you are looking at, and it
answers out loud in the system voice you pick.

Everything runs on your machine: the language model runs locally through Foundry Local, on the NPU
when there is a supported one, or else the GPU, or else the CPU. Nothing leaves the computer.

The window handling follows DigiKey's [Desktop Pet](https://www.digikey.com/en/maker/projects/desktop-pet/994f9b5997fa4d6899c022c9b23724a6)
project: the pet moves the window, not a sprite inside it. This project adds the 3D duck, edge
walking, a mouse passthrough region so the empty part of the window does not block clicks on the
desktop, speech, screen reading and the chat.

## Running it

1. Install [Foundry Local](https://learn.microsoft.com/en-us/azure/foundry-local/), Microsoft's
   on-device model runtime:

   ```powershell
   winget install Microsoft.FoundryLocal          # Windows
   ```

   ```bash
   brew tap microsoft/foundrylocal && brew install foundrylocal   # macOS, Apple silicon
   ```

   On a Mac, also install [llama.cpp](https://github.com/ggml-org/llama.cpp), which runs the chat
   model on Metal (see [On a Mac](#on-a-mac)). Without it the duck still works, on Foundry, but
   takes about 20 s to start each answer:

   ```bash
   brew install llama.cpp
   ```

2. Open the project in Godot 4.8 and run it, or export it for Windows or macOS.

The duck starts asleep: it settles low on the taskbar, breathing slowly, with Zs drifting up from
it, while it looks at the hardware, starts the Foundry Local server on port 39839, downloads the
model (once) and loads it. Click it then and the bubble shows the warm-up instead of a greeting,
with what it is doing and for how long (`Waking up, 23 s: Loading qwen2.5-7b`); there is
nothing to type into, and the Send and microphone buttons are off, until it is ready. When it is,
it wakes with a big stretch and a yawn and sets off; with the bubble open it says `I'm awake!`
and greets you instead. The first load converts the model for the GPU and can take a minute or
more; later loads take seconds.

| Do this | And the duck |
| --- | --- |
| Left-click | squeaks (one of four rubber duck squeaks), then says one of its greetings aloud, shown in the bubble too; clicking again closes it |
| Type in the orange box and press Enter, or Send | reads your screen, then answers in the bubble and out loud; Escape closes it. The box takes typing at any time; a line sent while the duck is still waking up is answered once it is ready |
| Click the microphone | starts a spoken conversation: talk, pause, and the duck answers out loud, then listens again. Click it again to stop; a sentence you are still saying is sent, not dropped |
| Drag | dangles from the cursor; let go still moving and it keeps the mouse's speed, so it can be thrown: it spins, bounces off the screen's edges, gives one of five quick squeaks when thrown hard and on every hard hit, and slides to a stop on the bottom |
| Right-click | opens the menu, with Quit |

The bubble has three tabs:

| Tab | Shows |
| --- | --- |
| Chat | the greeting or the latest answer, and the box to type in |
| Stats | the brain's state (`Ready, thinking on the GPU.`), the NPU and GPU with their TOPS, the model, the voice, and how much the last look at the screen read (or why it failed) |
| Settings | every text-to-speech voice the system offers. Test says a line in the selected one without changing anything; Apply makes it the duck's voice and saves it |

## Its name, memories, personality and skills

The duck keeps what it knows as plain text in its own folder, `user://duck/` (on Windows,
`%APPDATA%\Godotpp_userdata\Desktop Pet\duck\`). The **Duck** tab shows its name, whether it
wears its captain's hat, and what it remembers; it forgets the selected memory and opens the folder.

| File | Holds |
| --- | --- |
| `personality.md` | How it talks. Seeded on first run from `seed/personality.md`: bubbly and witty, in the spirit of Ernie from Sesame Street, whose best friend was a rubber duckie, with a few example lines, since a small model copies examples far better than it follows a description. Edit it freely; it is read afresh with every message and never overwritten |
| `name.txt` | Its name, once you give it one |
| `memories.md` | One remembered fact per `- ` line, all of them sent with every message |
| `told.md` | The facts it has already told. They are left out of the prompt so it tells a new one each time |
| `learned.md` | Facts it looked up on the web once it had told all of its own, one per `- ` line; edit or delete freely |
| `searched.md` | The topics it has searched for facts, so each search is about something new |
| `asked.md` | Its last 12 questions, sent with each message as ones not to ask again |
| `conversations/<when>.md` | Everything said, a file a conversation, named for when it began (`2026-10-08_064512.md`; the logs from before conversations were a file a day, `2026-10-07.md`), one `- 14:05:12 **You:** ...` or `**Duck:** ...` line each. The last three exchanges of the conversation under way go back into the prompt, so the duck picks up where you left off, even after a restart |
| `current.txt` | Which conversation is under way; without it, the newest |
| `skills/*.md` | Instructions with trigger words. When your message or the screen text mentions a trigger, that skill rides along with that one message, at most two at a time. Seeded with `godot-gdscript`, `python` and `javascript`, each a short list of the usual causes of bugs in that language. A seeded skill you have not edited is brought up to date when a newer one ships (the versions it replaces are kept in `seed/previous/`); one you have edited is left alone |

A skill file is a short header and the instructions:

```markdown
---
name: python
triggers: python, def, traceback, indexerror, keyerror
---
Usual causes in Python, worth checking against the code:
- A loop or index one past the end: `range(len(x) + 1)`...
```

It is a companion first. It chats about whatever you bring up and follows the conversation:
every prompt carries the last three exchanges, including what the duck itself said (its greeting
too, so answering "Hi! What's up?" makes sense to it), and older lines stay in the conversation
logs. It only turns into a rubber duck when you bring it code or a bug.

It is also meant to carry a conversation, not just answer. The personality's "How you carry a
conversation" section turns what conversation research has found into rules a small model can
follow: answer, add something of your own (a little story from its duck life, an opinion, or a
fact), then hand it back with one follow-up question about what you said; share as much as it
asks; pick up details and bring back what you said earlier; keep it fun; and go a little deeper
than small talk. The sources are listed in the comment at the top of `seed/personality.md`:
Huang, Yeomans, Brooks, Minson and Gino (2017) on follow-up questions and liking, Alison Wood
Brooks's TALK framework, and Kardas, Kumar and Epley (2021) on deeper conversation.

Small models state made-up facts with confidence, so the duck may only tell facts from the
personality's "Things you know for sure" list, each one checked: the 28,800 bath toys lost in the
Pacific in 1992, ducks sleeping with one eye open, the mallard's structural green, Ernie's
"Rubber Duckie" reaching number 16 in 1970, and more. Anything else becomes a story about itself.
Add facts there to give it more to talk about, but only true ones.

It does not say the same thing twice. A fact it has told goes into `told.md` and is left out of
the prompt, so the next one is new. Once every fact has been told, it looks more up: it searches
DuckDuckGo for the next of the Mind's `fact_topics` ("surprising facts about ducks", "history of the
rubber duck", "facts about ducklings" and so on), has the model copy out up to three facts the
results state, leaving out tips and adverts, and keeps them in `learned.md` beside its own. The
next answer notes it, for example `(Looked up 3 new facts to tell you)`. Until they arrive, and for
five minutes after a search that found nothing, it goes round its old facts again. Facts from the
web are only as good as the snippets they came from, so read `learned.md` now and then. The
questions it asks go into `asked.md`, and the latest 12 are sent with each message as ones not to
ask again. Small models copy their own last answer, and the personality's example answers, word for
word, and asking nicely in the prompt does not stop them, so the brain checks every sentence itself
as it arrives: one that mostly repeats one of its last three answers or an example, or asks a
question it asked lately, is dropped before it is shown or spoken, so a copy never reaches the
history where it would be copied again. If every sentence was a repeat it says something short and
fresh instead ("Hmm, my head's full of bubbles. Go on, I'm listening!"). While you are debugging
only a copied answer counts: "what did you expect to happen?" is fair to ask twice. A reply that
gets stuck on a word or a phrase ("gack-gack-gack...", `"4 * 2", "8", "4 * 2", "8"...`) is cut back
to its last whole sentence, and a line of its own instructions said back to you is dropped.

The answer streams. Foundry sends it a few words at a time, and each sentence appears in the bubble
and is spoken as soon as it is complete, while the model is still writing the next; Kokoro
synthesises each sentence as it arrives and plays them in turn, so the next is ready when the one
before ends. A hidden tag is held back from its `[` until it closes, so it is never shown or said.
The first words are heard about a second after Send rather than after the whole reply. The Stats
tab gives the last answer's timings, for example `Last answer: screen 0 ms, first word 388 ms,
first sentence 747 ms, whole 1.6 s (stop, debugging)`; "length" in place of "stop" means it ran out
of tokens. A long answer starts from its top and scrolls down as the duck says it, reaching the
bottom as it finishes.

Plain requests are carried out by the duck itself before the model sees them, so they always work:
"your name is Quackers", "call yourself ...", "remember that ...", "don't forget ...", "forget
...". Remarks such as "I can't remember why" or "do you remember" are left alone, and "my game"
is kept as "the user's game". The model can also keep things on its own, by ending a reply with a
hidden tag (`[remember: ...]`, `[forget: ...]`, `[name: ...]`, or `[skill: name | triggers |
steps]` when you teach it a way of doing something). Tags are stripped before the reply is shown
or spoken, a fact it already knows is not kept twice, and what changed is noted under the answer,
for example `(Name: Quackers; Remembered: The user's game is called Duck Hunt Deluxe)`.


## As a rubber duck

When you are working on code it changes manner. A message counts as debugging when it talks about a
bug ("crash", "error", "wrong", "stuck", "doesn't work", "fix", "code"...), holds code
(`get_tree().paused`, `==`, braces), or points at the screen ("what's this?") while an error is on
it; the message after one counts too, so explaining the bug keeps it there. Then:

- **A slim prompt.** In place of the whole personality (2400 tokens with its facts, examples and
  memories) the model gets `debug_role`, a few lines on being a cheerful rubber duck with no
  stories, facts or jokes while there is a bug to find, told to talk only about code and errors
  that are on screen or in what you said, and `sight_rules`: about 900 tokens. The first word comes twice as fast, and nothing tempts a duck
  fact into the middle of a bug.
- **The screen text with the error first.** The OCR is put in order before it is sent: error lines
  at the top under "Errors:", then the rest, without repeated lines or runs of file names and menu
  entries (`ScreenReader.focus`). The 6000-character cap then cuts noise rather than the error. If
  you switch windows to explain and the new screen shows no error, the last one goes along as
  "they are still working on this error from before".
- **Checks done in code** (`scripts/hints.gd`). Some slips a 7B model reads straight past, so the
  duck looks for them itself and sends what it finds as "Things to check", which the model is told
  to check against the code before it says so: a `$Node` path or a property whose name turns up
  nowhere else on screen while a name a letter or two away does (`$Sprit` beside `Sprite`, `prise`
  beside `price`); `fetch(...)` without `await`; Godot 3 syntax (`yield`, `onready var`, `export
  var`, `connect("signal", self, ...)`, `.instance()`); `range(len(x) + 1)`; something you said
  you set to true that nothing sets back to false; and the file and line a traceback or the
  debugger points at. Each fires only where it is right nearly every time, and a test runs them
  over real OCR of an editor with nothing wrong in it, where they must stay quiet.
- **The rubber duck's reminder** at the end of your message, where a small model heeds most: go
  through it step by step, name the line that looks wrong and why, then ask one short question that
  helps you check it; no lists or code blocks, since it is read aloud.
- **Settings for code:** `debug_max_tokens` 220 (explanations run 100 to 135 tokens and 160 cut
  some off), `debug_temperature` 0.3, and no repetition penalties: code repeats its marks and names
  all the time, and with them on the model dropped backticks and `+` and stopped at "The line that
  looks wrong is:".

The debugging prompt once had an example of a good turn, a made-up crash with its answer. Filmed
in use with nothing wrong on screen, the duck told that example back as the user's own bug, line
number and all. It went, the bench scored the same without it, and a ninth situation now checks
that a question with no code or error on screen gets a question back rather than an invented bug.

`tools/debug_bench.gd` measures it: eight situations, three rounds each, through the duck's own
pipeline in a scratch mind folder, scored by whether the answer names the actual cause, with the
timings of every turn. On the RTX 4080 Laptop with `qwen2.5-7b` (October 2026), the last commit
before this work and this one, two runs each with the same scoring:

| Situation | Before | After |
| --- | --- | --- |
| GDScript: `$Sprit` for a node called `Sprite`, null instance | 3, 1 | 3, 3 |
| Python: `total = s` where `total += s` was meant | 3, 3 | 3, 3 |
| JavaScript: `fetch` without `await`, `res.json is not a function` | 0, 0 | 3, 3 |
| Talked through, no screen: `get_tree().paused = true` never set back | 1, 0 | 3, 3 |
| GDScript: a signal sends an argument the method does not take | 3, 3 | 3, 3 |
| GDScript: Godot 3 syntax, `onready var` and `yield` | 0, 0 | 3, 2 |
| Python: `range(len(names) + 1)`, `IndexError` | 3, 2 | 3, 3 |
| JavaScript: `item.prise` for `price`, `NaN` | 1, 1 | 2, 2 |
| Total of 24 | 14, 10 | 23, 22 |
| First word heard | after the whole reply, 2.4 to 2.8 s, and its synthesis | first sentence written in 0.75 s |

`qwen2.5-coder-7b` scored 17 of 24 on the same bench, so the general model stays. A hidden
`[thinking: ...]` step before the answer scored 19: the model wrote "Thinking:" without the
bracket, and its thinking took the answer's place, so it was taken out again. The checks were
written with these situations in view, which is why the bench also has cases they do not touch
(the signal and the `IndexError` ones), and why the duck is told to check them rather than repeat
them. Run it with:

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s res://tools/debug_bench.gd
```

`DUCK_MODEL=<alias>` tries another model.

## Searching the web

Ask it to look something up and it searches DuckDuckGo first: "search for ...", "look up ...",
"google ...", "can you search the web for ...", "Ducky, look up ...". The only other search is the
one for new facts once it has told all it knows (see above), on a topic from its own list, never
on anything you said. The top five results, titles, addresses and snippets, go to the model
with your message as things it may tell you, and the first three are listed under the answer:

```
Searched DuckDuckGo:
Godot 4.5, making dreams accessible - Godot Engine: https://godotengine.org/releases/4.5/
```

It needs no key or account: `scripts/searcher.gd` posts the query to DuckDuckGo's plain results
page (`lite.duckduckgo.com`), as that page's own search box does, and reads the results out of the
HTML. After a few searches in quick succession Lite asks whether it is talking to a robot (HTTP 202);
the duck then tries `html.duckduckgo.com`, and if that asks too, it tells you to try again in a
minute. Both addresses are `search_urls` on the Searcher node.

## Reading the screen

The duck reads the screen it is on: it captures it, cuts it down to the window you were last
working in (not its own bubble, which has the focus while you type), blanks out its own window and
bubble so it does not read itself, and runs the picture through the OCR built into Windows 10 and
later (`Windows.Media.Ocr`; nothing to install). The OCR runs in one PowerShell process started with
the duck and kept running, which also notes the window in front four times a second, so neither
PowerShell nor the OCR engine starts up for each read: a read takes about 0.2 s, down from 0.4. It
reads as you start typing (the first letter) or as the mic hears you, and Send uses that reading if
it is under `read_ahead_ms` (3 s) old, so Send does not wait on OCR at all. The text, error lines
first and noise dropped (see As a rubber duck), up to `max_characters`, goes to the model with your
message, and only your message is kept in the conversation, so old screens do not pile up.

The model is told plainly that this text is all it can see, and to use it only when your message
is about the screen, your code or an error; otherwise it ignores it and just talks. It cannot see
pictures, colours or layout, and must not describe anything the text does not contain. OCR reads a multi-column window
(an editor with a file tree and a side panel) as interleaved lines, so a maximised editor reads
best.

Screen reading is Windows only for now. On other systems the duck is told it could not read the
screen and says so.

The captures and the text are written to `user://screen_0.png` to `screen_2.png` (in turn, since
the OCR process can keep the last one open a moment) and `user://screen.txt`, overwritten each time
and never sent anywhere.

## Talking to it

While the microphone is on it shows a red dot, and a red status pill takes the text box's place,
in the same row so the answer keeps its room, saying what it is doing (`Listening...`, `Hearing
you...`, `Writing it down...`, `Thinking...`, `Talking...`), with a level meter that moves as it
hears you. The box comes back when the microphone is turned off.

The microphone button turns on a conversation. The duck listens; when you talk it records, and
when you have been quiet for `pause_seconds` (1.2 s) it writes down what you said and sends it,
with a look at the screen, exactly as if you had typed it. What it heard appears in the bubble as
`You: ...` above the answer. While it thinks and talks it stops listening, so it does not hear
itself, and it starts listening again as soon as it has finished speaking, or as soon as the
answer is complete if the voice got there first. The pause was 0.6 s, which sent half a sentence
whenever you stopped to think in the middle of one. Click the microphone
again, or close the bubble, to stop.

The microphone plays into a muted `Mic` bus (`default_bus_layout.tres`) whose `AudioEffectCapture`
hands the samples to `scripts/listener.gd`. Speech is anything louder than `speech_threshold_db`
(-40 dB); bursts shorter than 0.3 s are dropped, and 0.3 s before the level rose is kept so the
first syllable is not cut off. Each sentence is written to `user://utterance.wav` at 16 kHz and
transcribed by `foundry transcribe`, on the speech model chosen for the machine (see below; Parakeet, 692 MB,
on an English system, downloaded the first time the mic is used), in about a third of a second on
the GPU.

The microphone is chosen on the Settings tab and remembered in `user://settings.cfg`; `Default`
follows the system's own default. If the duck never hears you, pick another microphone there: a
webcam microphone can be the system default and still send only silence (an OBSBOT Tiny SE did
exactly that here, while the laptop's own microphone array worked).

It answers whatever it hears while the microphone is on, including talk that was not meant for it,
so turn the microphone off when you are talking to someone else.

## On your phone

The Android app is a remote control for the duck on your PC: the duck on the top half of the
phone, the chat on the bottom half. It is not a second duck. The brain, the duck's memory and its
screen reading all stay on the PC, so from the phone you talk to the same duck, with the same
memories and the same conversation, and it still reads the PC's screen: with the phone in hand at
the desk, "why does this crash?" reads your editor.

- **Pairing.** The PC's Settings tab shows `Phone: code 462570  192.168.4.161:39842`. The app lists
  the PCs it hears on the Wi-Fi (the PC broadcasts a beacon once a second); pick yours, or type its
  address, enter the six-digit code, and Connect, or Done on the keyboard. The app remembers both
  and reconnects by itself. The code is made once and kept in `user://settings.cfg` under
  `[remote]`; it keeps anyone else on the network from talking to the duck, and through it reading
  your screen.
- **Typing** a line runs the same turn as typing it on the PC: screen read, search, memory and all.
  The answer streams onto the phone sentence by sentence, as it does on the PC.
- **Voice out.** With a Kokoro voice chosen on the PC, each sentence is spoken by Kokoro on the PC
  and the audio sent to the phone, which plays them in order; the PC stays quiet on the phone's
  turns (`speak_here_too` on the Remote node speaks them on both). With a system voice chosen, the
  phone reads the text with its own voice.
- **Voice in.** The mic button listens on the phone with the same pause rule as on the PC, and
  sends each sentence to the PC as a WAV to be written down by Parakeet there; the phone has no
  speech model of its own. Tapping it off mid-sentence sends what you have said so far.
- **The chat** looks like a messaging app: your messages in blue bubbles on the right, the
  duck's in grey on the left, each as wide as its text up to three quarters of the screen. The
  duck's bubble grows as its sentences arrive.
- **New** starts a new conversation: the duck keeps its memories and personality but no longer
  has the last one in mind. **Past** lists the conversations, newest first, each by when it began
  and the first thing you said; tap one to take it up again where it left off. They are the files
  in `user://duck/conversations/` on the PC, so the PC duck switches with the phone.
- **Mute** silences the duck on the phone and tells the PC, which then makes no audio for it at
  all, so a muted answer is done as soon as its text is; the choice is remembered.
- **The bubble bath.** The duck floats in milky bath water (the pond water from weather-fx, made
  calm), bobbing gently, with suds piled round it where it sits and clumps of foam floating about
  (`scripts/suds.gd`: hundreds of small foam bubbles in one MultiMesh, placed once from a seed and
  quivering in `assets/water/suds.gdshader`), and a sky meeting the water at the horizon. The bath
  is calm until it is disturbed: tapping the duck, or jolting the phone (its accelerometer;
  `shake_threshold`, 2.5 m/s² beyond the steady pull of gravity), sends up a burst of
  rainbow-rimmed bubbles (the bubble shader from the Godot 4.5 sandbox) and raises the swell and
  the duck's rocking, which settle again by half every `settle_half_life` (0.8 s). The water's
  ripple normal map is made by Godot from noise. Its contact foam, the white band where something
  sits in the water, is weather-fx's own, but measured from the duck's footprint on the water
  (`contact_footprint`) rather than from the depth texture: on Android's Compatibility renderer,
  reading the depth texture drew the water over the duck and the suds. See `CREDITS.md`.
- **Pick it up, drop it, throw it.** Press on the duck and move your finger and it comes up out of
  the bath, dangling; let go to drop it, or let go mid-swing to throw it, and it bounces off the
  sides of the view and splashes down, as hard as it came, with bubbles and a quick squeak for a belly
  flop, then drifts back into its suds. A tap still squeezes it, and so does pushing it down into
  the water.
- **The captain's hat** is optional: the Captain's hat box on the PC's Duck tab, under the name, or
  the Hat button on the phone (or a double tap on its duck) puts it on or takes it off, on both ducks
  at once; the choice is kept in
  `user://settings.cfg`. It is `scenes/hat.tscn`, the model with its four PBR textures as one
  material, sitting on the duck's head and turning with it.
- **The duck** sleeps until the PC's brain is awake, thinks while it waits, talks while it speaks,
  and squeezes and squeaks on every tap.
- **Away from home**, put the PC and the phone on [Tailscale](https://tailscale.com) and type the
  PC's Tailscale name into the address field; the beacon only reaches the local network.

Measured on the PC and an Android emulator on it (October 2026): the PC's echo of your line in a few
milliseconds, the first sentence on the phone 1.3 s after sending, and the first sentence's audio
about 1.5 s after its text, as Kokoro renders it. A spoken question from the phone was written down
and answered on the PC in 3.2 s, most of it the first transcription's check that the speech model
is downloaded.

### How it talks to the PC

`scripts/remote.gd`, the Remote node in `pet.tscn`, is a WebSocket server on port 39842 (a
`TCPServer` with `WebSocketPeer.accept_stream`, no add-on) and broadcasts `duck 39842 <name>` by
UDP to port 39843 once a second. Text frames are JSON; binary frames are audio, a kind byte, the
sentence's index as a little-endian uint32, then a WAV.

| From | Frame | |
| --- | --- | --- |
| phone | `{"hello": code, "name": phone}` | first; a wrong code gets `{"bye": "wrong code"}` and the socket closes |
| PC | `{"welcome": duck name, "ready", "status", "speaks", "recent"}` | `recent` is the last six messages, so the phone shows where the conversation was |
| phone | `{"say": line}`, or audio kind 1 | typed, or a spoken sentence for the PC to transcribe |
| PC | `{"you": line}` | the turn began; after a recording, what was heard (`""` with `"error"` when nothing was) |
| PC | `{"sentence": text, "index": n}`, then audio kind 2 for `n` | each sentence as it is written, then its Kokoro audio |
| PC | `{"replied": text, "notes": ...}` | the whole answer and what the duck remembered |
| PC | `{"status": text, "ready": bool}`, `{"busy": true}` | the brain waking; a turn already under way |
| phone | `{"ping": t}` every 5 s | answered `{"pong": t}`; three missed and the phone reconnects |

The phone app is `scenes/remote.tscn` with `scripts/remote_app.gd`, in this same project. Android
opens it instead of the pet through feature-tag overrides in `project.godot`
(`run/main_scene.android`, and `.android` versions of the window settings, so the phone gets an
ordinary portrait window rather than the PC's 144 px transparent one).

### Building it

Godot exports the APK; it needs the Android SDK and a JDK, set in the editor's Export > Android
settings, and the export templates for this exact Godot build (4.8-dev6). On this PC: Temurin JDK
21, the SDK in `%LOCALAPPDATA%\Android\Sdk` with `build-tools;36.1.0` and `platforms;android-36`
(what Godot 4.8 asks for; install them with the SDK's `cmdline-tools\latest\bin\sdkmanager.bat`,
passing the package name in a `--package_file`, since a `.bat` splits it at the semicolon), and the
templates from the `4.8-dev6` release of godot-builds. Then:

```powershell
& 'C:\Godot\godot.exe' --headless --path . --export-debug "Android" build/duck.apk
adb install -r build/duck.apk
```

The `Android` preset in `export_presets.cfg` builds for arm64 phones and x86_64 emulators, asks for
the internet, Wi-Fi state and microphone permissions, and leaves the tests, tools and seed out.
`tools/make_icon.gd` renders the duck into the app's icon. To try it without a phone, run an
Android Studio emulator and `tools/remote_host.gd` on the PC: the emulator reaches the PC at
`10.0.2.2` (its own network does not carry the beacon), and the host prints the code. To check the
PC side without any phone, `tools/remote_client.gd` pairs, sends a line (or a recording, with
`DUCK_WAV`) and prints every frame with its timing.

## How it picks the NPU, GPU or CPU

Foundry Local chooses. Asked for a model alias, it downloads the variant built for the best
hardware it finds: a QNN build for a Snapdragon X NPU, Vitis AI for an AMD Ryzen AI NPU, OpenVINO
for an Intel NPU, TensorRT-RTX or CUDA for an NVIDIA RTX GPU, WebGPU for other GPUs and Apple
silicon, and the CPU otherwise. The variant's name ends in its device
(`qwen2.5-7b-instruct-trtrtx-gpu`), which is how the duck knows where it is thinking.

## On a Mac

Foundry Local runs models on Apple silicon through WebGPU, and there it reads the whole prompt
again for every answer at about 110 tokens a second. The duck's prompt is about 2,000 tokens, its
personality most of it, so on an M4 Pro with 24 GB each answer started 22 s after the question,
even though writing it then took only seven.

So on macOS the chat model runs on llama.cpp's `llama-server` instead, on Metal, and Foundry keeps
only the speech model. The brain still chooses the model from Foundry's catalog, as below, then
starts `llama-server` on port 39841 with the GGUF build mapped to that alias in `llama_models` on
the Brain (`qwen2.5-14b` is `bartowski/Qwen2.5-14B-Instruct-GGUF:Q4_K_M`). The first run downloads
it from Hugging Face into `~/.cache/huggingface` while the bubble says `Fetching qwen2.5-14b`; its
output goes to `user://llama-server.log`. Closing the duck stops the server, unless it was run
from the editor (as with Foundry, below).

Measured on that M4 Pro with `qwen2.5-14b`:

| | Foundry (WebGPU) | llama.cpp (Metal) |
| --- | --- | --- |
| Reading a 2,000-token prompt | 22 s | 9 s |
| The same prompt again | 22 s | none: it keeps the prompt it read last |
| Writing | 13 tokens a second | 24 tokens a second |

A Mac also starts lower down the list. Its unified memory fits `qwen2.5-14b` (a 24 GB Mac has
16.8 GB to spend), but memory is not what makes it slow: reading the prompt is arithmetic, which
an Apple GPU has less of than an NVIDIA card with tensor cores. So `mac_chat` in
`resources/model_preferences.tres` starts at `qwen2.5-7b`, the model the RTX 4080 Laptop PC runs,
at half the 14B's work a token. Set `mac_chat` empty to give a Mac the `chat` list.

`llama-server` reuses whatever part of the prompt is unchanged from the last request, so how quick
an answer is depends on how much of the prompt stays the same between turns. It has three slots,
chat, debugging and fact finding, so each keeps its own prompt. A chat model with no GGUF in
`llama_models`, or a Mac without llama.cpp installed, stays on Foundry, and Stats says so.

## Which models it runs

Nothing is hard-coded to one machine. At startup the brain reads Foundry Local's catalog
(`foundry model list -o json`), which lists every model with its size and the build Foundry would
run here, and picks from the ranked lists in `resources/model_preferences.tres`:

| List | Best first |
| --- | --- |
| `chat` | `qwen2.5-14b`, `qwen2.5-7b`, `phi-4-mini`, `qwen2.5-1.5b`, `qwen2.5-0.5b`, then `qwen2.5-coder-*` |
| `mac_chat` | the same without `qwen2.5-14b`, used in place of `chat` on macOS (see [On a Mac](#on-a-mac)) |
| `speech_english` | `parakeet-tdt-*` |
| `speech_any_language` | `openai-whisper-small-generic-cpu`, then `base`, then `tiny` |

- **It fits the machine.** Each model must fit in `memory_share` (70%) of the memory on the device
  its build runs on, counting 1.2 times its download size for working memory: the card's own
  memory for an NVIDIA GPU or another Windows GPU with at least 2 GB, and system memory for an
  NPU, the CPU, an integrated GPU or a Mac. Speech is picked first and chat gets what is left. On
  a 12 GB RTX 4080 Laptop that is `qwen2.5-7b` and Parakeet; a 24 GB card gets `qwen2.5-14b`, a
  4 GB card `qwen2.5-1.5b`.
- **Lists are easy to change.** An entry with a `*` is a family, and the largest member that fits
  wins, so a new size is taken up as soon as Foundry publishes it; an entry without one is that
  model alone. The general Qwen 2.5 sizes are named one by one because `qwen2.5-*` would match the
  coder builds too. Foundry also updates a model's build under the same name. To prefer something
  else, reorder or add to the lists in the inspector; no code changes.
- **It speaks your language.** On an English system it listens with Parakeet; on any other it uses
  Whisper, on the CPU, because Foundry's CUDA Whisper builds return garbled text (CLI 0.10.3).
- **Reasoning models are left out** (`deepseek-r1-*`, `phi-4-reasoning`): they think aloud
  before answering, which reads badly when spoken.

Loading a model takes 40 to 50 s, so when the duck was started from the Godot editor it leaves the
chat model loaded as it closes, and the next run is up in a second or two
(`keep_loaded_from_editor` on the Brain; it knows by the editor's debugger being attached). Started
any other way, it unloads the model and frees the memory as it closes. `foundry model unload
qwen2.5-7b` frees it by hand.

Stats shows what was chosen and the budget, for example `Chat: qwen2.5-7b, 5.5 GB on the GPU.
Speech: parakeet-tdt-0.6b-v2, 0.7 GB on the GPU. Budget: 8.4 GB on the GPU, 21.8 GB of system
memory.` To force a chat model, set `model_alias` on the Brain node.

The first chat model was `qwen2.5-1.5b`, which could not cope with screen text: asked to describe
the screen it pasted the OCR back, and asked which file was open it made one up. `qwen2.5-coder-7b`
read the screen well but could not chat: given nine turns of small talk it answered five of them
with the same reply word for word, a copy of one of the personality's examples. `qwen2.5-7b`, the
general model of the same size, told a different fact or story each turn, asked something new each
time and used search results. `mistral-nemo-12b-instruct` fits too, but Foundry only builds it for
CUDA, and on this RTX 4080 that build printed "the the the..." like the CUDA Whisper builds, so it is
not on the list.

## TOPS

No operating system reports TOPS, so `scripts/hardware.gd` works them out:

- **NPU:** the vendor's rated INT8 peak, looked up from the processor or NPU device name (Snapdragon
  X 45, Ryzen AI 300 50, Core Ultra 200V 48, Apple M4 38, and so on). On Windows the NPU is found in
  the Plug and Play device list; every Apple silicon Mac has one.
- **GPU:** for NVIDIA RTX 40 series, SM count times the maximum SM clock from `nvidia-smi` times
  2,048 INT8 operations per SM per clock, dense. NVIDIA's advertised "AI TOPS" assume sparsity and
  are twice that. The maximum clock is higher than the rated boost, so this is a ceiling.

`tools/npu_tops.py` prints the same figures from the command line, without Godot:

```powershell
python tools/npu_tops.py
```

## Voices

The duck speaks through Godot's own text-to-speech, which uses the operating system's voices: SAPI
and OneCore voices on Windows (David, Zira and Mark on a stock US install), the voices in System
Settings > Accessibility > Spoken Content on macOS, and speech-dispatcher on Linux. More voices
installed through the system's language settings appear in the list the next time it starts.

Until a voice is applied, the duck uses the first voice in the system's language. The applied
voice is saved in `user://settings.cfg` (on Windows, `%APPDATA%\Godot\app_userdata\Desktop Pet\`),
and a saved voice that has since been uninstalled falls back to the default. A system with no
voices leaves the duck silent and the Settings tab says so; the text still appears.

### Natural voices (Kokoro)

Windows keeps its natural Narrator voices (Aria, Jenny and the rest) for Narrator: no other app can
use them. Instead the duck offers **Kokoro**, an open 82M-parameter voice model (Apache 2.0) that
sounds natural and runs entirely on your machine through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).

On the Settings tab its 28 English voices (20 American, 8 British) sit greyed out under the
system's, below a `Download natural voices (352 MB)` entry. Choosing that entry downloads
sherpa-onnx's tools and the Kokoro v1.0 model into `user://kokoro` and unpacks them; the entry
counts up the megabytes while it does, with Test and Apply greyed. When it is done the voices
turn white and work like any other: Test says a line, Apply makes it the duck's voice.

| | First line | Later lines |
| --- | --- | --- |
| sherpa-onnx's own tool, a fresh process each line | 1.4 to 2.2 s | 1.4 to 2.2 s |
| `kokoro-server`, the model kept loaded | 0.6 s, as it loads in the background at start | 0.3 to 1.6 s |

The difference is the model: sherpa-onnx's command-line tool loads all 310 MB of it for every line
and exits. `tools/kokoro_server/kokoro_server.c` is a small program on sherpa-onnx's C API that
loads it once and then answers line after line; the duck starts it when a Kokoro voice is
chosen, loads the model in the background so the first reply is quick too, and it exits with the
duck. It is built with `tools/kokoro_server/build.bat` (Visual Studio 2022) into
`bin/windows/kokoro-server.exe`, which the duck copies beside sherpa-onnx's library when it
installs the voices. There is no macOS build yet, so on a Mac the duck falls back to the
command-line tool and its slower replies.

The full-precision model is used although an int8 one is a third the size: on a Ryzen 9 7845HX
the int8 model took 4.6 s to make 4.8 s of speech, the full one 1.1 s.

The `seed/` and `bin/` files are not Godot resources, so an export must list `seed/*` and `bin/*`
in its preset's non-resource files.

## The duck

`scenes/duck.tscn` is the 3D duck: the model under three nodes (`Pivot` rolls it onto the edge it
is on, `Body` carries the animation, `Yaw` turns it left or right and 30 degrees toward the camera),
an orthographic camera, a sun and ambient light. `scenes/pet.tscn` shows it through a transparent
`SubViewport`. The model faces +X, so from the camera it is seen side on, and its base sits on the
bottom of the view so rolling it 90 degrees stands it on a wall.

Its animations are posed in `scripts/duck.gd` rather than keyed, and every one uses squash and
stretch, the classic animation principle that makes a thing read as soft and alive. The duck keeps
its volume whatever its shape (`Duck.squash`: what it loses in height it gains in width and depth),
and it scales from its base, so a squash keeps it sitting on its edge rather than shrinking.
Impacts settle with a damped wobble (`Duck.settle`) that overshoots past round before coming to
rest.

| Animation | Squash and stretch |
| --- | --- |
| `squeeze` | Clicking it squeezes it like a real rubber duck, with the squeak: flattened hard, then springing back taller than round |
| `cheer` | A hop: a crouch to gather itself, a stretched take-off, a spin in the air, a squash on landing and a wobble before the next |
| `sleep`, `wake` | Asleep while its brain loads: settled low, breathing slowly and deeply, head nodding, Zs rising; then a big stretch and yawn that settles with a wobble |
| `walk`, `climb` | Squashed as each foot lands, stretched at the top of each step, waddling side to side |
| `talk` | A stretch on every syllable, a little squash between them |
| `fall`, `land` | Stretched along the fall; flattened by the impact, then wobbling back |
| `hang` | Dragged or upside down along the top: pulled long by its own weight, swinging |
| `idle`, `think` | Breathing; a slow tilt with its head down in thought |

While the bubble is open the duck turns round to face you, its beak out of the screen, and perks up
as it does: a quick attentive stretch that settles (`Duck.perk`). When the bubble closes it turns
back the way it was going. Every turn eases round (`turn_speed`) instead of snapping, including
turning about at a corner, which takes the short way, past you.

`tools/model_shot.gd` renders a model from four
sides to see which way it faces before it goes into a scene:

```powershell
& 'C:\Godot\godot.exe' --path . -s tools/model_shot.gd -- res://assets/duck/rubber_duck.fbx res://screenshots/model_shot.png
```

## Changing it

The settings are exported on the nodes of `scenes/pet.tscn` and `scenes/duck.tscn`:

| Node | Setting | Default |
| --- | --- | --- |
| `Pet` | `speed` | 60 pixels a second |
| `Pet` | `gravity`, `bounciness`, `floor_friction`, `max_throw_speed`, `hard_bounce` | 2600 px/s², 0.55, 4, 4500 px/s, 650 px/s: how it flies when dropped or thrown |
| `Pet` | `idle_chance`, `climb_chance` | 0.3 at a bottom corner, 0.5 at any corner |
| `Pet` | `greetings` | ten canned greetings, one picked at random on each click |
| `Pet` | `test_line` | what the Test button says |
| `Duck` | `turn_to_camera`, `turn_speed` | 30 degrees three-quarters on while walking; 10, how quickly it turns |
| `Brain` | `preferences` | `resources/model_preferences.tres`: the ranked model lists and `memory_share` |
| `Brain` | `model_alias` | empty, so the model is chosen for the machine; set it to force one |
| `Brain` | `port` | 39839 |
| `Brain` | `llama_models`, `llama_port`, `llama_context` | GGUF builds for the five chat models, 39841, 16384 tokens: the Mac's llama.cpp chat server |
| `Brain` | `role`, `sight_rules` | its job as a rubber duck, and what it is told about seeing; its tone is `personality.md` |
| `Mind` | `max_memories`, `max_skills` | 40 memories in the prompt, 2 skills a message |
| `Brain` | `max_tokens`, `max_history` | 160; 6 messages, the last three exchanges, sent with each prompt |
| `Brain` | `debug_role`, `debug_max_tokens`, `debug_temperature` | while debugging: the slim prompt, 220 tokens, 0.3 |
| `Brain` | `keep_loaded_from_editor` | on: run from the editor, the model stays loaded on closing |
| `Pet` | `read_ahead_ms` | 3000: how old a screen read while typing may be and still be used at Send |
| `Voice` | `volume`, `rate` | 70, 1.0 |
| `ScreenReader` | `max_characters` | 6000 characters of screen text a message |
| `Searcher`, `FactSearcher` | `max_results`, `max_snippet`, `search_urls` | 5 results, 300 characters each, Lite then HTML |
| `Mind` | `fact_topics`, `fact_search_wait` | What it searches for new facts, in turn; 300 s before trying again after a search found none |
| `Listener` | `language` | empty, so the system language |
| `Listener` | `speech_threshold_db`, `pause_seconds` | -40 dB, 1.2 s |
| `Remote` | `enabled`, `port`, `beacon_port`, `speak_here_too` | on, 39842, 39843, off: the phone speaks the phone's turns |
| `Squeak` | `stream` | the four squeaks, picked at random |
| `FastSqueak` | `stream` | the five quick squeaks for a throw and a hard bounce, picked at random |

## Layout

```
scenes/pet.tscn             the pet window: the duck's viewport, Brain, Voice, ScreenReader, and the Bubble with its tabs
scenes/duck.tscn            the 3D duck, its camera and lights, and its optional hat
scenes/hat.tscn             the captain's hat with its material
assets/hat/                 the captain's hat model and textures
scripts/pet.gd              edge walking, dragging, the bubble, greetings, stats and voice settings
scripts/duck.gd             the duck's poses and animations
scripts/brain.gd            starts Foundry Local, picks the models, builds each prompt and checks each sentence
scripts/chat_stream.gd      one streamed reply from Foundry's OpenAI-compatible API, a few words at a time
scripts/hints.gd            the checks done in code while debugging
scripts/mind.gd             the duck's name, personality, memories and skills, in user://duck
seed/                       the first personality and skills, copied to user://duck on first run; previous/ holds the skill versions they replace
scripts/model_preferences.gd  the ranked model lists and the memory budget
resources/model_preferences.tres  the lists themselves, edited in the inspector
scripts/screen_reader.gd    captures the screen and reads it with the system OCR
scripts/searcher.gd         looks things up on DuckDuckGo when asked to
scripts/remote.gd           lets the phone app talk to the duck: the WebSocket server and the beacon
scenes/remote.tscn          the phone app: the duck on top, the chat below
scripts/remote_app.gd       the phone app's pairing, chat, voice and the duck's moods
scripts/suds.gd             the bubble bath's foam, round the duck and floating about
assets/water/               the phone's bath: the water, the bubbles and the suds shaders
export_presets.cfg          the Android export
scripts/voice.gd            speaks through the system's TTS voices or Kokoro's, and saves the chosen one
scripts/kokoro.gd           downloads and runs the natural Kokoro voices
tools/kokoro_server/        the program that keeps Kokoro's model loaded, and its build script
bin/windows/                kokoro-server.exe, built
scripts/listener.gd         records the mic, ends a sentence at a pause and transcribes it
default_bus_layout.tres     the muted Mic bus and its capture effect
scripts/hardware.gd         finds the NPU and GPU and their TOPS
assets/duck/                the rubber duck model
assets/audio/               the squeaks
assets/icons/               the microphone icon
tools/npu_tops.py           the TOPS report as a standalone script
tools/model_shot.gd         renders a model from four sides
tools/inspect_model.gd      prints a model's nodes, size, materials and animations
tools/debug_bench.gd        scores the duck at debugging and times it, against the real model
tools/remote_host.gd        a headless duck for a phone or an emulator to talk to
tools/remote_client.gd      a phone on the command line, to check the PC side
tools/make_icon.gd          renders the duck into the app's icon
tests/unit/                 GUT tests
tests/fixtures/             Foundry's real catalog output, DuckDuckGo result pages, and OCR of an editor
```

## Testing

The tests run on [GUT](https://github.com/bitwes/Gut) 9.7.1, which is not committed. Clone it once
into `addons/gut/`:

```bash
git clone --depth 1 --branch v9.7.1 https://github.com/bitwes/Gut.git /tmp/gut && cp -R /tmp/gut/addons/gut addons/gut
```

```powershell
& 'C:\Godot\godot.exe' --headless --path . --import
& 'C:\Godot\godot.exe' --headless --audio-driver Dummy --path . -s addons/gut/gut_cmdln.gd -gexit
```

They cover the edge walking, corner turns, rolls and facing; the duck's poses and scene; the
scene's wiring, tabs and input box; the greetings and the Stats text; blanking the pet's own
windows out of the capture and tidying the OCR text; the TOPS lookups and arithmetic; the brain's
handling of Foundry Local's responses and of the screen text; the streamed reply's events, the
sentence checks and the slim debugging prompt; the code checks and the error-first screen text;
Kokoro's sentence queue; the phone link's frames, pairing and beacon, a real WebSocket over
loopback, and the phone app's scene and Android settings; and choosing, saving and falling back
between voices. They do not need Foundry Local installed, and headless Godot has no text-to-speech
or screen, so they also show those missing stays quiet rather than failing.

Things found the hard way:

- Foundry Local's REST reference documents `/openai/loadedmodels`, but CLI 0.10.3 answers it with
  404, so the brain reads the loaded model from the standard `/v1/models`.
- `StorageFile.GetFileFromPathAsync` fails on Godot's forward-slash paths with only "One or more
  errors occurred", and Godot decodes a child process's stdout in the console code page, so the
  OCR script normalises its path and writes its text to a UTF-8 file.

- Foundry Local's speech models misbehave in CLI 0.10.3. The REST server answers
  `/v1/audio/transcriptions` with 404, so the listener runs `foundry transcribe -o json`. Its Whisper
  builds for CUDA (tiny to large-v3-turbo) return garbled text, a different garble each run, with
  words doubled or shuffled; the CPU Whisper and the Parakeet models transcribe correctly every
  time.
- An exported Node property (`@export var mind: Mind`) set in a `.tscn` is only resolved when the
  node lists it in `node_paths=PackedStringArray("mind")`. Without it the property is quietly
  null, and the duck's personality and memories never reached the model; a test now checks the
  link.
- `foundry model load` (CLI 0.10.3) can keep running long after the model has loaded, which left the
  duck asleep for good. The brain starts the load, then watches `foundry model list --loaded -o
  json` every two seconds, ends the load command once the model is listed, and gives up with a
  message after ten minutes.
- A label without clipping makes a container as wide as its text: a long warm-up line pushed the
  bubble's contents out past both sides of its fixed 340 px window. The status line clips with an
  ellipsis, with the seconds first so the count stays in view.
- Listening must not wait on anything but the voice. It used to resume only if the duck was still
  in its `talk` animation when the speech ended, so a changed animation left it deaf; it now
  resumes when the voice finishes, with a timer as a backstop in case the system never says so.
- On macOS the duck never woke: `foundry server start` leaves the daemon running, and the daemon
  inherits the command's stdout. `OS.execute` reads a child's stdout until it closes, so it waited
  for good. There the server is started through `/bin/sh -c "exec ... </dev/null >/dev/null 2>&1"`;
  Godot passes nothing after an `sh -c` script, so the CLI's path is quoted into the script itself.
  Windows starts it directly as before.
- The repetition penalties that keep small talk fresh ruin code: the model avoids tokens it has
  used, so after the first backtick or `+` it writes spaces instead, and it stopped at "The line
  that looks wrong is:" when the next thing was code. They are off while debugging.
- A click handled through `Area2D.input_event` is lost when the press and the release fall in the
  same physics frame: picking sees the press a frame late, after the release has gone by, and the
  duck is left stuck to the cursor. The window's mouse passthrough already limits input to the
  duck, so the pet takes the mouse in `_unhandled_input` instead.

## Credits

See [CREDITS.md](CREDITS.md).
