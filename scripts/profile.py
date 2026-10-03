#!/usr/bin/env python3
"""Read-only CPU/RSS sample of Halo and its child processes. No UI or media data."""
import argparse
import json
import subprocess
import time


def cpu_seconds(value):
    total = 0.0
    for component in value.split(":"):
        total = total * 60 + float(component)
    return total


def snapshot(root):
    output = subprocess.check_output(
        ["ps", "-axo", "pid=,ppid=,time=,rss="], text=True, timeout=10
    )
    processes = {}
    for line in output.splitlines():
        pid, parent, cpu, rss = line.split()
        processes[int(pid)] = (int(parent), cpu_seconds(cpu), int(rss))
    if root not in processes:
        raise RuntimeError("Halo exited during the sample")
    selected = {root}
    while True:
        children = {pid for pid, row in processes.items() if row[0] in selected}
        if children <= selected:
            break
        selected |= children
    return {pid: processes[pid] for pid in selected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True, help="Running Halo process ID")
    parser.add_argument("--seconds", type=int, default=30, choices=range(5, 301), metavar="5..300")
    parser.add_argument("--label", default="idle")
    args = parser.parse_args()
    initial = previous = snapshot(args.pid)
    peak_rss = sum(row[2] for row in previous.values())
    cpu = {pid: 0.0 for pid in initial}
    observed = set(initial)
    started = time.monotonic()
    while time.monotonic() - started < args.seconds:
        time.sleep(min(1, max(0, args.seconds - (time.monotonic() - started))))
        current = snapshot(args.pid)
        for pid, row in current.items():
            # Include all CPU time of children launched during this sample.
            baseline = previous[pid][1] if pid in previous else (row[1] if pid in observed else 0)
            cpu[pid] = cpu.get(pid, 0) + max(0, row[1] - baseline)
        observed.update(current)
        peak_rss = max(peak_rss, sum(row[2] for row in current.values()))
        previous = current
    elapsed = time.monotonic() - started
    print(json.dumps({
        "label": args.label,
        "seconds": round(elapsed, 2),
        "processes_seen": len(observed),
        "cpu_percent_one_core": round(sum(cpu.values()) / elapsed * 100, 3),
        "app_cpu_percent_one_core": round(cpu[args.pid] / elapsed * 100, 3),
        "peak_combined_rss_mib": round(peak_rss / 1024, 2),
        "final_app_rss_mib": round(previous[args.pid][2] / 1024, 2),
        "note": "RSS includes shared pages; this is a short sample, not an energy benchmark.",
    }, indent=2))


if __name__ == "__main__":
    main()
