# Benchmarks: the duck's local models

How each engine and model runs the duck, on a phone with no PC (the app's own benchmark, **Run the
benchmark** on the Stats tab, `scripts/local_bench.gd`) and on the PC and Mac (`tools/pc_bench.gd`,
the same four lines through the PC duck's own brain). The method and the metrics file are described
in the README, under "Picking the phone's model, and the benchmark".

Read the answers as well as the times: on both the phone and the PC the fastest setups were among
those writing nonsense, and the tables below say which by reading every answer, not only by
`LlmMetrics.garbled`.

## 2026-10-09, Galaxy S24 Ultra

| | |
| --- | --- |
| Phone | Samsung Galaxy S24 Ultra (SM-S928U), Snapdragon 8 Gen 3 (SM8650), 12 GB, Android 16 |
| Conditions | On its charger at 100 %, Wi-Fi, screen brightness turned down, the duck app in front throughout |
| Engines | NobodyWho 12.1.0 (llama.cpp, Vulkan), LiteRT-LM 0.18.0, Gemini Nano through ML Kit GenAI Prompt 1.0.0-beta4 |
| App | Godot 4.8-dev6, debug build |
| Run | `2026-10-09-173732`, raw lines in [benchmarks/2026-10-09_173732_galaxy-s24-ultra.jsonl](benchmarks/2026-10-09_173732_galaxy-s24-ultra.jsonl) |

Every setup started from nothing: the model before it let go, every downloaded model and LiteRT-LM's
compiled GPU code deleted, and the phone left to cool to within 1 C of where it began (37.1 C) with
Android reporting no throttling, before the download and again before the first line. Each was then
asked the same four lines in one conversation:

1. Hi duck, what do you like to do for fun?
2. What's your favourite colour?
3. My loop never ends. What should I check first?
4. Tell me a short joke about ducks.

The first answer after a start is shown apart, since it includes reading the duck's personality
(1,296 tokens with the first line, against 15 to 19 for each later one); "later" is the average of the other three. "First word" is
the time from sending the line to the first piece of the answer, "talking" to its first whole
sentence (when the duck starts speaking), "whole" to its end. Speeds are tokens a second while
writing: LiteRT-LM's own count where it gives one, otherwise pieces streamed over time.

| Setup | Download | Warm-up | First answer: word / talking / whole | Later: word / talking / whole | Tokens/s | Peak memory | Text |
| --- | --- | ---: | --- | --- | ---: | ---: | --- |
| Gemma 4 E2B, NobodyWho | 3,106 MB in 45 s | 7.5 s | 26.2 / 32.4 / 60.3 s | 2.9 / 8.3 / 37.2 s | 1.5 | 4.0 GB | fine |
| Gemma 4 E4B, NobodyWho | 4,977 MB in 69 s | 12.3 s | 59.5 / 60.8 / 80.7 s | 2.8 / 7.7 / 26.6 s | 2.6 | 6.3 GB | fine |
| Qwen 3.5 2B, NobodyWho | 1,280 MB in 21 s | 2.9 s | 11.5 / 12.1 / 19.8 s | 2.0 / 3.4 / 10.5 s | 10.3 | 1.9 GB | fine |
| Qwen 3.5 4B, NobodyWho | 2,740 MB in 37 s | 5.7 s | 30.1 / 35.9 / 43.8 s | 4.4 / 6.8 / 12.8 s | 4.7 | 3.6 GB | fine |
| Gemma 4 E2B, LiteRT-LM CPU | 2,588 MB in 36 s | 4.1 s | 9.6 / 9.9 / 12.5 s | 0.9 / 1.6 / 4.1 s | 17.2 | 2.6 GB | fine |
| **Gemma 4 E2B, LiteRT-LM GPU** | 2,588 MB in 37 s | 13.2 s | 1.9 / 2.0 / 3.7 s | 0.2 / 0.6 / 2.2 s | 27.6 | 2.7 GB | fine |
| Gemma 4 E2B (`-gpu` file), LiteRT-LM GPU | 2,008 MB in 29 s | 9.0 s | 1.5 / 1.6 / 3.1 s | 0.2 / 0.3 / 1.6 s | 32.0 | 2.9 GB | **garbled** |
| Gemma 4 E4B, LiteRT-LM CPU | 3,659 MB in 66 s | 7.3 s | 18.5 / 18.8 / 23.5 s | 1.6 / 2.7 / 6.7 s | 11.6 | 4.7 GB | fine |
| Gemma 4 E4B, LiteRT-LM GPU | 3,659 MB in 61 s | 25.1 s | 3.2 / 3.4 / 7.5 s | 0.9 / 2.6 / 6.9 s | 9.4 | 4.7 GB | fine |
| Gemma 4 E4B (`-gpu` file), LiteRT-LM GPU | 2,969 MB in 46 s | 13.0 s | 2.8 / 3.5 / 6.0 s | 0.4 / 1.1 / 5.0 s | 16.9 | 5.7 GB | **garbled** |
| Gemini Nano, Android AICore | | | | | | | not offered: "AICore says this phone has no Gemini Nano" |

Downloads ran at 55 to 74 MB/s over Wi-Fi, so their times say more about the network than the
engine; what matters is the size. The app's memory with no model loaded was about 0.45 GB.

### What it shows

- **LiteRT-LM is the engine for Gemma 4 on this phone.** The same Gemma 4 E2B that takes a minute for
  its first answer on NobodyWho, at 1.5 tokens a second, takes 3.7 s on LiteRT-LM's GPU backend at
  28 tokens a second: about twenty times faster, in two thirds of the memory. Even LiteRT-LM's CPU
  backend is ten times faster than NobodyWho's GPU here.
- **The phone duck now defaults to Gemma 4 E2B on LiteRT-LM's GPU** (`LocalBrain.auto_setups`), and
  to the same file on the CPU where the GPU will not start, so the fallback downloads nothing more.
  NobodyWho remains the last resort, for a build without the Android plugin.
- **The smaller `-gpu.litertlm` files write nonsense on the Snapdragon 8 Gen 3** (found by reading
  the answers after this run; benchmarks since check every answer, `LlmMetrics.garbled`, and fail a
  setup that writes nonsense however fast it is): English broken off
  mid-word into fragments of Hindi, Thai, Korean and Japanese, for both E2B and E4B, while the
  standard file on the same GPU backend writes perfectly well. They post the best times in the table,
  which is exactly why the text has to be read and not just timed. They stay in the setups list, to
  be tried on other phones.
- **Gemma 4 E4B on the GPU is slower than on the CPU once warmed up** (9.4 against 11.6 tokens a
  second), with the phone left about 2.3 GB of free memory; it starts answering much sooner, though.
- **On NobodyWho, Qwen 3.5 2B is the one to pick**: 10 tokens a second in 1.9 GB, seven times
  Gemma 4 E2B's speed there.
- **The first answer costs reading the personality.** Every setup's first answer is several times
  its later ones; on LiteRT-LM's GPU that is 1.9 s against 0.2 s to the first word.
- **Heat matters, and the cool-downs earned their keep.** Gemma 4 on NobodyWho alone took the phone
  to Android's thermal state 2 (moderate) and 3 (severe) within a few answers. An earlier run with no
  cool-downs, right after a 3 GB download, is not counted here.
- **LiteRT-LM's own time to first token** (`native_ttft_s` in the raw lines) stays at the first
  answer's value on every later one, so it measures the first answer only; the app's own "first word"
  is the figure to compare.

### What each said to "My loop never ends. What should I check first?"

| Setup | Answer |
| --- | --- |
| Gemma 4 E2B, NobodyWho | Oh dear, a loop! That sounds like a tricky little puzzle for your program! We need to see where the loop is getting stuck so we can figure it out together. Have you tried printing something to see how many times it's running? |
| Gemma 4 E4B, NobodyWho | Oh, a runaway loop! Those are tricky little critters, aren't they? When things get stuck in a loop, you gotta figure out where the happy path might have gone wrong. What is that loop supposed to be doing, and what is it actually doing instead? |
| Qwen 3.5 2B, NobodyWho | Ooh, a classic bug! The first thing to check is whether your code is actually running, or if you're just stuck in an endless loop waiting for something that never comes. Have you ever tried printing your variable at the top of the function to see if... |
| Qwen 3.5 4B, NobodyWho | Ooh, an infinite loop! That's a classic mystery I love to solve. Have you checked if the variable you're supposed to change is actually changing, or is it stuck in a loop of its own? |
| Gemma 4 E2B, LiteRT-LM CPU | Oh dear, a loop that never ends sounds like a real puzzle! When a loop gets stuck, the first thing I always suggest is to carefully trace the path of the loop to see where the condition might be getting stuck in a loop. Have you tried looking at the... |
| Gemma 4 E2B, LiteRT-LM GPU | A loop that won't end sounds like a real puzzle, doesn't it? When a loop gets stuck, the very first thing to check is usually the condition that tells it when to stop. Have you thought about what happens to the variable controlling the loop as it runs? |
| Gemma 4 E2B (`-gpu` file), LiteRT-LM GPU | Ouch! That's a bit of a tough spot, but I know sometimes the biggest hurdle is just figuring where you start. When you say your loop never ends, is it like a big unfinished project, or is it something else that needs to get sorted? (its other three answers were garbled) |
| Gemma 4 E4B, LiteRT-LM CPU | Oh dear, a loop that won't quit! That sounds like a tricky little puzzle, but we can definitely find the exit! Can you tell me what the loop is supposed to be doing, and what it's doing instead? |
| Gemma 4 E4B, LiteRT-LM GPU | Oh dear, an endless loop! That sounds like a tricky little puzzle, but we can definitely find the bug together! What language are you using for this loop, and what is it supposed to be doing? |
| Gemma 4 E4B (`-gpu` file), LiteRT-LM GPU | Aan excuse rings hollow에 대한 aDance! Ouch, thingsSoundNhap structure-aware! If arias sing, of course, I'd probably checkSleep... |

## 2026-10-09, Alienware m18 (PC)

| | |
| --- | --- |
| Machine | Alienware m18 R1 AMD: Ryzen 9 7845HX, 32 GB, GeForce RTX 4080 Laptop GPU (12 GB), Windows 11 (10.0.26200) |
| Conditions | On mains power, the PC duck closed, nothing else using Foundry Local |
| Engine | Foundry Local 0.10.3, every build of the duck's chat models (`resources/model_preferences.tres`) in its catalogue: TensorRT-RTX, CUDA and WebGPU on the GPU, and the CPU |
| Run | `2026-10-09-192206`, raw lines in [benchmarks/2026-10-09_192206_alienware-m18.jsonl](benchmarks/2026-10-09_192206_alienware-m18.jsonl); Qwen 2.5 14B on TensorRT-RTX again as `2026-10-09-210606`, in [benchmarks/2026-10-09_210606_alienware-m18_14b-trtrtx-retry.jsonl](benchmarks/2026-10-09_210606_alienware-m18_14b-trtrtx-retry.jsonl) |

As on the phone, every build started from nothing: every cached build of the duck's chat models
deleted and Foundry's server stopped, the GPU left to cool to within 3 C of where it began (44 C)
and idle, then the build downloaded, started by the PC duck's own brain (its prompts, reminders and
160-token answers) in a mind of its own, and asked the same four lines. "Warm-up" is from the
download's end to the brain being ready: starting Foundry's server and loading the build. Speeds are
pieces streamed a second, which Foundry sends a token at a time. "GPU" is the most graphics memory
in use, about 0.9 GB of it other programs'. CPU builds' GPU figures are that baseline.

