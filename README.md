# Ping Me 🎯
Ping Me is a lightweight macOS menu bar app for monitoring internet connection health in real time.
It gives a quick dashboard for reachability, latency trends, packet loss, and live RX/TX throughput.

## Highlights
- Menu bar status icon with quick dashboard access
- One-click connection monitoring with periodic ping probes
- Recent latency chart and success/failure history
- Metrics for packet loss, jitter, average/max latency, and transfer rates
- Diagnostics export with redacted clipboard copy flow
- Safer host controls:
  - strict host input validation
  - optional **Public internet hosts only** policy (default on)

## Requirements
- macOS 13+
- Swift 6 toolchain

## Run locally
```bash
swift run
```

The app opens a dashboard window at launch and also stays available from the macOS menu bar.

## Run unit tests
```bash
swift test
```

## Why I wrote this app
I travel for work a lot and wanted an easy way to measure public wifi quality.

---
Built with Codex (with help from Oz in Warp).
