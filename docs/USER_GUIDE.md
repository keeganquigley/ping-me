# Ping Me — User Guide

Ping Me is a small macOS menu bar app that watches your internet connection and
shows you, at a glance, whether it's healthy. It lives in the menu bar, opens a
compact dashboard, and quietly measures reachability, latency, packet loss, and
live upload/download throughput.

This guide walks you through installing, launching, and getting the most out of
Ping Me.

## What you need

- A Mac running macOS 13 (Ventura) or newer.
- The Swift 6 toolchain, available with current Xcode or as a standalone
  install from swift.org. You only need this to build the app from source.

No special permissions, account, or network configuration are required to use
Ping Me. It does not create a login item, does not send data anywhere, and does
not require administrator privileges.

## Installing and launching

Ping Me is distributed as source code. From a Terminal window, change into the
project folder and run:

```bash
swift run
```

The first run will compile the app (this can take a minute or two) and then
launch it. After that, subsequent launches with `swift run` are fast.

When the app starts, two things happen at once:

1. A dashboard window titled "Ping Me" appears, roughly 420×620 pixels.
2. A Wi‑Fi icon appears in the macOS menu bar. Clicking that icon opens the
   same dashboard as a popover, so you can check on the connection without
   keeping the window visible.

Ping Me runs as an "accessory" app — it does not show a Dock icon and does not
appear in Command‑Tab. To quit it, close the Terminal where you ran
`swift run`, or press Ctrl‑C in that Terminal.

## The menu bar icon

The shape of the menu bar icon reflects the current connection status:

- A plain Wi‑Fi icon means the app is **idle** or **online**.
- A Wi‑Fi icon with an exclamation mark means the connection is **degraded**.
- A Wi‑Fi icon with a slash means the connection is **offline**.

Clicking the icon opens the dashboard popover. Everything you can do in the
main window you can also do from this popover.

## The dashboard, card by card

The dashboard is organized as a vertical stack of cards. You can scroll if
your display is small.

### Header and status badge

The header shows the app name and a coloured status pill in the top right. The
badge reads:

- **Idle** (gray) — monitoring is not running. No probes are being sent.
- **Online** (green) — the most recent probe succeeded.
- **Degraded** (orange) — monitoring is running, but the latest probe failed
  and there have not yet been three failures in a row. Ping Me also shows
  Degraded briefly when you first start monitoring, before the first probe
  returns.
- **Offline** (red) — either macOS reports no network path at all, or three
  consecutive probes have failed.

### Monitor

Below the header is a single large button. It says **Check Connection** when
monitoring is stopped and turns into a red **Stop** button while monitoring is
active. To the right of the word "Monitor" is the interface macOS is currently
using for internet traffic — for example Wi‑Fi, Ethernet, or Cellular.

Press Check Connection to start. Ping Me immediately sends its first probe and
then keeps probing on the interval you set (see Settings).

### Latency (recent)

This card plots the round‑trip latency of the last 30 successful probes as a
smooth blue line. Vertical red shading marks points in time where a probe
failed. If there are no probes yet, the card shows "No probes yet" instead of
an empty chart.

### Metrics

Ping Me exposes the numbers it computes from the probe history. All values
reset when you clear history or stop and restart monitoring.

- **Success rate** — percentage of probes that got a reply.
- **Packet loss** — the mirror image of success rate.
- **Latest latency** — round‑trip time of the most recent successful probe.
- **Avg / max latency** — average and worst round‑trip time across all
  successful probes in the current history buffer.
- **Jitter** — the average absolute difference between consecutive
  latencies. Lower is steadier; higher means the connection is bouncy, which
  matters for voice and video calls.
- **Rx / Tx** — current download and upload rates on the active interface,
  refreshed each probe cycle. Values are shown in binary units per second
  (KiB/s, MiB/s, and so on).
- **Link state** — whether macOS's own path monitor considers the network
  usable.
- **Low data mode** — whether the active network has Low Data Mode turned on.
- **Expensive** — whether macOS flags the network as expensive (for example,
  a tethered cellular connection).
- **Monitoring for** — how long the current monitoring session has been
  running.
- **Offline for** — how long the connection has been down. Only shown while
  status is Degraded or Offline and there has been at least one prior
  success.

### Settings

- **Ping host** — the hostname Ping Me sends probes to. The default is
  `google.com`. Type a new host and press Enter or click **Apply**. If the
  host is unusable, a red message appears below the field and the previous
  host is kept. Hosts can contain letters, digits, dots, hyphens, and colons,
  must be at most 253 characters long, may not start with a hyphen, and must
  contain at least one letter or digit.
