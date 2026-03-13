import AppKit
import SwiftUI

final class TeleprompterWindowController {
    static let shared = TeleprompterWindowController()

    private var panel: NSPanel?
    private var state: TeleprompterState?

    private init() {}

    func show(state: TeleprompterState) {
        self.state = state

        if let existing = panel {
            existing.orderFront(nil)
            return
        }

        let contentView = TeleprompterContentView(state: state)
        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )

        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.level = .floating
        panel.sharingType = .none
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position: top center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 350
            let y = screenFrame.maxY - 320
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else if let state {
            show(state: state)
        }
    }

    func close() {
        // Stop playback before closing to avoid timer callbacks during teardown
        state?.isPlaying = false
        let panelToClose = panel
        panel = nil
        state = nil
        // Defer actual close to avoid CoreAnimation commit conflicts
        DispatchQueue.main.async {
            panelToClose?.orderOut(nil)
            panelToClose?.close()
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Click-through

    func updateClickThrough() {
        guard let state else { return }
        panel?.ignoresMouseEvents = state.isClickThrough
    }

    // MARK: - Opacity

    func updateOpacity() {
        guard let state else { return }
        panel?.alphaValue = state.opacity
    }
}
