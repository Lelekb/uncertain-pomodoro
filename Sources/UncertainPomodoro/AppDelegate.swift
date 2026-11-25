import AppKit
import PomodoroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct WorkSession {
        let start: Date
        let uptime: TimeInterval
        let sampler: SessionSampler
        let plannedSeconds: TimeInterval
        var isTest = false

        var elapsed: TimeInterval { max(0, ProcessInfo.processInfo.systemUptime - uptime) }
    }

    private struct BreakSession {
        var start: TimeInterval
        let duration: TimeInterval
        var pausedAt: TimeInterval?

        var elapsed: TimeInterval {
            max(0, (pausedAt ?? ProcessInfo.processInfo.systemUptime) - start)
        }
    }

    private enum State {
        case idle
        case work(WorkSession)
        case alarm(WorkSession, worked: TimeInterval)
        case breakTime(BreakSession)
    }

    private var state: State = .idle
    private var statusItem: NSStatusItem!
    private var startItems: [NSMenuItem] = []
    private var testItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var breakTitleItem: NSMenuItem!
    private var pauseBreakItem: NSMenuItem!
    private var endBreakItem: NSMenuItem!
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private lazy var log = SessionLog(fileURL: SessionLog.defaultURL())

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["minMinutes": 10.0, "steepness": 2.0, "lastMax": 30])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for minutes in [30, 45, 60] {
            let item = NSMenuItem(title: "Start \(minutes) min max",
                                  action: #selector(startWork(_:)), keyEquivalent: "")
            item.tag = minutes
            item.target = self
            menu.addItem(item)
            startItems.append(item)
        }
        testItem = addItem("Test run (2 min, not logged)", action: #selector(startTest), to: menu)
        testItem.isHidden = true
        stopItem = addItem("Stop", action: #selector(stopWork), to: menu)
        breakTitleItem = NSMenuItem(title: "Break", action: nil, keyEquivalent: "")
        breakTitleItem.isEnabled = false
        menu.addItem(breakTitleItem)
        pauseBreakItem = addItem("Pause break", action: #selector(toggleBreakPause), to: menu)
        endBreakItem = addItem("End break", action: #selector(endBreak), to: menu)
        menu.addItem(.separator())
        addItem("Settings…", action: #selector(showSettings), to: menu)
        addItem("Open log folder", action: #selector(openLogFolder), to: menu)
        addItem("Quit", action: #selector(quit), to: menu)
        menu.delegate = self
        statusItem.menu = menu
        refresh()
        let timer = Timer(timeInterval: 2, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The test run is only shown when the menu is opened with Option held.
    func menuWillOpen(_ menu: NSMenu) {
        testItem.isHidden = !NSEvent.modifierFlags.contains(.option)
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Fixed 2-minute session to watch the bars step; no break, nothing logged.
    @objc private func startTest() {
        guard case .idle = state else { return }
        let sampler = SessionSampler(minMinutes: 1, maxMinutes: 2, steepness: 0)
        state = .work(WorkSession(start: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                                  sampler: sampler, plannedSeconds: 120, isTest: true))
        refresh()
    }

    @objc private func startWork(_ sender: NSMenuItem) {
        startSession(maxMinutes: sender.tag)
    }

    private func startSession(maxMinutes: Int) {
        guard case .idle = state else { return }
        let minimum = defaults.double(forKey: "minMinutes")
        let steepness = defaults.double(forKey: "steepness")
        let sampler = SessionSampler(
            minMinutes: minimum.isFinite && minimum > 0 ? minimum : 10,
            maxMinutes: Double(maxMinutes),
            steepness: steepness.isFinite && steepness >= 0 ? steepness : 2)
        defaults.set(maxMinutes, forKey: "lastMax")
        state = .work(WorkSession(start: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                                  sampler: sampler, plannedSeconds: sampler.draw()))
        refresh()
    }

    @objc private func stopWork() {
        guard case let .work(session) = state else { return }
        let worked = session.elapsed
        state = .idle
        if !session.isTest { append(session, worked: worked, endedBy: "stopped", rating: nil, breakSeconds: 0) }
        refresh()
    }

    @objc private func toggleBreakPause() {
        guard case var .breakTime(session) = state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let pausedAt = session.pausedAt {
            session.start += now - pausedAt
            session.pausedAt = nil
        } else {
            session.pausedAt = now
        }
        state = .breakTime(session)
        refresh()
    }

    @objc private func endBreak() {
        guard case .breakTime = state else { return }
        state = .idle
        refresh()
    }

    @objc private func tick() {
        switch state {
        case let .work(session) where session.elapsed >= session.plannedSeconds:
            let worked = session.elapsed
            state = .alarm(session, worked: worked)
            NSSound(named: "Glass")?.play()
            if session.isTest {
                state = .idle
                refresh()
                return
            }
            AlarmPanel.show(workedSeconds: worked) { [weak self] rating in
                guard let self, case .alarm = self.state else { return }
                let duration = BreakPolicy.breakDuration(worked: worked)
                self.state = .breakTime(BreakSession(
                    start: ProcessInfo.processInfo.systemUptime, duration: duration))
                self.append(session, worked: worked, endedBy: "alarm", rating: rating,
                            breakSeconds: duration)
                self.refresh()
            }
        case let .breakTime(session)
            where session.pausedAt == nil && session.elapsed >= session.duration:
            state = .idle
            NSSound(named: "Tink")?.play()
            let maxMinutes = defaults.integer(forKey: "lastMax")
            BreakOverPanel.show(maxMinutes: maxMinutes) { [weak self] start in
                guard start, let self, case .idle = self.state else { return }
                self.startSession(maxMinutes: maxMinutes)
            }
        default:
            break
        }
        refresh()
    }

    private func refresh() {
        let fraction: Double
        let mode: BarMode
        var workingMax: Int?
        var canStart = false
        var canStop = false
        var onBreak = false
        var breakPaused = false
        switch state {
        case .idle:
            fraction = 0
            mode = .idle
            canStart = true
        case let .work(session):
            fraction = session.elapsed / session.plannedSeconds
            mode = .work
            workingMax = Int(session.sampler.maxMinutes)
            canStop = true
        case let .alarm(session, _):
            fraction = 1
            mode = .work
            workingMax = Int(session.sampler.maxMinutes)
        case let .breakTime(session):
            fraction = session.elapsed / session.duration
            mode = .breakTime
            onBreak = true
            breakPaused = session.pausedAt != nil
        }
        statusItem.button?.image = BarRenderer.image(fraction: fraction, mode: mode)
        for item in startItems {
            item.title = item.tag == workingMax
                ? "Working… (max \(item.tag) min)" : "Start \(item.tag) min max"
            item.isEnabled = canStart
            testItem.isEnabled = canStart
            item.state = item.tag == defaults.integer(forKey: "lastMax") ? .on : .off
        }
        stopItem.isEnabled = canStop
        breakTitleItem.isHidden = !onBreak
        breakTitleItem.title = breakPaused ? "Break paused" : "Break"
        pauseBreakItem.isHidden = !onBreak
        pauseBreakItem.isEnabled = onBreak
        pauseBreakItem.title = breakPaused ? "Resume break" : "Pause break"
        endBreakItem.isHidden = !onBreak
        endBreakItem.isEnabled = onBreak
    }

    private func append(_ session: WorkSession, worked: TimeInterval, endedBy: String,
                        rating: Int?, breakSeconds: TimeInterval) {
        let record = SessionRecord(start: session.start, maxMinutes: session.sampler.maxMinutes,
                                   minMinutes: session.sampler.minMinutes,
                                   steepness: session.sampler.steepness,
                                   plannedSeconds: session.plannedSeconds, workedSeconds: worked,
                                   endedBy: endedBy, focusRating: rating,
                                   breakSeconds: breakSeconds, negotiated: false)
        do {
            try log.append(record)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the session log"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func showSettings() {
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "Minimum minutes (greater than 0) and steepness (0 or greater)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 76))
        let minimum = NSTextField(string: String(defaults.double(forKey: "minMinutes")))
        let steepness = NSTextField(string: String(defaults.double(forKey: "steepness")))
        for (index, pair) in [("Min minutes", minimum), ("Steepness", steepness)].enumerated() {
            let y = 44 - index * 36
            let label = NSTextField(labelWithString: pair.0)
            label.frame = NSRect(x: 0, y: y + 3, width: 130, height: 20)
            pair.1.frame = NSRect(x: 140, y: y, width: 130, height: 24)
            view.addSubview(label)
            view.addSubview(pair.1)
        }
        alert.accessoryView = view
        NSApplication.shared.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let minValue = Double(minimum.stringValue), minValue.isFinite,
                  minValue > 0,
                  let steepValue = Double(steepness.stringValue), steepValue.isFinite,
                  steepValue >= 0 else {
                alert.informativeText = "Enter finite values: a minimum greater than 0 and a steepness of 0 or greater."
                continue
            }
            defaults.set(minValue, forKey: "minMinutes")
            defaults.set(steepValue, forKey: "steepness")
            break
        }
    }

    @objc private func openLogFolder() {
        NSWorkspace.shared.open(SessionLog.defaultURL().deletingLastPathComponent())
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        switch state {
        case .work:
            stopWork()
        case let .alarm(session, worked):
            state = .idle
            append(session, worked: worked, endedBy: "alarm", rating: nil, breakSeconds: 0)
        default:
            break
        }
    }
}