- **Public internet hosts only** — a safety toggle that is on by default.
  When on, Ping Me refuses to probe addresses that resolve to private ranges.
  That includes RFC1918 private IPv4 (10.x, 172.16–31.x, 192.168.x),
  loopback (127.x and ::1), link‑local (169.254.x and fe80::/10),
  carrier‑grade NAT (100.64–127.x), multicast, IPv6 unique‑local addresses
  (fc00::/7), and similar. Turn this off only if you deliberately want to
  probe a host inside your own network.
- **Probe interval** — how often Ping Me sends a probe, in whole seconds.
  Use the stepper to change it. The allowed range is 1 to 60 seconds.
  Shorter intervals give a more responsive chart and faster detection; longer
  intervals are easier on the network and on battery.

### Clear History / Copy Diagnostics

A small row of text buttons sits between the settings and the captive portal
section.

- **Clear History** throws away the probe history and metrics for the
  current session. Monitoring keeps running if it was running.
- **Copy Diagnostics** opens a confirmation dialog before it writes anything
  to the clipboard. If you confirm, Ping Me copies a redacted diagnostics
  report — the target host and per‑probe detail strings are replaced with
  `<redacted>`, and only the last 12 probes are included. The report contains
  status, interface name, success rate, latest latency, Rx/Tx, and similar
  high‑level numbers. The confirmation dialog reminds you that anything on
  the clipboard can be read by other apps, so only paste the report
  somewhere you trust.

### Captive Portal

Public Wi‑Fi networks usually require you to agree to a splash page before
they let real traffic through. Sometimes that splash page fails to pop up — it
got dismissed, the browser is confused, or the usual trigger page is cached.
Ping Me gives you two buttons to force the issue without disconnecting from
the network.

- **Open Captive Portal Login** opens
  `http://captive.apple.com/hotspot-detect.html` in your default browser.
  That is the URL macOS itself uses to check for captive portals, so hitting
  it often makes the network's splash page appear. If for some reason it
  cannot be opened, Ping Me falls back to `http://neverssl.com/`.
- **No redirect? Try alternate trigger** opens `http://1.1.1.1/`, falling
  back to `http://8.8.8.8/`. These are plain HTTP addresses that some captive
  portals will intercept when the Apple check URL is already cached.

Both actions are harmless — they just load a web page in your browser. They
will not disconnect you from the network or forget it.

### Open Google Speed Test

A text link at the bottom opens a Google search for "internet speed test",
which offers Google's built‑in speed test at the top of the results. Handy
when you want to measure throughput against something heavier than a
one‑packet ping.

## Tips and troubleshooting

**Latency jumps around a lot.** Your Wi‑Fi is probably congested or weak. Try
moving closer to the access point, or watch the jitter value — a high jitter
number confirms an unsteady link.

**Status stays Degraded forever.** Check that the ping host is reachable from
your machine (try `ping google.com` in Terminal). If you changed the ping
host and something looks off, set it back to `google.com` and try again.

**Probes are blocked by host policy.** You either entered a private address
(for example `192.168.1.1`) or the hostname resolves to one, and the
"Public internet hosts only" toggle is on. Turn it off in Settings if that is
intentional, or switch to a public host.

**The Copy Diagnostics dialog seems alarming.** It is conservative on
purpose. Any clipboard content can be read by other applications on your Mac;
Ping Me redacts the target host and per‑probe details before copying, but
the numbers themselves still describe your connection. Paste into a trusted
document or bug report.

**I can't get to the captive portal splash page.** Use **Open Captive Portal
Login** first. If nothing happens, try **No redirect? Try alternate
trigger**. If that still does not work, forget the network in System
Settings › Wi‑Fi and rejoin it.

**The menu bar icon never changes.** You probably have not pressed Check
Connection yet. The icon reflects the current monitoring status, and that
stays Idle until the first probe runs.

**I want to quit the app.** Close the Terminal window running `swift run`,
or press Ctrl‑C there.

## What Ping Me does not do

To set expectations:

- It does not run continuously in the background after you quit. It is a
  foreground accessory app tied to the `swift run` process.
- It does not test bandwidth the way a speed test does. The Rx/Tx metrics
  report whatever your machine is already sending and receiving, not a
  measured maximum. Use the Google Speed Test link for that.
- It does not change any network settings, and it does not send your data
  anywhere. All measurements stay on your machine.

## Glossary

- **Probe** — a single ping sent to the target host.
- **Latency** — the round‑trip time for a probe, in milliseconds.
- **Jitter** — the average difference between consecutive latencies.
- **Packet loss** — the percentage of probes that did not get a reply.
- **Path** — macOS's view of whether the network is usable right now, shown
  in the Link state row.
