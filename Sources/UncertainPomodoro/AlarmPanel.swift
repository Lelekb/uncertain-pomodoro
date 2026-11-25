import AppKit

@MainActor
final class AlarmPanel: NSObject, NSWindowDelegate {
    // NSWindow's delegate and NSControl's target do not retain their receivers.
    private static var visiblePanels: [AlarmPanel] = []
    private let panel: NSPanel
    private var completion: ((Int?) -> Void)?

    static func show(workedSeconds: TimeInterval, completion: @escaping (Int?) -> Void) {
        let controller = AlarmPanel(workedSeconds: workedSeconds, completion: completion)
        visiblePanels.append(controller)
        controller.panel.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.panel.makeKeyAndOrderFront(nil)
    }

    private init(workedSeconds: TimeInterval, completion: @escaping (Int?) -> Void) {
        self.completion = completion
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 150),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Time's up"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let minutes = Int(max(0, workedSeconds) / 60)
        let label = NSTextField(wrappingLabelWithString:
            "You worked \(minutes) min. How focused were you?")
        label.frame = NSRect(x: 24, y: 85, width: 342, height: 40)
        panel.contentView?.addSubview(label)

        for rating in 1...5 {
            let button = NSButton(title: String(rating), target: self, action: #selector(rate(_:)))
            button.tag = rating
            button.bezelStyle = .rounded
            button.frame = NSRect(x: 20 + (rating - 1) * 49, y: 25, width: 46, height: 32)
            panel.contentView?.addSubview(button)
        }
        let skip = NSButton(title: "Skip", target: self, action: #selector(skipRating))
        skip.bezelStyle = .rounded
        skip.keyEquivalent = "\u{1b}"
        skip.frame = NSRect(x: 285, y: 25, width: 80, height: 32)
        panel.contentView?.addSubview(skip)
    }

    @objc private func rate(_ sender: NSButton) {
        finish(rating: sender.tag)
    }

    @objc private func skipRating() {
        finish(rating: nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(rating: nil, closePanel: false)
    }

    private func finish(rating: Int?, closePanel: Bool = true) {
        guard let callback = completion else { return }
        completion = nil
        callback(rating)
        if closePanel { panel.close() }
        Self.visiblePanels.removeAll { $0 === self }
    }
}

@MainActor
final class BreakOverPanel: NSObject, NSWindowDelegate {
    // NSWindow's delegate and NSControl's target do not retain their receivers.
    private static var visiblePanels: [BreakOverPanel] = []
    private let panel: NSPanel
    private var completion: ((Bool) -> Void)?

    static func show(maxMinutes: Int, completion: @escaping (Bool) -> Void) {
        let controller = BreakOverPanel(maxMinutes: maxMinutes, completion: completion)
        visiblePanels.append(controller)
        controller.panel.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.panel.makeKeyAndOrderFront(nil)
    }

    private init(maxMinutes: Int, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 150),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Break over"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let label = NSTextField(wrappingLabelWithString:
            "Break's over. Start the next session?")
        label.frame = NSRect(x: 24, y: 85, width: 342, height: 40)
        panel.contentView?.addSubview(label)

        let start = NSButton(title: "Start (max \(maxMinutes) min)",
                             target: self, action: #selector(startSession))
        start.bezelStyle = .rounded
        start.frame = NSRect(x: 20, y: 25, width: 240, height: 32)
        panel.contentView?.addSubview(start)

        let notNow = NSButton(title: "Not now", target: self, action: #selector(decline))
        notNow.bezelStyle = .rounded
        notNow.keyEquivalent = "\u{1b}"
        notNow.frame = NSRect(x: 275, y: 25, width: 90, height: 32)
        panel.contentView?.addSubview(notNow)
    }

    @objc private func startSession() {
        finish(start: true)
    }

    @objc private func decline() {
        finish(start: false)
    }

    func windowWillClose(_ notification: Notification) {
        finish(start: false, closePanel: false)
    }

    private func finish(start: Bool, closePanel: Bool = true) {
        guard let callback = completion else { return }
        completion = nil
        callback(start)
        if closePanel { panel.close() }
        Self.visiblePanels.removeAll { $0 === self }
    }
}
