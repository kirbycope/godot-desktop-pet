extends GutTest
## The PC benchmark's helpers (tools/pc_bench.gd): which Foundry builds it tries, what it calls
## them, and when the GPU counts as cool. The run itself needs Foundry Local and takes hours.

const PcBench: GDScript = preload("res://tools/pc_bench.gd")


func test_it_tries_every_chat_build_of_the_ducks_models() -> void:
	var catalog: Array = [
		{"alias": "qwen2.5-7b", "variantName": "qwen2.5-7b-instruct-cuda-gpu", "type": "Chat", "device": "Gpu", "executionProvider": "CUDAExecutionProvider"},
		{"alias": "qwen2.5-7b", "variantName": "qwen2.5-7b-instruct-generic-cpu", "type": "Chat", "device": "Cpu", "executionProvider": "CPUExecutionProvider"},
		{"alias": "qwen2.5-coder-1.5b", "variantName": "qwen2.5-coder-1.5b-instruct-trtrtx-gpu", "type": "Chat", "device": "Gpu", "executionProvider": "NvTensorRTRTXExecutionProvider"},
		{"alias": "deepseek-r1-7b", "variantName": "deepseek-r1-7b-cuda-gpu", "type": "Chat", "device": "Gpu", "executionProvider": "CUDAExecutionProvider"},
		{"alias": "parakeet-tdt-0.6b-v2", "variantName": "parakeet", "type": "AutomaticSpeechRecognition", "device": "Gpu"},
	]
	var names: Array = PcBench.chat_builds(catalog, PackedStringArray(["qwen2.5-7b", "qwen2.5-coder-*", "parakeet-*"])).map(func(b: Dictionary) -> String: return b["variantName"])
	assert_eq(names, ["qwen2.5-7b-instruct-cuda-gpu", "qwen2.5-7b-instruct-generic-cpu", "qwen2.5-coder-1.5b-instruct-trtrtx-gpu"], "every build, chat only, and only the duck's models")


func test_a_build_is_named_by_model_provider_and_chip() -> void:
	assert_eq(PcBench.label_for({"alias": "qwen2.5-coder-7b", "device": "Gpu", "executionProvider": "CUDAExecutionProvider"}), "Qwen 2.5 Coder 7B, Foundry CUDA GPU")
	assert_eq(PcBench.label_for({"alias": "qwen2.5-14b", "device": "Gpu", "executionProvider": "NvTensorRTRTXExecutionProvider"}), "Qwen 2.5 14B, Foundry TensorRT-RTX GPU")
	assert_eq(PcBench.label_for({"alias": "phi-4-mini", "device": "Cpu", "executionProvider": "CPUExecutionProvider"}), "Phi 4 Mini, Foundry CPU")


func test_on_a_mac_each_gguf_is_a_setup_too() -> void:
	var builds: Array[Dictionary] = PcBench.llama_builds({"qwen2.5-7b": "bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M"})
	assert_eq(builds[0]["variantName"], "llama-qwen2.5-7b")
	assert_eq(PcBench.label_for(builds[0]), "Qwen 2.5 7B, llama.cpp Metal")
	assert_string_ends_with(PcBench.hf_folder("bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M"), "hub/models--bartowski--Qwen2.5-7B-Instruct-GGUF")


func test_the_gpu_is_cool_near_where_it_began_and_idle() -> void:
	assert_true(PcBench.cool_enough({"gpu_c": 46.0, "gpu_util": 0}, 48.0, 10))
	assert_false(PcBench.cool_enough({"gpu_c": 61.0, "gpu_util": 0}, 48.0, 10), "still warm")
	assert_false(PcBench.cool_enough({"gpu_c": 45.0, "gpu_util": 85}, 48.0, 10), "still busy")
	assert_true(PcBench.cool_enough({}, 48.0, 10), "no GPU to read counts as cool")
