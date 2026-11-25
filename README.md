# Uncertain Pomodoro

A macOS menu-bar focus timer that **doesn't tell you how long the session is**.

You set only a maximum (e.g. 30 min). Each session draws a hidden length between a minimum and
your maximum, more likely to end late than early. The menu bar shows a coarse 5-bar hint, never the
exact time. When the hidden end arrives: a sound and a pop-up asking how focused you were (1–5),
then a break of 20 % of the time worked (3–10 min).

**Why:** not knowing how long you have makes you start immediately instead of pacing yourself,
and trains tolerance for ambiguity.

## Features
- Hidden duration from a rising truncated exponential (inverse-CDF sampling, unit-tested)
- 5-bar menu-bar hint in 20 % steps
- Focus rating after every session; break with Pause / Resume / End
- Local session log (JSON Lines) in `~/Library/Application Support/UncertainPomodoro/sessions.jsonl`
- No network, no dependencies, no Dock icon

## Build & run
Requires macOS 13+ and Swift 5.9 (Xcode or Command Line Tools).

```bash
swift build -c release
.build/release/UncertainPomodoro
swift test   # sampler and break-policy tests
```

Option-click the menu-bar item for a 2-minute test session.

Design notes: [INTERFACES.md](INTERFACES.md). Feedback and ideas welcome in Issues.

MIT License.
