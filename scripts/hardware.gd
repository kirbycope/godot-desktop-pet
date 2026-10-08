class_name Hardware
extends RefCounted
## Finds the NPU and GPU on this machine and their rated INT8 TOPS.
##
## No operating system reports TOPS, so the NPU figure is the vendor's rated peak looked up by name,
## and the GPU figure is computed from SM count and clock (NVIDIA Ada only). The same lookups are in
## tools/npu_tops.py for use outside Godot.

## Regex over the lower-cased device or CPU name with (R) and (TM) removed, and its rated INT8
## TOPS. First match wins, so the more specific patterns come first.
const NPU_TOPS: Dictionary[String, float] = {
	"snapdragon x|hexagon": 45.0,
	"core ultra [3579] 2\\d\\dv\\b": 48.0, # Lunar Lake
	"core ultra [3579] 2\\d\\d": 13.0, # Arrow Lake
	"core ultra [3579] 1\\d\\d": 11.0, # Meteor Lake
	"ryzen ai": 50.0, # Strix Point, Krackan, Strix Halo
	"ryzen [3579] 8\\d\\d\\d": 16.0, # Hawk Point
	"ryzen [3579] 7\\d40": 10.0, # Phoenix
	"apple m4": 38.0, "apple m3": 18.0, "apple m2": 15.8, "apple m1": 11.0,
}

## Ada Lovelace (RTX 40 series) streaming multiprocessor counts. Laptop names come first.
const ADA_SMS: Dictionary[String, int] = {
	"4090 laptop": 76, "4080 laptop": 58, "4070 laptop": 36, "4060 laptop": 24, "4050 laptop": 20,
	"4090": 128, "4080 super": 80, "4080": 76, "4070 ti super": 66, "4070 ti": 60,
	"4070 super": 56, "4070": 46, "4060 ti": 34, "4060": 24,
}

## Ada tensor cores, dense INT8. Sparsity doubles it, which is the "AI TOPS" NVIDIA advertises.
const INT8_OPS_PER_SM_PER_CLOCK: int = 2048

## PnP names that mean an NPU. Case-sensitive with word boundaries, so "Input" is not "NPU".
const NPU_PATTERN: String = "\\bNPU\\b|AI Boost|Neural|XDNA|Hexagon|Ryzen AI"


## Rated INT8 TOPS for the first name found in the table, or -1.0 when none is.
static func rated_npu_tops(names: PackedStringArray) -> float:
	for device_name: String in names:
		var cleaned: String = device_name.to_lower().replace("(r)", "").replace("(tm)", "")
		for pattern: String in NPU_TOPS:
			if RegEx.create_from_string(pattern).search(cleaned) != null:
				return NPU_TOPS[pattern]
	return -1.0


## Dense INT8 TOPS for an NVIDIA Ada GPU at the given clock, or -1.0 when the GPU is not in the table.
static func ada_gpu_tops(gpu_name: String, clock_mhz: float) -> float:
	var lowered: String = gpu_name.to_lower()
	for key: String in ADA_SMS:
		if key in lowered:
			return ADA_SMS[key] * clock_mhz * 1e6 * INT8_OPS_PER_SM_PER_CLOCK / 1e12
	return -1.0


## Names of the NPUs present. Every Apple silicon Mac has a Neural Engine; Windows lists them in PnP.
static func npu_devices() -> PackedStringArray:
	var cpu: String = OS.get_processor_name()
	if OS.get_name() == "macOS":
		return PackedStringArray([cpu + " Neural Engine"]) if cpu.begins_with("Apple M") else PackedStringArray()
	if OS.get_name() != "Windows":
		return PackedStringArray()
	var output: Array = []
	var command: String = ("Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -cmatch '%s' -or $_.Class -eq 'ComputeAccelerator' } | ForEach-Object { $_.FriendlyName }" % NPU_PATTERN)
	OS.execute("powershell", ["-NoProfile", "-Command", command], output)
	var found: PackedStringArray = PackedStringArray()
	for line: String in "".join(output).split("\n", false):
		if not line.strip_edges().is_empty():
			found.append(line.strip_edges())
	return found


## [name, max SM clock in MHz] for the first NVIDIA GPU, or an empty array when nvidia-smi is absent.
static func nvidia_gpu() -> Array:
	var output: Array = []
	var code: int = OS.execute("nvidia-smi", ["--query-gpu=name,clocks.max.sm", "--format=csv,noheader,nounits"], output)
	if code != 0 or output.is_empty():
		return []
	var parts: PackedStringArray = String(output[0]).split("\n", false)[0].split(",")
	if parts.size() < 2:
		return []
	return [parts[0].strip_edges(), parts[1].strip_edges().to_float()]


## Megabytes of memory models can use on each kind of device. An NPU and the CPU share system
## memory; so does a GPU whose own memory is unknown or small (an integrated GPU, or a Mac).
static func memory_budgets(share: float) -> Dictionary:
	var system: float = system_memory_mb()
	var gpu: float = gpu_memory_mb()
	return {"gpu": (gpu if gpu > 0.0 else system) * share, "npu": system * share, "cpu": system * share}


static func system_memory_mb() -> float:
	return float(OS.get_memory_info().get("physical", 0)) / 1048576.0


## Dedicated GPU memory in megabytes, or 0 when the GPU shares system memory or cannot be asked.
static func gpu_memory_mb() -> float:
	var output: Array = []
	if OS.execute("nvidia-smi", ["--query-gpu=memory.total", "--format=csv,noheader,nounits"], output) == 0 and not output.is_empty():
		return String(output[0]).split("\n", false)[0].strip_edges().to_float()
	if OS.get_name() != "Windows":
		return 0.0
	# Other Windows GPUs report their memory in the display adapter class's registry keys.
	var command: String = r"(Get-ItemProperty 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -ErrorAction SilentlyContinue | ForEach-Object { $_.'HardwareInformation.qwMemorySize' } | Measure-Object -Maximum).Maximum"
	output.clear()
	OS.execute("powershell", ["-NoProfile", "-Command", command], output)
	var mb: float = "".join(output).strip_edges().to_float() / 1048576.0
	return mb if mb >= 2048.0 else 0.0


## One line per accelerator, for the pet to say when asked what it runs on.
static func describe() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var npus: PackedStringArray = npu_devices()
	if npus.is_empty():
		lines.append("NPU: none")
	else:
		var tops: float = rated_npu_tops(npus + PackedStringArray([OS.get_processor_name()]))
		lines.append("NPU: %s, %s" % [npus[0], ("%.0f TOPS" % tops) if tops > 0.0 else "TOPS unknown"])
	var gpu: Array = nvidia_gpu()
	if not gpu.is_empty():
		var tops: float = ada_gpu_tops(gpu[0], gpu[1])
		lines.append("GPU: %s, %s" % [gpu[0], ("%.0f TOPS" % tops) if tops > 0.0 else "TOPS unknown"])
	else:
		lines.append("GPU: " + RenderingServer.get_video_adapter_name())
	return "\n".join(lines)
