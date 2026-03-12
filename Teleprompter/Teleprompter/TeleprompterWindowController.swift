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
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.level = .floating
        panel.sharingType = .none
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
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

        updateClickThrough()
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
        panel?.close()
        panel = nil
        state = nil
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
