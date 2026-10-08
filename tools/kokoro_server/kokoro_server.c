/*
 * kokoro-server: keeps the Kokoro voice model loaded and speaks one line per request.
 *
 * sherpa-onnx's own sherpa-onnx-offline-tts loads the 310 MB model for every line and exits, which
 * costs about a second before each reply. This loads it once and then waits.
 *
 *   kokoro-server <kokoro model folder> <threads>
 *
 * Each request is one line on stdin, fields separated by tabs:
 *
 *   <speaker id> \t <lexicon file name> \t <output .wav path> \t <text>
 *
 * and the answer is one line on stdout: "ok", or "error <why>". The model is (re)loaded when the
 * lexicon changes, which is when the duck switches between American and British voices. It exits
 * when stdin closes.
 *
 * Built against sherpa-onnx's C API (Apache 2.0); see build.bat.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sherpa-onnx/c-api/c-api.h"

#define LINE_MAX_BYTES 16384
#define PATH_MAX_BYTES 2048

static char model_dir[PATH_MAX_BYTES];
static int threads = 4;
static const SherpaOnnxOfflineTts *tts = NULL;
static char loaded_lexicon[PATH_MAX_BYTES] = "";

static void join(char *out, const char *dir, const char *name) {
  snprintf(out, PATH_MAX_BYTES, "%s/%s", dir, name);
}

/* Loads the model with `lexicon`, unless it is already loaded with it. */
static int load(const char *lexicon) {
  if (tts != NULL && strcmp(lexicon, loaded_lexicon) == 0) {
    return 1;
  }
  if (tts != NULL) {
    SherpaOnnxDestroyOfflineTts(tts);
    tts = NULL;
  }
  char model[PATH_MAX_BYTES], voices[PATH_MAX_BYTES], tokens[PATH_MAX_BYTES];
  char data[PATH_MAX_BYTES], dict[PATH_MAX_BYTES], lex[PATH_MAX_BYTES];
  join(model, model_dir, "model.onnx");
  join(voices, model_dir, "voices.bin");
  join(tokens, model_dir, "tokens.txt");
  join(data, model_dir, "espeak-ng-data");
  join(dict, model_dir, "dict");
  join(lex, model_dir, lexicon);

  SherpaOnnxOfflineTtsConfig config;
  memset(&config, 0, sizeof(config));
  config.model.kokoro.model = model;
  config.model.kokoro.voices = voices;
  config.model.kokoro.tokens = tokens;
  config.model.kokoro.data_dir = data;
  config.model.kokoro.dict_dir = dict;
  config.model.kokoro.lexicon = lex;
  config.model.kokoro.length_scale = 1.0f;
  config.model.num_threads = threads;
  config.model.provider = "cpu";
  config.max_num_sentences = 1;

  tts = SherpaOnnxCreateOfflineTts(&config);
  if (tts == NULL) {
    loaded_lexicon[0] = '\0';
    return 0;
  }
  snprintf(loaded_lexicon, sizeof(loaded_lexicon), "%s", lexicon);
  return 1;
}

static void answer(const char *text) {
  fputs(text, stdout);
  fputc('\n', stdout);
  fflush(stdout);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: kokoro-server <kokoro model folder> [threads]\n");
    return 2;
  }
  snprintf(model_dir, sizeof(model_dir), "%s", argv[1]);
  if (argc > 2) {
    threads = atoi(argv[2]) > 0 ? atoi(argv[2]) : 4;
  }

  static char line[LINE_MAX_BYTES];
  while (fgets(line, sizeof(line), stdin) != NULL) {
    line[strcspn(line, "\r\n")] = '\0';
    char *sid_text = strtok(line, "\t");
    char *lexicon = strtok(NULL, "\t");
    char *wav = strtok(NULL, "\t");
    char *text = strtok(NULL, "");
    if (sid_text == NULL || lexicon == NULL || wav == NULL || text == NULL) {
      answer("error bad request");
      continue;
    }
    if (!load(lexicon)) {
      answer("error the model would not load");
      continue;
    }
    SherpaOnnxGenerationConfig generation;
    memset(&generation, 0, sizeof(generation));
    generation.sid = atoi(sid_text);
    generation.speed = 1.0f;
    generation.silence_scale = 0.2f;
    const SherpaOnnxGeneratedAudio *audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &generation, NULL, NULL);
    if (audio == NULL || audio->n == 0) {
      answer("error nothing was generated");
    } else if (!SherpaOnnxWriteWave(audio->samples, audio->n, audio->sample_rate, wav)) {
      answer("error the wav could not be written");
    } else {
      answer("ok");
    }
    if (audio != NULL) {
      SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    }
  }
  if (tts != NULL) {
    SherpaOnnxDestroyOfflineTts(tts);
  }
  return 0;
}
