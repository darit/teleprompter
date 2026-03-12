# Teleprompter Plan 3: Floating Teleprompter Window

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a floating, always-on-top teleprompter window that is invisible to screen sharing, with auto-scroll, click-through toggle, playback controls, and global keyboard shortcuts.

**Architecture:** An `NSPanel` subclass creates a floating overlay window with `sharingType = .none`. A `TeleprompterState` observable drives scroll position, playback, speed, and opacity. The SwiftUI content is split into a text zone (scrolling script with faded prev/next context) and a controls zone (always interactive). `NSEvent.addGlobalMonitorForEvents` handles global keyboard shortcuts. The "Present" button in `ScriptDetailView` opens the teleprompter via a `TeleprompterWindowController` singleton.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (NSPanel, NSEvent global monitor)

**Spec:** `docs/superpowers/specs/2026-03-12-teleprompter-design.md` -- View 4

**Depends on:** Plan 1 (Foundation) + Plan 2 (PPTX/LLM) -- completed

**Deferred to later plans:**
- Visual style settings (Glass / Solid / Adaptive)
- Settings view for customization
- Position presets remembered between sessions (UserDefaults persistence)

---

## File Structure

```
Teleprompter/
  Teleprompter/
    Teleprompter/
      TeleprompterState.swift             # Observable state: scroll, playback, speed, opacity
      TeleprompterWindowController.swift  # NSPanel creation, positioning, click-through
      GlobalShortcutManager.swift         # Global keyboard shortcut monitoring
    Views/Teleprompter/
      TeleprompterContentView.swift       # Root view hosted in the NSPanel
      TeleprompterTextView.swift          # Scrolling script text zone
      TeleprompterControlsView.swift      # Playback controls zone
  TeleprompterTests/
    Teleprompter/
      TeleprompterStateTests.swift        # State logic tests
```

---

## Chunk 1: Teleprompter State and Window

### Task 1: TeleprompterState

**Files:**
- Create: `Teleprompter/Teleprompter/Teleprompter/TeleprompterState.swift`
- Create: `Teleprompter/TeleprompterTests/Teleprompter/TeleprompterStateTests.swift`

- [ ] **Step 1: Write tests**

```swift
// TeleprompterTests/Teleprompter/TeleprompterStateTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("TeleprompterState")
struct TeleprompterStateTests {

    @Test("initial state is paused at top")
    func testInitialState() {
        let sections = TeleprompterStateTests.sampleSections()
        let state = TeleprompterState(sections: sections, fontSize: 24, scrollSpeed: 1.0)

        #expect(state.isPlaying == false)
        #expect(state.scrollOffset == 0)
        #expect(state.currentSectionIndex == 0)
        #expect(state.opacity == 1.0)
        #expect(state.isClickThrough == true)
    }

    @Test("play and pause toggle")
    func testPlayPause() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.togglePlayPause()
        #expect(state.isPlaying == true)

        state.togglePlayPause()
        #expect(state.isPlaying == false)
    }

    @Test("jump forward advances section index")
    func testJumpForward() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.jumpForward()
        #expect(state.currentSectionIndex == 1)

        state.jumpForward()
        #expect(state.currentSectionIndex == 2)

        // Should not go past last section
        state.jumpForward()
        #expect(state.currentSectionIndex == 2)
    }

    @Test("jump backward decreases section index")
    func testJumpBackward() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.jumpForward()
        state.jumpForward()
        #expect(state.currentSectionIndex == 2)

        state.jumpBackward()
        #expect(state.currentSectionIndex == 1)

        state.jumpBackward()
        #expect(state.currentSectionIndex == 0)

        // Should not go below 0
        state.jumpBackward()
        #expect(state.currentSectionIndex == 0)
    }

    @Test("speed adjustment clamps to range")
    func testSpeedAdjustment() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.increaseSpeed()
        #expect(state.scrollSpeed == 1.25)

        state.decreaseSpeed()
        #expect(state.scrollSpeed == 1.0)

        // Should not go below minimum
        state.scrollSpeed = 0.25
        state.decreaseSpeed()
        #expect(state.scrollSpeed == 0.25)

        // Should not exceed maximum
        state.scrollSpeed = 3.0
        state.increaseSpeed()
        #expect(state.scrollSpeed == 3.0)
    }

    @Test("opacity clamps to range")
    func testOpacity() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.increaseOpacity()
        #expect(state.opacity == 1.0) // already at max

        state.opacity = 0.5
        state.decreaseOpacity()
        #expect(state.opacity == 0.4)

        state.opacity = 0.2
        state.decreaseOpacity()
        #expect(state.opacity == 0.2) // clamp at min
    }

    @Test("click-through toggle")
    func testClickThrough() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)
        #expect(state.isClickThrough == true)

        state.toggleClickThrough()
        #expect(state.isClickThrough == false)

        state.toggleClickThrough()
        #expect(state.isClickThrough == true)
    }

    @Test("full script text concatenates sections")
    func testFullScriptText() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)
        let text = state.fullScriptText
        #expect(text.contains("Introduction text"))
        #expect(text.contains("Overview text"))
        #expect(text.contains("Conclusion text"))
    }

    @Test("section offsets computed for navigation")
    func testSectionOffsets() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)
        #expect(state.sectionStartIndices.count == 3)
        #expect(state.sectionStartIndices[0] == 0)
    }

    // MARK: - Helpers

    static func sampleSections() -> [TeleprompterSection] {
        [
            TeleprompterSection(slideNumber: 1, label: "Introduction", content: "Introduction text here.", accentColorHex: "#4A9EFF"),
            TeleprompterSection(slideNumber: 2, label: "Overview", content: "Overview text goes here.", accentColorHex: "#34C759"),
            TeleprompterSection(slideNumber: 3, label: "Conclusion", content: "Conclusion text for the end.", accentColorHex: "#FF9500"),
        ]
    }

    func sampleSections() -> [TeleprompterSection] {
        Self.sampleSections()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `TeleprompterState` not defined

- [ ] **Step 3: Implement TeleprompterState**

```swift
// Teleprompter/Teleprompter/TeleprompterState.swift
import Foundation
import Observation

