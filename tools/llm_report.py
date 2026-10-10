"""Turns the phone's model metrics (user://llm_metrics.jsonl) into a Markdown table, one row per setup.

    adb exec-out run-as com.kirbycope.duck cat files/llm_metrics.jsonl > llm_metrics.jsonl
    python tools/llm_report.py llm_metrics.jsonl            # the last benchmark
    python tools/llm_report.py llm_metrics.jsonl --run <name>

The columns: the download (MB, seconds, MB/s), the warm-up from download to ready, the first answer
after a start (seconds to its first word, to its first whole sentence, to its end), the warmed-up
answers averaged the same way, the decode speed in tokens a second (LiteRT-LM's own count where it
gives one), LiteRT-LM's prefill speed, the app's peak memory, and the hottest the battery got.
"""
import argparse
import json
import sys


def mean(rows, key):
    values = [float(r[key]) for r in rows if key in r]
    return sum(values) / len(values) if values else None


def cell(value, form="{:.2f}"):
    return "" if value is None else form.format(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("metrics")
    parser.add_argument("--run", default="")
    args = parser.parse_args()
    entries = []
    with open(args.metrics, encoding="utf-8") as f:
        for line in f:
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    runs = [e["run"] for e in entries if e.get("kind") == "bench"]
    run = args.run or (runs[-1] if runs else "")
    if not run:
        sys.exit("no benchmark in %s" % args.metrics)
    bench = next(e for e in entries if e.get("kind") == "bench" and e.get("run") == run)
    order, by_setup = [], {}
    for e in entries:
        if e.get("run") != run or e.get("kind") == "bench":
            continue
        if "setup" not in e:
            continue
        if e["setup"] not in by_setup:
            order.append(e["setup"])
        # Tried again after the run was cut short: only the last try counts.
        if e["setup"] not in by_setup or e["kind"] == "cleared":
            by_setup[e["setup"]] = []
        by_setup[e["setup"]].append(e)
    device = bench.get("device", {})
    print("Benchmark %s on %s (%s, Android %s)\n" % (run, device.get("model", "?"), device.get("soc", "?"), device.get("android", "?")))
    print("| Setup | Download MB | s | MB/s | Warm-up s | 1st: word s | 1st: talking s | 1st: whole s | Later: word s | Later: talking s | Later: whole s | Decode tok/s | Prefill tok/s | Peak MB | Battery C | Result |")
    print("| --- |" + " ---: |" * 14 + " --- |")
    for setup in order:
        rows = by_setup[setup]
        label = next((r["label"] for r in rows if "label" in r), setup)
        download = next((r for r in rows if r["kind"] == "download"), {})
        load = next((r for r in rows if r["kind"] == "load"), {})
        answers = [r for r in rows if r["kind"] == "answer"]
        first = [r for r in answers if r.get("turn") == 1]
        later = [r for r in answers if r.get("turn", 0) > 1]
        failed = [r["why"] for r in rows if r["kind"] == "failed"]
        # The "cleared" line still carries the setup before's memory and heat.
        own = [r for r in rows if r["kind"] != "cleared"]
        peak = max((int(r.get("pss_mb", 0)) for r in own), default=0)
        hottest = max((float(r.get("battery_c", 0)) for r in own), default=0)
        print("| %s | " % label + " | ".join([
            cell(download.get("mb"), "{:.0f}"), cell(download.get("seconds"), "{:.0f}"), cell(download.get("mb_per_s"), "{:.1f}"),
            cell(load.get("seconds"), "{:.1f}"),
            cell(mean(first, "first_word_s")), cell(mean(first, "first_sentence_s")), cell(mean(first, "total_s"), "{:.1f}"),
            cell(mean(later, "first_word_s")), cell(mean(later, "first_sentence_s")), cell(mean(later, "total_s"), "{:.1f}"),
            cell(mean(answers, "decode_tps"), "{:.1f}"), cell(mean(answers, "prefill_tps"), "{:.0f}"),
            cell(peak or None, "{:.0f}"), cell(hottest or None, "{:.1f}"),
            ("failed: " + failed[0]) if failed else "%d answers" % len(answers),
        ]) + " |")


if __name__ == "__main__":
    main()
