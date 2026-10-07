extends GutTest


func test_rated_npu_tops_by_name() -> void:
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["Snapdragon(R) X Elite - X1E78100 - Qualcomm(R) Oryon(TM) CPU"])), 45.0)
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["AMD Ryzen AI 9 HX 370 w/ Radeon 890M"])), 50.0)
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["AMD Ryzen 7 8840HS w/ Radeon 780M Graphics"])), 16.0)
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["Apple M4 Pro Neural Engine"])), 38.0)


func test_intel_generations_are_told_apart() -> void:
	# Windows' own spelling, with (R) and (TM) in the middle of the name.
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["Intel(R) Core(TM) Ultra 7 258V"])), 48.0, "Lunar Lake")
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["Intel(R) Core(TM) Ultra 9 285H"])), 13.0, "Arrow Lake")
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["Intel(R) Core(TM) Ultra 7 155H"])), 11.0, "Meteor Lake")


func test_unknown_or_absent_npu_is_negative() -> void:
	assert_eq(Hardware.rated_npu_tops(PackedStringArray()), -1.0)
	assert_eq(Hardware.rated_npu_tops(PackedStringArray(["AMD Ryzen 9 7845HX with Radeon Graphics"])), -1.0)


func test_ada_gpu_tops_matches_nvidia_figures() -> void:
	# NVIDIA rates the 4080 Laptop at 542 AI TOPS with sparsity at its 2.28 GHz boost: 271 dense.
	assert_almost_eq(Hardware.ada_gpu_tops("NVIDIA GeForce RTX 4080 Laptop GPU", 2280.0), 270.8, 0.5)
	# And the desktop 4090 at 1321 sparse, 661 dense, at 2520 MHz.
	assert_almost_eq(Hardware.ada_gpu_tops("NVIDIA GeForce RTX 4090", 2520.0), 660.6, 0.5)


func test_laptop_gpu_is_not_mistaken_for_the_desktop_part() -> void:
	assert_almost_eq(Hardware.ada_gpu_tops("RTX 4080 Laptop GPU", 1000.0), 58 * 2.048, 0.01)


func test_non_ada_gpu_is_negative() -> void:
	assert_eq(Hardware.ada_gpu_tops("AMD Radeon 610M", 2200.0), -1.0)


func test_npu_pattern_does_not_match_input_devices() -> void:
	var regex: RegEx = RegEx.create_from_string(Hardware.NPU_PATTERN)
	assert_null(regex.search("USB Input Device"))
	assert_not_null(regex.search("Intel(R) AI Boost"))
	assert_not_null(regex.search("NPU Compute Accelerator Device"))


func test_describe_names_both_accelerators() -> void:
	var text: String = Hardware.describe()
	assert_string_contains(text, "NPU:")
	assert_string_contains(text, "GPU:")