| Setup | Download | Warm-up | First answer: word / whole | Later: word / whole | Tokens/s | GPU / Foundry memory | Text |
| --- | --- | ---: | --- | --- | ---: | --- | --- |
| Phi-4-mini, CUDA | 3,686 MB in 58 s | 13.6 s | 1.3 / 3.3 s | 0.4 / 1.6 s | 75 | 11.6 / 1.3 GB | answers as "You:" |
| Phi-4-mini, WebGPU | 3,809 MB in 49 s | 13.5 s | 1.1 / 1.9 s | 0.3 / 1.0 s | 100 | 10.6 / 1.3 GB | fine, if rambling |
| Phi-4-mini, CPU | 4,915 MB in 77 s | 16.0 s | 14.7 / 20.4 s | 15.6 / 22.4 s | 11 | - / 5.7 GB | answers as "You:" |
| Qwen 2.5 0.5B, TensorRT-RTX | 528 MB in 24 s | 17.5 s | 0.7 / 1.8 s | 0.2 / 0.6 s | 125 | 6.0 / 0.9 GB | broken |
| Qwen 2.5 0.5B, CUDA | 528 MB in 16 s | 11.0 s | 0.3 / 0.6 s | 0.1 / 0.9 s | 187 | 5.9 / 1.0 GB | broken |
| Qwen 2.5 0.5B, WebGPU | 700 MB in 15 s | 11.0 s | 0.3 / 1.1 s | 0.1 / 0.3 s | 123 | 5.8 / 1.0 GB | broken |
| Qwen 2.5 0.5B, CPU | 822 MB in 20 s | 12.0 s | 2.8 / 3.3 s | 3.0 / 4.8 s | 67 | - / 1.4 GB | broken |
| Qwen 2.5 1.5B, TensorRT-RTX | 1,280 MB in 51 s | 19.6 s | 0.9 / 2.8 s | 0.4 / 1.0 s | 77 | 8.3 / 0.8 GB | answers as "You:" |
| Qwen 2.5 1.5B, CUDA | 1,280 MB in 26 s | 11.0 s | 0.4 / 0.7 s | 0.2 / 1.0 s | 144 | 7.8 / 1.1 GB | broken |
| Qwen 2.5 1.5B, WebGPU | 1,546 MB in 25 s | 11.0 s | 0.4 / 0.8 s | 0.2 / 0.7 s | 111 | 7.1 / 1.1 GB | broken |
| Qwen 2.5 1.5B, CPU | 1,822 MB in 32 s | 13.0 s | 6.6 / 7.9 s | 7.2 / 8.6 s | 26 | - / 2.4 GB | broken |
| Qwen 2.5 7B, TensorRT-RTX | 5,623 MB in 86 s | 50.3 s | 1.1 / 3.1 s | 0.7 / 1.7 s | 77 | 9.7 / 0.8 GB | fine |
| **Qwen 2.5 7B, CUDA** | 4,843 MB in 86 s | 13.5 s | 1.3 / 2.1 s | 0.6 / 1.6 s | 68 | 11.8 / 2.0 GB | fine |
| Qwen 2.5 7B, WebGPU | 5,324 MB in 87 s | 14.6 s | 1.3 / 2.1 s | 0.6 / 1.9 s | 65 | 11.8 / 2.0 GB | fine |
| Qwen 2.5 7B, CPU | 6,307 MB in 109 s | 40.7 s | 27.0 / 32.0 s | 29.4 / 36.5 s | 8 | - / 7.9 GB | fine, but slow |
| **Qwen 2.5 14B, TensorRT-RTX** (retried) | 9,000 MB in 156 s | 108.7 s | 1.5 / 2.7 s | 1.2 / 3.0 s | 39 | 11.9 / 2.9 GB | fine (the first try did not load within the duck's 10 minutes) |
| Qwen 2.5 14B, CUDA | 9,000 MB in 129 s | 15.5 s | 4.3 / 6.6 s | 39.1 / 41.1 s | 37 | 11.8 / 8.1 GB | fine, but later answers slow |
| **Qwen 2.5 14B, WebGPU** | 9,523 MB in 152 s | 17.5 s | 4.0 / 6.3 s | 3.7 / 5.7 s | 36 | 11.9 / 6.6 GB | fine |
| Qwen 2.5 14B, CPU | 11,325 MB in 192 s | 36.2 s | 53.2 / 76.6 s | 59.9 / 78.5 s | 4 | - / 13.9 GB | fine, but slow |
| Qwen 2.5 Coder 0.5B, TensorRT-RTX | 528 MB in 27 s | 18.0 s | 0.5 / 2.1 s | 0.2 / 0.8 s | 161 | 5.5 / 0.8 GB | broken |
| Qwen 2.5 Coder 0.5B, CUDA | 528 MB in 21 s | 12.0 s | 0.4 / 0.5 s | 0.1 / 0.5 s | 130 | 6.3 / 1.1 GB | broken |
| Qwen 2.5 Coder 0.5B, WebGPU | 528 MB in 18 s | 11.0 s | 0.3 / 1.4 s | 0.1 / 0.9 s | 143 | 5.3 / 1.0 GB | broken |
| Qwen 2.5 Coder 0.5B, CPU | 822 MB in 22 s | 12.0 s | 2.8 / 5.0 s | 3.4 / 5.6 s | 69 | - / 1.4 GB | broken |
| Qwen 2.5 Coder 1.5B, TensorRT-RTX | 1,280 MB in 65 s | 19.6 s | 0.5 / 3.1 s | 0.2 / 0.4 s | 58 | 7.8 / 0.8 GB | broken |
| Qwen 2.5 Coder 1.5B, CUDA | 1,280 MB in 30 s | 11.5 s | 0.4 / 1.4 s | 0.2 / 0.3 s | 98 | 7.3 / 1.1 GB | broken |
| Qwen 2.5 Coder 1.5B, WebGPU | 1,280 MB in 30 s | 12.0 s | 0.4 / 1.7 s | 0.2 / 0.3 s | 86 | 6.3 / 1.1 GB | broken |
| Qwen 2.5 Coder 1.5B, CPU | 1,822 MB in 38 s | 13.5 s | 6.7 / 11.8 s | 7.1 / 7.6 s | 23 | - / 2.4 GB | broken |
| Qwen 2.5 Coder 7B, TensorRT-RTX | 4,843 MB in 95 s | 52.8 s | 1.0 / 2.0 s | 0.7 / 1.5 s | 75 | 9.6 / 0.8 GB | fine, terse |
| Qwen 2.5 Coder 7B, CUDA | 4,843 MB in 70 s | 13.5 s | 1.3 / 2.2 s | 0.6 / 1.3 s | 66 | 11.8 / 1.9 GB | fine, terse |
| Qwen 2.5 Coder 7B, WebGPU | 4,843 MB in 71 s | 15.5 s | 1.3 / 2.0 s | 0.6 / 1.5 s | 62 | 11.9 / 1.9 GB | fine, terse |
| Qwen 2.5 Coder 7B, CPU | 6,307 MB in 95 s | 22.1 s | 26.6 / 31.6 s | 28.1 / 33.3 s | 8 | - / 7.8 GB | fine, but slow |
| **Qwen 2.5 Coder 14B, TensorRT-RTX** | 9,000 MB in 171 s | 114.8 s | 1.5 / 3.1 s | 1.3 / 3.4 s | 40 | 11.9 / 3.0 GB | fine |
| Qwen 2.5 Coder 14B, CUDA | 9,000 MB in 127 s | 15.6 s | 3.1 / 4.8 s | 3.1 / 5.5 s | 37 | 11.9 / 6.5 GB | fine |
| Qwen 2.5 Coder 14B, WebGPU | 9,000 MB in 133 s | 15.0 s | 2.7 / 4.4 s | 2.2 / 4.3 s | 36 | 11.9 / 5.5 GB | fine |
| Qwen 2.5 Coder 14B, CPU | 11,325 MB in 193 s | 31.7 s | 52.8 / 61.3 s | 55.2 / 69.9 s | 4 | - / 14.0 GB | fine, but slow |

"Broken" is not nonsense in the phone's sense (none of it tripped `LlmMetrics.garbled`) but no use
to the duck all the same: answers that repeat the question back ("Hi duck, what do you like to do
for fun?"), write the conversation's labels ("The user says:", "Answer:", "(Answer: I love green
ducks.)"), loop ("The duck is a duck, and it is a duck..."), or were all thrown away by the duck's
own repeat filter, leaving its stand-in line ("Ooh, I've lost my thread! Tell me more about that.").

### What it shows

- **The 0.5B and 1.5B models are no use to the duck on any backend**, Qwen or Coder, however fast:
  the duck's prompt is too much for them. Phi-4-mini mostly holds together but answers as "You:"
  on CUDA and the CPU.
- **From 7B up, every answer is sound**, and on the GPU every backend gives the same quality.
- **The 7B on CUDA is the quick all-rounder**: ready 13.5 s after its download, its first answer in
  2.1 s and the next ones in about 1.6 s. TensorRT-RTX answers no faster but takes 50 s to start,
  which looks like TensorRT building its engine for this GPU as it loads.
- **A 14B on the 12 GB GPU is close to the limit.** Qwen 2.5 14B on CUDA filled it (11.8 GB) and its
  later answers took 40 s, against 6 s on WebGPU with word-for-word the same answers. On
  TensorRT-RTX it did not load within the duck's 10 minutes the first time, and took 109 s the
  second. Once started, TensorRT-RTX is the best place for a 14B: about 3 s an answer for both
  Qwen 2.5 14B and Qwen 2.5 Coder 14B, with Foundry holding under half the system memory it takes
  for CUDA or WebGPU.
- **The CPU is out of the question for the duck**: 30 s an answer for a 7B, over a minute for a 14B.
- Downloads ran at 50 to 70 MB/s, so the 9 GB 14B builds took two to three minutes.

## Running it again

On the phone, with no PC: **Try local LLM**, then the Stats tab's **Run the benchmark**. Leave the
app in front (the screen stays on by itself); it takes about an hour for all eleven setups and
downloads about 31 GB. Then:

```powershell
adb exec-out run-as com.kirbycope.duck cat files/llm_metrics.jsonl > llm_metrics.jsonl
python tools/llm_report.py llm_metrics.jsonl
```

`tools/llm_report.py` prints the table above (the last run, or `--run <name>`). The answers are in
the phone's `files/bench/conversations/`.

On the PC, with the PC duck closed (it deletes every cached chat model, so the duck downloads its own
again on its next start; speech models are left alone):

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s res://tools/pc_bench.gd
python tools/llm_report.py "$env:APPDATA\Godot\app_userdata\Desktop Pet\pc_llm_metrics.jsonl"
```

`DUCK_BENCH_BUILDS` (comma-separated build names) tries only those. Every answer is in the metrics
file itself, under "text". Add a section here for each machine or engine version worth keeping.