struct TeleprompterSection: Identifiable {
    let id = UUID()
    let slideNumber: Int
    let label: String
    let content: String
    let accentColorHex: String
}

@Observable
final class TeleprompterState {
    let sections: [TeleprompterSection]
    var fontSize: Double
    var scrollSpeed: Double
    var scrollOffset: CGFloat = 0
    var isPlaying = false
    var currentSectionIndex = 0
    var opacity: Double = 1.0
    var isClickThrough = true

    private static let minSpeed: Double = 0.25
    private static let maxSpeed: Double = 3.0
    private static let speedStep: Double = 0.25
    private static let minOpacity: Double = 0.2
    private static let maxOpacity: Double = 1.0
    private static let opacityStep: Double = 0.1

    init(sections: [TeleprompterSection], fontSize: Double, scrollSpeed: Double) {
        self.sections = sections
        self.fontSize = fontSize
        self.scrollSpeed = scrollSpeed
    }

    // MARK: - Playback

    func togglePlayPause() {
        isPlaying.toggle()
    }

    func jumpForward() {
        if currentSectionIndex < sections.count - 1 {
            currentSectionIndex += 1
        }
    }

    func jumpBackward() {
        if currentSectionIndex > 0 {
            currentSectionIndex -= 1
        }
    }

    // MARK: - Speed

    func increaseSpeed() {
        scrollSpeed = min(Self.maxSpeed, scrollSpeed + Self.speedStep)
    }

    func decreaseSpeed() {
        scrollSpeed = max(Self.minSpeed, scrollSpeed - Self.speedStep)
    }

    // MARK: - Opacity

    func increaseOpacity() {
        opacity = min(Self.maxOpacity, opacity + Self.opacityStep)
    }

    func decreaseOpacity() {
        opacity = max(Self.minOpacity, opacity - Self.opacityStep)
    }

    // MARK: - Click-through

    func toggleClickThrough() {
        isClickThrough.toggle()
    }

    // MARK: - Script Content

    var fullScriptText: String {
        sections.map(\.content).joined(separator: "\n\n")
    }

    /// Character index where each section starts in fullScriptText.
    var sectionStartIndices: [Int] {
        var indices: [Int] = []
        var offset = 0
        for (i, section) in sections.enumerated() {
            indices.append(offset)
            offset += section.content.count
            if i < sections.count - 1 {
                offset += 2 // "\n\n" separator
            }
        }
        return indices
    }

