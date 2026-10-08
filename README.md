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
| Click the microphone | starts a spoken conversation: talk, pause, and the duck answers out loud, then listens again. Click it again to stop |
| Drag | dangles from the cursor; let go still moving and it keeps the mouse's speed, so it can be thrown: it spins, bounces off the screen's edges, squeaks on a hard hit and slides to a stop on the bottom |
| Right-click | opens the menu, with Quit |

The bubble has three tabs:

| Tab | Shows |
| --- | --- |
| Chat | the greeting or the latest answer, and the box to type in |
| Stats | the brain's state (`Ready, thinking on the GPU.`), the NPU and GPU with their TOPS, the model, the voice, and how much the last look at the screen read (or why it failed) |
| Settings | every text-to-speech voice the system offers. Test says a line in the selected one without changing anything; Apply makes it the duck's voice and saves it |

## Its name, memories, personality and skills

The duck keeps what it knows as plain text in its own folder, `user://duck/` (on Windows,
`%APPDATA%\Godotpp_userdata\Desktop Pet\duck\`). The **Duck** tab shows its name and what it
remembers, forgets the selected memory, and opens the folder.

| File | Holds |
| --- | --- |
| `personality.md` | How it talks. Seeded on first run from `seed/personality.md`: bubbly and witty, in the spirit of Ernie from Sesame Street, whose best friend was a rubber duckie, with a few example lines, since a small model copies examples far better than it follows a description. Edit it freely; it is read afresh with every message and never overwritten |
| `name.txt` | Its name, once you give it one |
| `memories.md` | One remembered fact per `- ` line, all of them sent with every message |
| `told.md` | The facts it has already told. They are left out of the prompt so it tells a new one each time |
| `learned.md` | Facts it looked up on the web once it had told all of its own, one per `- ` line; edit or delete freely |
| `searched.md` | The topics it has searched for facts, so each search is about something new |
| `asked.md` | Its last 12 questions, sent with each message as ones not to ask again |
| `conversations/<date>.md` | Everything said, a file a day, one `- 14:05:12 **You:** ...` or `**Duck:** ...` line each. The last three exchanges go back into the prompt when the duck starts again, so it picks up where you left off |
| `skills/*.md` | Instructions with trigger words. When your message or the screen text mentions a trigger, that skill rides along with that one message, at most two at a time. Seeded with `rubber-duck-method`, `reading-errors` and `godot-gdscript` |

A skill file is a short header and the instructions:

```markdown
---
name: reading-errors
triggers: error, exception, traceback, crash
---
Find the first error line and the file and line it points at...
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
word, and asking nicely in the prompt does not stop them, so the brain checks each reply itself: one
that mostly repeats any of its last three answers or an example, or asks a question it asked
lately, is sent back once with what it repeated and a request for something new. If the second try
repeats too, the repeated sentences are cut out, so a copy never reaches the history where it
would be copied again. A reply that gets stuck on one word ("gack-gack-gack...") is cut back to its
last whole sentence, and a line of its own instructions said back to you is dropped.

A long answer starts from its top and scrolls down as the duck says it, reaching the bottom as it
finishes.

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
it; the message after one counts too, so explaining the bug keeps it there. Then the reminder at the
end of your message asks for a rubber duck instead of a companion: no duck facts, stories or jokes,
go through it step by step, name the line that looks wrong and why, and ask one short question that
helps you check it, without lists or code blocks since it is read aloud. The repetition penalties
are off for it too: code repeats its marks and names all the time, and with them on the model
dropped backticks and `+` and stopped at "The line that looks wrong is:". The seeded skills
(`rubber-duck-method`, `reading-errors`, `godot-gdscript`) still ride along when their words come up.

How well it does, measured with four situations run three times each through the duck's own
pipeline on `qwen2.5-7b` and `qwen2.5-coder-7b` (October 2026):

| Situation | qwen2.5-7b | qwen2.5-coder-7b |
| --- | --- | --- |
| Python: `total = s` where `total += s` was meant | 3 of 3 | 3 of 3 |
| Talked through, no screen: `get_tree().paused = true` never set back | 3 of 3 point at it | 3 of 3 point at it |
| GDScript: `$Sprit` for a node called `Sprite`, null instance | 1 of 3 spot the typo; all say `sprite` is null | 0 of 3 spot the typo; all say it is null |
| JavaScript: `fetch` without `await`, `res.json is not a function` | 0 of 3 | 0 of 3 |

So it reads an error down to its line and catches plain logic slips, and when you describe what your
code does it finds the step that matters, which is the rubber duck's real job. It misses subtler
things, a typo in a node path or a missing `await`, and sometimes explains the error back to you
rather than finding its cause. That is a 7B model on a laptop GPU; a card with 24 GB gets
`qwen2.5-14b` by itself (see Which models it runs). Before the debugging reminder and with the
penalties on, the same tests went about 2 in 4, with duck facts in the middle of a bug.

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

Each time you send a message the duck captures the screen it is on, blanks out its own window and
bubble so it does not read itself, and runs the picture through the OCR built into Windows 10 and
later (`Windows.Media.Ocr`, through PowerShell; nothing to install). The text, up to
`max_characters`, goes to the model with your message, and only your message is kept in the
conversation, so old screens do not pile up. Reading takes about half a second.

The model is told plainly that this text is all it can see, and to use it only when your message
is about the screen, your code or an error; otherwise it ignores it and just talks. It cannot see
pictures, colours or layout, and must not describe anything the text does not contain. OCR reads a multi-column window
(an editor with a file tree and a side panel) as interleaved lines, so a maximised editor reads
best.

Screen reading is Windows only for now. On other systems the duck is told it could not read the
screen and says so.

The capture and the text are written to `user://screen.png` and `user://screen.txt`, overwritten
each time and never sent anywhere.

## Talking to it

While the microphone is on it shows a red dot, and a red status pill takes the text box's place,
in the same row so the answer keeps its room, saying what it is doing (`Listening...`, `Hearing
you...`, `Writing it down...`, `Thinking...`, `Talking...`), with a level meter that moves as it
hears you. The box comes back when the microphone is turned off.

The microphone button turns on a conversation. The duck listens; when you talk it records, and
when you have been quiet for `pause_seconds` (0.8 s) it writes down what you said and sends it,
with a look at the screen, exactly as if you had typed it. What it heard appears in the bubble as
`You: ...` above the answer. While it thinks and talks it stops listening, so it does not hear
itself, and it starts listening again as soon as it has finished speaking. Click the microphone
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

## How it picks the NPU, GPU or CPU

Foundry Local chooses. Asked for a model alias, it downloads the variant built for the best
hardware it finds: a QNN build for a Snapdragon X NPU, Vitis AI for an AMD Ryzen AI NPU, OpenVINO
for an Intel NPU, TensorRT-RTX or CUDA for an NVIDIA RTX GPU, WebGPU for other GPUs and Apple
silicon, and the CPU otherwise. The variant's name ends in its device
(`qwen2.5-7b-instruct-trtrtx-gpu`), which is how the duck knows where it is thinking.

## Which models it runs

Nothing is hard-coded to one machine. At startup the brain reads Foundry Local's catalog
(`foundry model list -o json`), which lists every model with its size and the build Foundry would
run here, and picks from the ranked lists in `resources/model_preferences.tres`:

| List | Best first |
| --- | --- |
| `chat` | `qwen2.5-14b`, `qwen2.5-7b`, `phi-4-mini`, `qwen2.5-1.5b`, `qwen2.5-0.5b`, then `qwen2.5-coder-*` |
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
| `Brain` | `role`, `sight_rules` | its job as a rubber duck, and what it is told about seeing; its tone is `personality.md` |
| `Mind` | `max_memories`, `max_skills` | 40 memories in the prompt, 2 skills a message |
| `Brain` | `max_tokens`, `max_history` | 160; 6 messages, the last three exchanges, sent with each prompt |
| `Voice` | `volume`, `rate` | 70, 1.0 |
| `ScreenReader` | `max_characters` | 6000 characters of screen text a message |
| `Searcher`, `FactSearcher` | `max_results`, `max_snippet`, `search_urls` | 5 results, 300 characters each, Lite then HTML |
| `Mind` | `fact_topics`, `fact_search_wait` | What it searches for new facts, in turn; 300 s before trying again after a search found none |
| `Listener` | `language` | empty, so the system language |
| `Listener` | `speech_threshold_db`, `pause_seconds` | -40 dB, 0.8 s |
| `Squeak` | `stream` | the four squeaks, picked at random |

## Layout

```
scenes/pet.tscn             the pet window: the duck's viewport, Brain, Voice, ScreenReader, and the Bubble with its tabs
scenes/duck.tscn            the 3D duck, its camera and lights
scripts/pet.gd              edge walking, dragging, the bubble, greetings, stats and voice settings
scripts/duck.gd             the duck's poses and animations
scripts/brain.gd            starts Foundry Local, picks the models and talks to its OpenAI-compatible API
scripts/mind.gd             the duck's name, personality, memories and skills, in user://duck
seed/                       the first personality and skills, copied to user://duck on first run
scripts/model_preferences.gd  the ranked model lists and the memory budget
resources/model_preferences.tres  the lists themselves, edited in the inspector
scripts/screen_reader.gd    captures the screen and reads it with the system OCR
scripts/searcher.gd         looks things up on DuckDuckGo when asked to
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
tests/unit/                 GUT tests
tests/fixtures/             Foundry's real catalog output, for the model choice tests
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
handling of Foundry Local's responses and of the screen text; and choosing, saving and falling back
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
- A click handled through `Area2D.input_event` is lost when the press and the release fall in the
  same physics frame: picking sees the press a frame late, after the release has gone by, and the
  duck is left stuck to the cursor. The window's mouse passthrough already limits input to the
  duck, so the pet takes the mouse in `_unhandled_input` instead.

## Credits

See [CREDITS.md](CREDITS.md).
