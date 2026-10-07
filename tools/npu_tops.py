"""Report the NPU (if any) in this system and its rated INT8 TOPS.

Windows exposes no TOPS counter, so this finds NPU devices through PnP, matches the
name against known rated figures, and lists which ONNX Runtime NPU providers are installed.
"""
import json
import platform
import re
import subprocess

# Regex over the lower-cased device/CPU name with (R) and (TM) removed, and its rated INT8 TOPS.
# First match wins. The same table is in scripts/hardware.gd.
KNOWN_NPUS: list[tuple[str, float]] = [
    (r"snapdragon x|hexagon", 45),
    (r"core ultra [3579] 2\d\dv\b", 48),  # Lunar Lake
    (r"core ultra [3579] 2\d\d", 13),  # Arrow Lake
    (r"core ultra [3579] 1\d\d", 11),  # Meteor Lake
    (r"ryzen ai", 50),  # Strix Point, Krackan, Strix Halo
    (r"ryzen [3579] 8\d\d\d", 16),  # Hawk Point
    (r"ryzen [3579] 7\d40", 10),  # Phoenix
    (r"apple m4", 38), (r"apple m3", 18), (r"apple m2", 15.8), (r"apple m1", 11),
]


def ps(command: str) -> str:
    result = subprocess.run(["powershell", "-NoProfile", "-Command", command],
                            capture_output=True, text=True, timeout=60)
    return result.stdout.strip()


def find_npu_devices() -> list[str]:
    out = ps("Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -cmatch "
             "'\\bNPU\\b|AI Boost|Neural|XDNA|Hexagon|Ryzen AI' -or $_.Class -eq 'ComputeAccelerator' } "
             "| Select-Object -ExpandProperty FriendlyName | ConvertTo-Json")
    if not out:
        return []
    data = json.loads(out)
    return [data] if isinstance(data, str) else data


def cpu_name() -> str:
    return ps("(Get-CimInstance Win32_Processor).Name") or platform.processor()


def rated_tops(names: list[str]) -> float | None:
    for name in names:
        cleaned = name.lower().replace("(r)", "").replace("(tm)", "")
        for pattern, tops in KNOWN_NPUS:
            if re.search(pattern, cleaned):
                return tops
    return None


def ort_providers() -> list[str]:
    try:
        import onnxruntime
        return onnxruntime.get_available_providers()
    except ImportError:
        return []


# Ada Lovelace (RTX 40 series) streaming multiprocessor counts
ADA_SMS: dict[str, int] = {
    "4090 laptop": 76, "4080 laptop": 58, "4070 laptop": 36, "4060 laptop": 24, "4050 laptop": 20,
    "4090": 128, "4080 super": 80, "4080": 76, "4070 ti super": 66, "4070 ti": 60,
    "4070 super": 56, "4070": 46, "4060 ti": 34, "4060": 24,
}
INT8_OPS_PER_SM_PER_CLOCK: int = 2048  # Ada tensor cores, dense; sparsity doubles it


def gpu_tops() -> None:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=name,clocks.max.sm", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        out = ""
    if not out:
        print("GPU: no NVIDIA GPU found via nvidia-smi")
        return
    for line in out.splitlines():
        name, clock = [part.strip() for part in line.split(",")]
        sms = next((n for key, n in ADA_SMS.items() if key in name.lower()), None)
        if sms is None:
            print(f"GPU: {name} (not in the Ada table, check the NVIDIA spec sheet)")
            continue
        dense = sms * float(clock) * 1e6 * INT8_OPS_PER_SM_PER_CLOCK / 1e12
        print(f"GPU: {name}, {sms} SMs at {clock} MHz max")
        print(f"GPU INT8 tensor: about {dense:.0f} TOPS dense, {dense * 2:.0f} TOPS with sparsity "
              f"(NVIDIA's 'AI TOPS' figure)")


def main() -> None:
    gpu_tops()
    cpu = cpu_name()
    devices = find_npu_devices()
    providers = ort_providers()
    print(f"CPU: {cpu}")
    print(f"NPU devices found: {devices if devices else 'none'}")
    print(f"ONNX Runtime providers: {providers if providers else 'onnxruntime not installed'}")
    npu_providers = [p for p in providers if p in ("QNNExecutionProvider", "OpenVINOExecutionProvider",
                                                   "VitisAIExecutionProvider")]
    if not devices:
        print("Result: no NPU detected, so 0 NPU TOPS.")
        return
    tops = rated_tops(devices + [cpu])
    if tops is None:
        print("Result: NPU present but not in the rated table; check the vendor spec sheet.")
    else:
        print(f"Result: about {tops} INT8 TOPS (vendor rated peak, from the table).")
    print(f"NPU-capable ONNX providers installed: {npu_providers if npu_providers else 'none'}")


if __name__ == "__main__":
    main()
