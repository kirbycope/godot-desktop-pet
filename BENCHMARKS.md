# Benchmarks: the phone duck's local models

How each engine and model runs the duck on a phone with no PC, measured by the app's own benchmark
(**Run the benchmark** on the Stats tab, `scripts/local_bench.gd`). The method and the metrics file
are described in the README, under "Picking the phone's model, and the benchmark".

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
- **The smaller `-gpu.litertlm` files write nonsense on the Snapdragon 8 Gen 3**: English broken off
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

## Running it again

On the phone, with no PC: **Try local LLM**, then the Stats tab's **Run the benchmark**. Leave the
app in front (the screen stays on by itself); it takes about an hour for all eleven setups and
downloads about 31 GB. Then:

```powershell
adb exec-out run-as com.kirbycope.duck cat files/llm_metrics.jsonl > llm_metrics.jsonl
python tools/llm_report.py llm_metrics.jsonl
```

`tools/llm_report.py` prints the table above (the last run, or `--run <name>`). The answers are in
the phone's `files/bench/conversations/`. Add a section here for each phone or engine version worth
keeping.
