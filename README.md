# Desktop Pet: a 3D rubber duck debugger

A Godot 4 desktop pet you explain your code to. A 3D rubber duck lives in its own transparent,
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

On first start the duck looks at the hardware, starts the Foundry Local server on port 39839,
downloads the model (once) and loads it. Until then the chat box shows what it is doing, and the
Stats tab has the whole story.

| Do this | And the duck |
| --- | --- |
| Left-click | quacks one of its greetings aloud, shown in the bubble too; clicking again closes it |
| Type in the orange box and press Enter, or Send | reads your screen, then answers in the bubble and out loud; Escape closes it |
| Drag | dangles from the cursor, then tumbles back to the bottom when let go |
| Right-click | opens the menu, with Quit |

The bubble has three tabs:

| Tab | Shows |
| --- | --- |
| Chat | the greeting or the latest answer, and the box to type in |
| Stats | the brain's state (`Ready, thinking on the GPU.`), the NPU and GPU with their TOPS, the model, the voice, and how much the last look at the screen read (or why it failed) |
| Settings | every text-to-speech voice the system offers. Test says a line in the selected one without changing anything; Apply makes it the duck's voice and saves it |

## Reading the screen

Each time you send a message the duck captures the screen it is on, blanks out its own window and
bubble so it does not read itself, and runs the picture through the OCR built into Windows 10 and
later (`Windows.Media.Ocr`, through PowerShell; nothing to install). The text, up to
`max_characters`, goes to the model with your message, and only your message is kept in the
conversation, so old screens do not pile up. Reading takes about half a second.

The model is told plainly that this text is all it can see: it cannot see pictures, colours or
layout, and must not describe anything the text does not contain. OCR reads a multi-column window
(an editor with a file tree and a side panel) as interleaved lines, so a maximised editor reads
best.

Screen reading is Windows only for now. On other systems the duck is told it could not read the
screen and says so.

The capture and the text are written to `user://screen.png` and `user://screen.txt`, overwritten
each time and never sent anywhere.

## How it picks the NPU, GPU or CPU

Foundry Local chooses. Asked for a model alias, it downloads the variant built for the best
hardware it finds: a QNN build for a Snapdragon X NPU, Vitis AI for an AMD Ryzen AI NPU, OpenVINO
for an Intel NPU, TensorRT-RTX or CUDA for an NVIDIA RTX GPU, WebGPU for other GPUs and Apple
silicon, and the CPU otherwise. The variant's name ends in its device
(`qwen2.5-coder-7b-instruct-trtrtx-gpu`), which is how the duck knows where it is thinking.

The default is `qwen2.5-coder-7b`. The 1.5B model it started with could not cope with screen text:
asked to describe the screen it pasted the OCR back, and asked which file was open it made one up.
The 7B coder model summarises what it read and says when it cannot tell. It needs about 5 GB of
memory on the GPU or NPU; on a 12 GB GPU, leave no other model loaded alongside it, since running
out of video memory while it loads can take the duck's own window down with it.

Two things worth knowing:

- **Apple's Neural Engine is not used.** Foundry Local runs on the Apple silicon GPU through
  WebGPU and Metal. The duck still reports the Neural Engine's rated TOPS.
- **NPU support needs current drivers.** Foundry Local's CLI reference lists the minimum driver
  for each NPU; an Intel NPU needs Arrow Lake or later and Intel's NPU driver.

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

## The duck

`scenes/duck.tscn` is the 3D duck: the model under three nodes (`Pivot` rolls it onto the edge it
is on, `Body` carries the animation, `Yaw` turns it left or right and 30 degrees toward the camera),
an orthographic camera, a sun and ambient light. `scenes/pet.tscn` shows it through a transparent
`SubViewport`. The model faces +X, so from the camera it is seen side on, and its base sits on the
bottom of the view so rolling it 90 degrees stands it on a wall.

Its animations are posed in `scripts/duck.gd` rather than keyed: `walk` and `climb` waddle,
`hang` sways upside down, `idle` bobs, `cheer` hops and spins, `think` tilts its head, `talk` bobs
like a quack, `fall` tumbles and `land` squashes. `tools/model_shot.gd` renders a model from four
sides to see which way it faces before it goes into a scene:

```powershell
& 'C:\Godot\godot.exe' --path . -s tools/model_shot.gd -- res://assets/duck/rubber_duck.fbx res://screenshots/model_shot.png
```

## Changing it

The settings are exported on the nodes of `scenes/pet.tscn` and `scenes/duck.tscn`:

| Node | Setting | Default |
| --- | --- | --- |
| `Pet` | `speed`, `fall_speed` | 60, 700 pixels a second |
| `Pet` | `idle_chance`, `climb_chance` | 0.3 at a bottom corner, 0.5 at any corner |
| `Pet` | `greetings` | ten canned greetings, one picked at random on each click |
| `Pet` | `test_line` | what the Test button says |
| `Duck` | `turn_to_camera` | 30 degrees |
| `Brain` | `model_alias` | `qwen2.5-coder-7b` (4.7 GB); `qwen2.5-1.5b` (1.3 GB) for a smaller machine, and `foundry model list` shows the rest |
| `Brain` | `port` | 39839 |
| `Brain` | `personality`, `sight_rules` | the rubber duck system prompt, and what it is told about seeing |
| `Brain` | `max_tokens`, `max_history` | 160, 12 messages |
| `Voice` | `volume`, `rate` | 70, 1.0 |
| `ScreenReader` | `max_characters` | 6000 characters of screen text a message |

## Layout

```
scenes/pet.tscn             the pet window: the duck's viewport, Brain, Voice, ScreenReader, and the Bubble with its tabs
scenes/duck.tscn            the 3D duck, its camera and lights
scripts/pet.gd              edge walking, dragging, the bubble, greetings, stats and voice settings
scripts/duck.gd             the duck's poses and animations
scripts/brain.gd            starts Foundry Local and talks to its OpenAI-compatible API
scripts/screen_reader.gd    captures the screen and reads it with the system OCR
scripts/voice.gd            speaks through the system's TTS voices and saves the chosen one
scripts/hardware.gd         finds the NPU and GPU and their TOPS
assets/duck/                the rubber duck model
tools/npu_tops.py           the TOPS report as a standalone script
tools/model_shot.gd         renders a model from four sides
tools/inspect_model.gd      prints a model's nodes, size, materials and animations
tests/unit/                 GUT tests
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

Two things found the hard way:

- Foundry Local's REST reference documents `/openai/loadedmodels`, but CLI 0.10.3 answers it with
  404, so the brain reads the loaded model from the standard `/v1/models`.
- `StorageFile.GetFileFromPathAsync` fails on Godot's forward-slash paths with only "One or more
  errors occurred", and Godot decodes a child process's stdout in the console code page, so the
  OCR script normalises its path and writes its text to a UTF-8 file.

## Credits

See [CREDITS.md](CREDITS.md).