    /// Build state from a Script model.
    static func from(script: Script) -> TeleprompterState {
        let teleprompterSections = script.sortedSections.map { section in
            TeleprompterSection(
                slideNumber: section.slideNumber,
                label: section.label,
                content: section.content,
                accentColorHex: section.accentColorHex
            )
        }
        return TeleprompterState(
            sections: teleprompterSections,
            fontSize: script.fontSize,
            scrollSpeed: script.scrollSpeed
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Teleprompter/TeleprompterState.swift Teleprompter/TeleprompterTests/Teleprompter/TeleprompterStateTests.swift
git commit -m "Add TeleprompterState with playback, speed, opacity, and navigation"
```

---

### Task 2: TeleprompterWindowController

**Files:**
- Create: `Teleprompter/Teleprompter/Teleprompter/TeleprompterWindowController.swift`

- [ ] **Step 1: Implement the window controller**

```swift
// Teleprompter/Teleprompter/TeleprompterWindowController.swift
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
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED (note: TeleprompterContentView doesn't exist yet, this will fail -- that's expected, we create a stub)

Create a temporary stub to make it build:

```swift
// This will be replaced in Task 5. For now, just enough to compile.
```

Actually, skip the build verification here -- Task 5 creates the view. Just commit the controller.

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Teleprompter/TeleprompterWindowController.swift
git commit -m "Add TeleprompterWindowController with floating NSPanel"
```

---

### Task 3: GlobalShortcutManager

**Files:**
- Create: `Teleprompter/Teleprompter/Teleprompter/GlobalShortcutManager.swift`

- [ ] **Step 1: Implement global shortcut manager**

```swift
// Teleprompter/Teleprompter/GlobalShortcutManager.swift
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
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Teleprompter/GlobalShortcutManager.swift
git commit -m "Add GlobalShortcutManager for teleprompter keyboard shortcuts"
```

---

## Chunk 2: Teleprompter Views

### Task 4: TeleprompterControlsView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/Teleprompter/TeleprompterControlsView.swift`

- [ ] **Step 1: Implement controls view**

```swift
// Teleprompter/Views/Teleprompter/TeleprompterControlsView.swift
import SwiftUI

struct TeleprompterControlsView: View {
    @Bindable var state: TeleprompterState

    var body: some View {
        HStack(spacing: 16) {
            // Lock toggle
            Button {
                state.toggleClickThrough()
                TeleprompterWindowController.shared.updateClickThrough()
            } label: {
                Image(systemName: state.isClickThrough ? "lock.open" : "lock")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(state.isClickThrough ? "Lock (click-through ON)" : "Unlock (click-through OFF)")

            Divider().frame(height: 20)

            // Transport controls
            HStack(spacing: 12) {
                Button {
                    state.jumpBackward()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Previous section")

                Button {
                    state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(state.isPlaying ? "Pause" : "Play")

                Button {
                    state.jumpForward()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Next section")
            }

            Divider().frame(height: 20)

            // Speed
            HStack(spacing: 4) {
                Button {
                    state.decreaseSpeed()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)

                Text("\(String(format: "%.2g", state.scrollSpeed))x")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 32)

                Button {
                    state.increaseSpeed()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .help("Scroll speed")

            Divider().frame(height: 20)

            // Opacity
            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Slider(value: $state.opacity, in: 0.2...1.0, step: 0.1)
                    .frame(width: 60)
                    .onChange(of: state.opacity) {
                        TeleprompterWindowController.shared.updateOpacity()
                    }
            }
            .help("Window opacity")

            Spacer()

            // Close
            Button {
                TeleprompterWindowController.shared.close()
                GlobalShortcutManager.shared.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close teleprompter")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/Teleprompter/TeleprompterControlsView.swift
git commit -m "Add TeleprompterControlsView with transport and opacity controls"
```

---

### Task 5: TeleprompterTextView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/Teleprompter/TeleprompterTextView.swift`

- [ ] **Step 1: Implement scrolling text view**

```swift
// Teleprompter/Views/Teleprompter/TeleprompterTextView.swift
import SwiftUI

struct TeleprompterTextView: View {
    @Bindable var state: TeleprompterState
    @State private var scrollProxy: ScrollViewProxy?
    @State private var timer: Timer?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(section: section, index: index)
                            .id(index)
                    }

                    // Bottom padding so last section can scroll to top
                    Spacer()
                        .frame(height: 300)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: state.currentSectionIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(newIndex, anchor: .top)
                }
            }
            .onChange(of: state.isPlaying) { _, playing in
                if playing {
                    startAutoScroll()
                } else {
                    stopAutoScroll()
                }
            }
        }
        .onDisappear {
            stopAutoScroll()
        }
    }

    private func sectionView(section: TeleprompterSection, index: Int) -> some View {
        let isCurrent = index == state.currentSectionIndex
        let isPast = index < state.currentSectionIndex

        return VStack(alignment: .leading, spacing: 8) {
            // Slide divider
            if index > 0 {
                HStack(spacing: 8) {
                    SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)
                    Rectangle()
                        .fill(Color(hex: section.accentColorHex)?.opacity(0.2) ?? Color.gray.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            Text(section.content)
                .font(.system(size: state.fontSize))
                .lineSpacing(state.fontSize * 0.5)
                .foregroundStyle(isCurrent ? .primary : (isPast ? .tertiary : .secondary))
                .opacity(isCurrent ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.3), value: state.currentSectionIndex)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        stopAutoScroll()
        // Pixels per second based on speed multiplier
        let baseRate: Double = 30.0
        let interval: TimeInterval = 1.0 / 30.0 // 30 fps

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                guard state.isPlaying else { return }
                let pixelsPerFrame = (baseRate * state.scrollSpeed) * interval
                state.scrollOffset += pixelsPerFrame
            }
        }
    }

    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/Teleprompter/TeleprompterTextView.swift
git commit -m "Add TeleprompterTextView with section-based scrolling"
```

---

### Task 6: TeleprompterContentView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/Teleprompter/TeleprompterContentView.swift`

- [ ] **Step 1: Implement content view**

```swift
// Teleprompter/Views/Teleprompter/TeleprompterContentView.swift
import SwiftUI

struct TeleprompterContentView: View {
    @Bindable var state: TeleprompterState

    var body: some View {
        VStack(spacing: 0) {
            // Current section indicator
            HStack(spacing: 8) {
                if state.currentSectionIndex < state.sections.count {
                    let current = state.sections[state.currentSectionIndex]
                    SlidePillView(slideNumber: current.slideNumber, colorHex: current.accentColorHex)
                    Text(current.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(state.currentSectionIndex + 1) / \(state.sections.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Divider()

            // Text zone
            TeleprompterTextView(state: state)

            Divider()

            // Controls zone (always interactive)
            TeleprompterControlsView(state: state)
        }
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/Teleprompter/TeleprompterContentView.swift
git commit -m "Add TeleprompterContentView combining text and controls zones"
```

---

## Chunk 3: Wiring and Integration

### Task 7: Wire Present Button

**Files:**
- Modify: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptDetailView.swift`
- Modify: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptManagerView.swift`

- [ ] **Step 1: Update ScriptDetailView to accept onPresent callback**

In `ScriptDetailView.swift`:

1. Add `var onPresent: () -> Void = {}` property after the `onRefineWithAI` property
2. Replace `Button("Present") { // Plan 3: launch teleprompter }` with `Button("Present") { onPresent() }`
3. Update the preview: `ScriptDetailView(script: PreviewSampleData.sampleScript(), onRefineWithAI: {}, onPresent: {})`

- [ ] **Step 2: Update ScriptManagerView to launch teleprompter**

In `ScriptManagerView.swift`, pass the `onPresent` callback to `ScriptDetailView`:

```swift
ScriptDetailView(
    script: script,
    onRefineWithAI: { openAssistant(for: script) },
    onPresent: { launchTeleprompter(for: script) }
)
```

Add the `launchTeleprompter` method:

```swift
private func launchTeleprompter(for script: Script) {
    guard !script.sections.isEmpty else { return }
    let state = TeleprompterState.from(script: script)
    TeleprompterWindowController.shared.show(state: state)
    GlobalShortcutManager.shared.start(state: state)
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/ScriptDetailView.swift Teleprompter/Teleprompter/Views/ScriptManager/ScriptManagerView.swift
git commit -m "Wire Present button to launch floating teleprompter window"
```

---

### Task 8: End-to-End Smoke Test

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 2: Run app and test teleprompter flow**

Run: `Cmd+R`
Verify:
1. Select a script with content in the sidebar
2. Click "Present" -- floating teleprompter window appears
3. Window floats above all other windows
4. Window is invisible to screen sharing (verify with screenshot or screen recording)
5. Play/Pause button toggles auto-scroll
6. Rewind/Forward buttons navigate between sections
7. Speed controls adjust scroll rate
8. Opacity slider changes window transparency
9. Lock toggle enables/disables click-through
10. Close button (X) dismisses the teleprompter
11. Global shortcuts work when another app has focus (Cmd+Shift+T to toggle, etc.)

- [ ] **Step 3: Fix any issues found during smoke test**

- [ ] **Step 4: Final commit if needed**

```bash
git status
git add <specific-files>
git commit -m "Polish teleprompter after smoke test"
```
