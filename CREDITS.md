# Credits

Third-party work in this repository: who made it, where it came from, its licence and where it sits in the tree.

| Folder | Asset | Author | License | Source |
| --- | --- | --- | --- | --- |
| `assets/duck` | Rubber Duck (`rubber_duck.fbx`) | Polygate2 | CGTrader Royalty Free License (no AI) | https://www.cgtrader.com/3d-models/architectural/other/rubber-duck-48c4668d-70d0-4753-8d1e-75541181ceb9 |
| `assets/audio` | RubberDuckSqueak CRT2045701, cut into four squeaks (`duck_squeak_01.ogg` to `04`) | Audio Hero Inc. | Audio Hero End User License Agreement | https://download.audiohero.com/track/14678241 |
| `assets/icons` | `microphone.svg` from Mobile Controls 1.0 | Kenney | CC0 (`License.txt`) | https://kenney.nl |
| `bin/windows/kokoro-server.exe` | Built from `tools/kokoro_server/kokoro_server.c` against sherpa-onnx's C API | this project; sherpa-onnx by k2-fsa | sherpa-onnx: Apache 2.0 | https://github.com/k2-fsa/sherpa-onnx |

The window technique comes from DigiKey's [Desktop Pet](https://www.digikey.com/en/maker/projects/desktop-pet/994f9b5997fa4d6899c022c9b23724a6)
maker project. None of its sprites are used here.

The pet's language models are downloaded at run time by [Foundry Local](https://github.com/microsoft/Foundry-Local)
and are not part of this repository; each carries its publisher's licence, which
`foundry model info <alias>` shows. The default, Qwen2.5 Coder 7B Instruct, is Apache 2.0.

[GUT](https://github.com/bitwes/Gut) (MIT) runs the tests and is fetched, not committed.

The natural voices are downloaded at run time into `user://kokoro` when asked for, and are not
part of this repository: the Kokoro v1.0 model (82M parameters, by hexgrad, Apache 2.0,
https://huggingface.co/hexgrad/Kokoro-82M) as packaged by sherpa-onnx, sherpa-onnx's own tools
(Apache 2.0) and ONNX Runtime (MIT), and the espeak-ng phoneme data that comes inside the model
package (GPL 3.0).
