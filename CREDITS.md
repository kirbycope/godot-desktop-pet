# Credits

Third-party work in this repository: who made it, where it came from, its licence and where it sits in the tree.

| Folder | Asset | Author | License | Source |
| --- | --- | --- | --- | --- |
| `assets/duck`, and rendered into `assets/icons/duck_icon.png` | Rubber Duck (`rubber_duck.fbx`) | Polygate2 | CGTrader Royalty Free License (no AI) | https://www.cgtrader.com/3d-models/architectural/other/rubber-duck-48c4668d-70d0-4753-8d1e-75541181ceb9 |
| `assets/hat` | Captain Hat (`CaptainHat.FBX` and its four PBR textures) from Hat Pack 3 | Baria3DAsset | CGTrader Royalty Free License | CGTrader (bought by the author; the pack's listing link was not kept with the download) |
| `assets/audio` | RubberDuckSqueak CRT2045701, cut into four squeaks (`duck_squeak_01.ogg` to `04`) and five quick ones for throws and bounces (`duck_squeak_fast_01.ogg` to `05`) | Audio Hero Inc. | Audio Hero End User License Agreement | https://download.audiohero.com/track/14678241 |
| `assets/water/pond_water.gdshader` | The pond water: toon colours, Gerstner waves, contact and crest foam; adapted (its weather globals became plain uniforms, the stencil went, the contact foam measures from a footprint instead of the depth texture) | Antigravity Contributors, from weather-fx | MIT | https://github.com/kirbycope/weather-fx (`addons/weather_fx/resources/pond_water.gdshader`) |
| `assets/water/bubbles.gdshader` | Bubble Shader, the rainbow-rimmed bubbles | Yui Kinomoto (@arlez80) | MIT | via godot-4.5-sandbox-3d (`scenes/props/bubble/`) |
| `assets/icons` | `microphone.svg` from Mobile Controls 1.0 | Kenney | CC0 (`License.txt`) | https://kenney.nl |
| `bin/windows/kokoro-server.exe` | Built from `tools/kokoro_server/kokoro_server.c` against sherpa-onnx's C API | this project; sherpa-onnx by k2-fsa | sherpa-onnx: Apache 2.0 | https://github.com/k2-fsa/sherpa-onnx |
| `android_plugin` (its Gradle wrapper, build files and layout) and `addons/GeminiNano`, built from it | Godot Android Plugin Template | Fredia Huya-Kouadio | MIT (`android_plugin/LICENSE`) | https://github.com/m4gr3d/Godot-Android-Plugin-Template |

The window technique comes from DigiKey's [Desktop Pet](https://www.digikey.com/en/maker/projects/desktop-pet/994f9b5997fa4d6899c022c9b23724a6)
maker project. None of its sprites are used here.

The pet's language models are downloaded at run time by [Foundry Local](https://github.com/microsoft/Foundry-Local)
and are not part of this repository; each carries its publisher's licence, which
`foundry model info <alias>` shows. The default, Qwen2.5 Coder 7B Instruct, is Apache 2.0.

On macOS the chat model is downloaded instead by [llama.cpp](https://github.com/ggml-org/llama.cpp)
(MIT, installed with Homebrew, not part of this repository) as a GGUF quantisation by
[bartowski](https://huggingface.co/bartowski) on Hugging Face: Qwen2.5 Instruct 14B, 7B, 1.5B and
0.5B (Apache 2.0, by the Qwen team) and Phi-4-mini-instruct (MIT, by Microsoft), each at Q4_K_M.

[GUT](https://github.com/bitwes/Gut) (MIT) runs the tests and is fetched, not committed.

The phone app's local LLM, for when there is no PC:

- [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) 12.1.0, by the NobodyWho authors, EUPL 1.2,
  is fetched into `addons/nobodywho` by `tools/fetch_nobodywho.py` and not committed. It is built on
  [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT). The model it picks for the phone's memory
  is downloaded at run time from NobodyWho's Hugging Face mirrors and is not part of this repository:
  Gemma 4 E2B by default (Apache 2.0, by Google), or where it will not load, Qwen3, Qwen3.5 and
  Qwen3.6 (Apache 2.0, by the Qwen team) or another Gemma 4, each at Q4_K_M.
- [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) 0.18.0, by Google, Apache 2.0, is added
  to the Android export from Google's Maven repository (`com.google.ai.edge.litertlm:litertlm-android`)
  and is not part of this repository. The Gemma 4 E2B and E4B `.litertlm` models it runs (Apache 2.0,
  by Google, converted by [litert-community](https://huggingface.co/litert-community)) are downloaded
  at run time from Hugging Face and are not part of this repository either.
- Gemini Nano is Android's own model, run by the phone's AICore and reached through Google's
  [ML Kit GenAI Prompt API](https://developers.google.com/ml-kit/genai/prompt/android/get-started)
  (`com.google.mlkit:genai-prompt`, under the ML Kit terms of service), which the Android export
  adds from Google's Maven repository. Neither is part of this repository.

The natural voices are downloaded at run time into `user://kokoro` when asked for, and are not
part of this repository: the Kokoro v1.0 model (82M parameters, by hexgrad, Apache 2.0,
https://huggingface.co/hexgrad/Kokoro-82M) as packaged by sherpa-onnx, sherpa-onnx's own tools
(Apache 2.0) and ONNX Runtime (MIT), and the espeak-ng phoneme data that comes inside the model
package (GPL 3.0).
