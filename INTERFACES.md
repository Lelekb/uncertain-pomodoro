# Uncertain Pomodoro v1: interfaces (contract for all workers)

macOS 13+, Swift 5.9, SwiftPM, AppKit only. No third-party dependencies. Menu-bar only app (no Dock icon).

## Concept
The user sets a MAX session length (e.g. 30 or 60 min). At session start the app draws a hidden
duration in [min, max] from a truncated exponential that RISES toward max (end more likely late).
The menu bar shows 10 segments filling with elapsed/max, colour green -> red. At the hidden end:
sound + a floating pop-up asking for a 1-5 focus rating, then a fixed break. Every session is logged.

## Module PomodoroCore (pure Swift + Foundation, testable; NO AppKit here)

### Sampler.swift
```swift
public struct SessionSampler {
    public var minMinutes: Double      // default 10
    public var maxMinutes: Double      // user setting, default 30
    public var steepness: Double       // lambda >= 0; 0 = uniform; default 2.0
    public init(minMinutes: Double = 10, maxMinutes: Double = 30, steepness: Double = 2.0)
    /// Draw a duration in seconds in [min, max]. pdf(x) ∝ exp(steepness * x) on x = (t-min)/(max-min) ∈ [0,1].
    /// Inverse CDF: x = ln(1 + u*(e^λ - 1)) / λ  (λ>0); x = u for λ≈0. If max <= min, return max.
    public func draw(u: Double) -> TimeInterval          // u ∈ [0,1), deterministic, for tests
    public func draw() -> TimeInterval                    // uses SystemRandomNumberGenerator
}
public enum BreakPolicy {
    /// 20 % of worked seconds, clamped to [3, 10] minutes, rounded to whole minutes.
    public static func breakDuration(worked: TimeInterval) -> TimeInterval
}
```

### SessionLog.swift
```swift
public struct SessionRecord: Codable, Equatable {
    public var start: Date
    public var maxMinutes: Double
    public var minMinutes: Double
    public var steepness: Double
    public var plannedSeconds: TimeInterval   // the hidden draw (written only after the session ends)
    public var workedSeconds: TimeInterval    // actual (less than planned if stopped early)
    public var endedBy: String                // "alarm" | "stopped"
    public var focusRating: Int?              // 1...5, nil if skipped
    public var breakSeconds: TimeInterval
    public var negotiated: Bool               // always false in v1
}
public final class SessionLog {
    public init(fileURL: URL)                                  // JSON Lines, one record per line, append-only
    public static func defaultURL() -> URL                     // ~/Library/Application Support/UncertainPomodoro/sessions.jsonl (creates dir)
    public func append(_ record: SessionRecord) throws         // ISO-8601 dates
    public func readAll() throws -> [SessionRecord]            // skips malformed lines
}
```

## Module UncertainPomodoro (executable, AppKit)

### BarRenderer.swift
```swift
import AppKit
enum BarRenderer {
    /// 10 rounded segments, total ~ 64x14 pt, for NSStatusItem.button.image (isTemplate = false).
    /// fraction ∈ [0,1] = elapsed/max. Filled segments: colour interpolated green(#34C759) -> amber(#FF9F0A) -> red(#FF3B30)
    /// by the segment's position (later segments redder); the partially-filled segment is filled proportionally.
    /// Unfilled segments: secondary label colour at 25 % alpha. mode .break draws all segments in blue (#0A84FF) filling with break progress.
    static func image(fraction: Double, mode: BarMode) -> NSImage
}
enum BarMode { case idle, work, breakTime }
```
Idle = all segments unfilled.

### AppDelegate.swift + main.swift
- `main.swift`: NSApplication.shared, setActivationPolicy(.accessory), delegate = AppDelegate(), run.
- Status item shows BarRenderer image; tick every 2 s via Timer (RunLoop .common).
- Menu: "Start 30 min max", "Start 45 min max", "Start 60 min max", "Stop", separator, "Settings…" (min minutes, steepness via a small NSAlert with text fields; persisted in UserDefaults keys `minMinutes`, `steepness`, `lastMax`), "Open log folder", "Quit".
- Never reveal the drawn duration (no tooltip, no menu text). Menu item title while running: "Working… (max N min)".
- At hidden end: NSSound(named: "Glass")?.play(); show AlarmPanel; on rating -> append SessionRecord, start break (bar .breakTime), at break end play "Tink" and go idle.
- "Stop" during work: log with endedBy "stopped", focusRating nil, no break.

### AlarmPanel.swift
```swift
import AppKit
final class AlarmPanel {
    /// Floating NSPanel (level .floating, joins all spaces, centered), title "Time's up",
    /// text "You worked X min. How focused were you?", five buttons 1…5 and "Skip".
    /// Activates the app so it appears in front. Calls completion exactly once, then closes.
    static func show(workedSeconds: TimeInterval, completion: @escaping (Int?) -> Void)
}
```
