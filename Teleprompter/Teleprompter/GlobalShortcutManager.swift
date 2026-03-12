import AppKit

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var monitor: Any?
    private weak var state: TeleprompterState?

    private init() {}

    func start(state: TeleprompterState) {
        self.state = state
        stop()

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard let state else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmdShift = flags == [.command, .shift]

        guard isCmdShift else { return }

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
            break
        }
    }
}
