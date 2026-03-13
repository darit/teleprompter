import AppKit

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var state: TeleprompterState?

    private init() {}

    func start(state: TeleprompterState) {
        self.state = state
        stop()

        // Global monitor: fires when app is NOT focused (e.g. PowerPoint is in front)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: fires when app IS focused (teleprompter window is key)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // consume the event
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let state else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmdShift = flags == [.command, .shift]

        guard isCmdShift else { return false }

        switch event.keyCode {
        case 17: // T
            TeleprompterWindowController.shared.toggle()
        case 35: // P
            state.togglePlayPause()
        case 126: // Up arrow
            state.increaseSpeed()
        case 125: // Down arrow
            state.decreaseSpeed()
        case 123: // Left arrow
            state.jumpBackward()
        case 124: // Right arrow
            state.jumpForward()
        case 24: // + (equals key)
            state.increaseFontSize()
        case 27: // - (minus key)
            state.decreaseFontSize()
        case 37: // L
            state.toggleClickThrough()
            TeleprompterWindowController.shared.updateClickThrough()
        case 33: // [
            state.decreaseOpacity()
            TeleprompterWindowController.shared.updateOpacity()
        case 30: // ]
            state.increaseOpacity()
            TeleprompterWindowController.shared.updateOpacity()
        default:
            return false
        }
        return true
    }
}
