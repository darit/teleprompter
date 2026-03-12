# Teleprompter Plan 1: Foundation -- Project Setup, Data Model & Script Manager

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Xcode project, data model, and Script Manager view -- the core app shell that everything else builds on.

**Architecture:** SwiftUI app using NavigationSplitView for the Script Manager. SwiftData for persistence with Script and ScriptSection models. Liquid Glass styling via macOS Tahoe APIs. The app launches directly into the Script Manager.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Xcode 26, macOS Tahoe

**Spec:** `docs/superpowers/specs/2026-03-12-teleprompter-design.md`

**Related plans:**
- Plan 2: PPTX parsing, LLM providers, Script Assistant
- Plan 3: Teleprompter floating window

---

## File Structure

```
Teleprompter/
  Teleprompter.xcodeproj
  Teleprompter/
    TeleprompterApp.swift              # App entry point, ModelContainer setup
    Models/
      Script.swift                     # Script SwiftData model
      ScriptSection.swift              # ScriptSection SwiftData model
    Views/
      ScriptManager/
        ScriptManagerView.swift        # NavigationSplitView: sidebar + detail
        ScriptSidebarView.swift        # Sidebar: search, list, new/import buttons
        ScriptDetailView.swift         # Detail: script content with slide sections
        ScriptRowView.swift            # Single row in the sidebar list
        SlideSectionView.swift         # Single slide section in the detail view
      Components/
        SlidePillView.swift            # Reusable slide number pill with accent color
    Utilities/
      ColorHex.swift                   # Color <-> hex string conversion
      ReadTimeEstimator.swift          # Estimate reading duration from text
    Preview Content/
      PreviewSampleData.swift          # Sample Script/ScriptSection for SwiftUI previews
  TeleprompterTests/
    Models/
      ScriptTests.swift                # Script model tests
      ScriptSectionTests.swift         # ScriptSection model tests
    Utilities/
      ColorHexTests.swift              # Hex conversion tests
      ReadTimeEstimatorTests.swift     # Read time calculation tests
```

---

## Chunk 1: Project Setup and Data Model

### Task 1: Create Xcode Project

**Files:**
- Create: `Teleprompter.xcodeproj` (via Xcode CLI)
- Create: `Teleprompter/TeleprompterApp.swift`

- [ ] **Step 1: Create macOS app project (MANUAL -- requires Xcode GUI)**

This step must be done manually in Xcode before the agent continues:

1. Open Xcode
2. File > New > Project
3. macOS > App
4. Configure:
   - Product Name: `Teleprompter`
   - Organization Identifier: `com.dannyrodriguez`
   - Interface: SwiftUI
   - Storage: SwiftData
   - Language: Swift
   - Testing System: Swift Testing
5. Save in: `/Users/drodrig/Developer/teleprompter/`

**Agent resumes after this step is complete.**

- [ ] **Step 2: Verify project builds**

Run: Open the project in Xcode and press `Cmd+B`
Expected: Build succeeds with zero errors

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/
git commit -m "Initialize Xcode project with SwiftUI and SwiftData"
```

---

### Task 2: Script Data Model

**Files:**
- Create: `Teleprompter/Teleprompter/Models/Script.swift`
- Create: `Teleprompter/Teleprompter/Models/ScriptSection.swift`
- Create: `Teleprompter/TeleprompterTests/Models/ScriptTests.swift`
- Create: `Teleprompter/TeleprompterTests/Models/ScriptSectionTests.swift`

- [ ] **Step 1: Write tests for ScriptSection**

```swift
// TeleprompterTests/Models/ScriptSectionTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("ScriptSection Model")
struct ScriptSectionTests {

    @Test("initializes with all required properties")
    func testInit() {
        let section = ScriptSection(
            slideNumber: 1,
            label: "Introduction",
            content: "Welcome everyone to this presentation.",
            order: 0,
            accentColorHex: "#4A9EFF",
            isAIRefined: false
        )

        #expect(section.slideNumber == 1)
        #expect(section.label == "Introduction")
        #expect(section.content == "Welcome everyone to this presentation.")
        #expect(section.order == 0)
        #expect(section.accentColorHex == "#4A9EFF")
        #expect(section.isAIRefined == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `ScriptSection` not defined

- [ ] **Step 3: Implement ScriptSection model**

```swift
// Teleprompter/Models/ScriptSection.swift
import Foundation
import SwiftData

@Model
final class ScriptSection {
    var slideNumber: Int
    var label: String
    var content: String
    var order: Int
    var accentColorHex: String
    var isAIRefined: Bool

    init(
        slideNumber: Int,
        label: String,
        content: String,
        order: Int,
        accentColorHex: String,
        isAIRefined: Bool = false
    ) {
        self.slideNumber = slideNumber
        self.label = label
        self.content = content
        self.order = order
        self.accentColorHex = accentColorHex
        self.isAIRefined = isAIRefined
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Write tests for Script**

```swift
// TeleprompterTests/Models/ScriptTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("Script Model")
struct ScriptTests {

    @Test("initializes with name and empty sections")
    func testInitDefaults() {
        let script = Script(name: "Test Script")

        #expect(script.name == "Test Script")
        #expect(script.sections.isEmpty)
        #expect(script.scrollSpeed == 1.0)
        #expect(script.fontSize == 16.0)
    }

    @Test("stores sections in order")
    func testSectionsOrdering() {
        let script = Script(name: "Ordered")
        let s1 = ScriptSection(slideNumber: 1, label: "Intro", content: "Hello", order: 0, accentColorHex: "#FF0000")
        let s2 = ScriptSection(slideNumber: 2, label: "Body", content: "Main", order: 1, accentColorHex: "#00FF00")
        script.sections = [s1, s2]

        let sorted = script.sortedSections
        #expect(sorted.count == 2)
        #expect(sorted[0].label == "Intro")
        #expect(sorted[1].label == "Body")
    }

    @Test("modifiedAt updates are tracked")
    func testDates() {
        let script = Script(name: "Dated")
        #expect(script.createdAt <= Date.now)
        #expect(script.modifiedAt <= Date.now)
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `Script` not defined

- [ ] **Step 7: Implement Script model**

```swift
// Teleprompter/Models/Script.swift
import Foundation
import SwiftData

@Model
final class Script {
    var name: String
    @Relationship(deleteRule: .cascade) var sections: [ScriptSection]
    var createdAt: Date
    var modifiedAt: Date
    var scrollSpeed: Double
    var fontSize: Double

    var sortedSections: [ScriptSection] {
        sections.sorted { $0.order < $1.order }
    }

    init(
        name: String,
        sections: [ScriptSection] = [],
        scrollSpeed: Double = 1.0,
        fontSize: Double = 16.0
    ) {
        self.name = name
        self.sections = sections
        self.createdAt = Date.now
        self.modifiedAt = Date.now
        self.scrollSpeed = scrollSpeed
        self.fontSize = fontSize
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 9: Register models in app entry point**

Update `TeleprompterApp.swift`:

```swift
// Teleprompter/TeleprompterApp.swift
import SwiftUI
import SwiftData

@main
struct TeleprompterApp: App {
    var body: some Scene {
        WindowGroup {
            ScriptManagerView() // replaced in Task 11 with full implementation; use placeholder until then
        }
        .modelContainer(for: [Script.self, ScriptSection.self])
    }
}
```

- [ ] **Step 10: Build and verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds

- [ ] **Step 11: Commit**

```bash
git add Teleprompter/Teleprompter/Models/ Teleprompter/TeleprompterTests/Models/
git commit -m "Add Script and ScriptSection SwiftData models with tests"
```

---

### Task 3: Utility -- Color Hex Conversion

**Files:**
- Create: `Teleprompter/Teleprompter/Utilities/ColorHex.swift`
- Create: `Teleprompter/TeleprompterTests/Utilities/ColorHexTests.swift`

- [ ] **Step 1: Write tests**

```swift
// TeleprompterTests/Utilities/ColorHexTests.swift
import Testing
import SwiftUI
@testable import Teleprompter

@Suite("Color Hex Conversion")
struct ColorHexTests {

    @Test("creates Color from valid hex string")
    func testFromHex() {
        let color = Color(hex: "#4A9EFF")
        #expect(color != nil)
    }

    @Test("returns nil for invalid hex")
    func testInvalidHex() {
        let color = Color(hex: "not-a-color")
        #expect(color == nil)
    }

    @Test("handles hex without hash prefix")
    func testWithoutHash() {
        let color = Color(hex: "4A9EFF")
        #expect(color != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `Color(hex:)` not defined

- [ ] **Step 3: Implement hex conversion**

```swift
// Teleprompter/Utilities/ColorHex.swift
import SwiftUI

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6,
              let hexNumber = UInt64(hexString, radix: 16) else {
            return nil
        }

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNumber & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Utilities/ColorHex.swift Teleprompter/TeleprompterTests/Utilities/ColorHexTests.swift
git commit -m "Add Color hex string conversion utility"
```

---

### Task 4: Utility -- Read Time Estimator

**Files:**
- Create: `Teleprompter/Teleprompter/Utilities/ReadTimeEstimator.swift`
- Create: `Teleprompter/TeleprompterTests/Utilities/ReadTimeEstimatorTests.swift`

- [ ] **Step 1: Write tests**

```swift
// TeleprompterTests/Utilities/ReadTimeEstimatorTests.swift
import Testing
@testable import Teleprompter

@Suite("Read Time Estimator")
struct ReadTimeEstimatorTests {

    @Test("estimates duration for a known word count")
    func testBasicEstimate() {
        // Average speaking rate: ~150 words per minute
        let text = String(repeating: "word ", count: 150)
        let duration = ReadTimeEstimator.estimateDuration(for: text, wordsPerMinute: 150)
        #expect(duration == 60.0) // 1 minute
    }

    @Test("returns zero for empty text")
    func testEmptyText() {
        let duration = ReadTimeEstimator.estimateDuration(for: "", wordsPerMinute: 150)
        #expect(duration == 0.0)
    }

    @Test("formats duration as readable string")
    func testFormatDuration() {
        #expect(ReadTimeEstimator.formatDuration(45) == "~45 sec")
        #expect(ReadTimeEstimator.formatDuration(90) == "~1.5 min")
        #expect(ReadTimeEstimator.formatDuration(480) == "~8 min")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `ReadTimeEstimator` not defined

- [ ] **Step 3: Implement estimator**

```swift
// Teleprompter/Utilities/ReadTimeEstimator.swift
import Foundation

enum ReadTimeEstimator {
    static func estimateDuration(for text: String, wordsPerMinute: Double = 150) -> TimeInterval {
        let wordCount = text.split(separator: " ").count
        guard wordCount > 0 else { return 0 }
        return (Double(wordCount) / wordsPerMinute) * 60.0
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "~\(Int(seconds)) sec"
        } else {
            let minutes = seconds / 60.0
            if minutes == minutes.rounded() {
                return "~\(Int(minutes)) min"
            } else {
                return "~\(String(format: "%.1f", minutes)) min"
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Utilities/ReadTimeEstimator.swift Teleprompter/TeleprompterTests/Utilities/ReadTimeEstimatorTests.swift
git commit -m "Add read time estimation utility"
```

---

### Task 5: Preview Sample Data

**Files:**
- Create: `Teleprompter/Teleprompter/Preview Content/PreviewSampleData.swift`

- [ ] **Step 1: Create sample data for SwiftUI previews**

```swift
// Teleprompter/Preview Content/PreviewSampleData.swift
import Foundation
import SwiftData

@MainActor
enum PreviewSampleData {
    static let sampleSections: [ScriptSection] = [
        ScriptSection(
            slideNumber: 1, label: "Introduction",
            content: "Buenas tardes a todos. Hoy vamos a revisar los cambios mas importantes que hicimos en la arquitectura durante Q1.",
            order: 0, accentColorHex: "#4A9EFF"
        ),
        ScriptSection(
            slideNumber: 2, label: "Overview",
            content: "Nos enfocamos en tres pilares: performance, developer experience, y observabilidad.",
            order: 1, accentColorHex: "#34C759"
        ),
        ScriptSection(
            slideNumber: 3, label: "Latency Reduction",
            content: "Logramos reducir la latencia p95 de 320 milisegundos a 180. Eso es una mejora del 44 por ciento gracias a la migracion a Redis Cluster.",
            order: 2, accentColorHex: "#FF9500", isAIRefined: true
        ),
    ]

    static func sampleScript() -> Script {
        let script = Script(name: "Q1 Architecture Review")
        script.sections = sampleSections
        return script
    }

    static var container: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Script.self, ScriptSection.self, configurations: config)
        let script = sampleScript()
        container.mainContext.insert(script)
        return container
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add "Teleprompter/Teleprompter/Preview Content/PreviewSampleData.swift"
git commit -m "Add preview sample data for SwiftUI previews"
```

---

## Chunk 2: Script Manager Views

### Task 6: SlidePillView Component

**Files:**
- Create: `Teleprompter/Teleprompter/Views/Components/SlidePillView.swift`

- [ ] **Step 1: Implement slide pill component**

```swift
// Teleprompter/Views/Components/SlidePillView.swift
import SwiftUI

struct SlidePillView: View {
    let slideNumber: Int
    let colorHex: String

    var body: some View {
        Text("SLIDE \(slideNumber)")
            .font(.system(size: 9, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: colorHex)?.opacity(0.12) ?? Color.gray.opacity(0.12))
                    .strokeBorder(Color(hex: colorHex)?.opacity(0.2) ?? Color.gray.opacity(0.2), lineWidth: 1)
            }
            .glassEffect(.regular.interactive, in: .capsule)
    }
}

#Preview {
    HStack(spacing: 8) {
        SlidePillView(slideNumber: 1, colorHex: "#4A9EFF")
        SlidePillView(slideNumber: 2, colorHex: "#34C759")
        SlidePillView(slideNumber: 3, colorHex: "#FF9500")
    }
    .padding()
}
```

- [ ] **Step 2: Open preview in Xcode and verify it renders**

Expected: Three colored pills showing "SLIDE 1", "SLIDE 2", "SLIDE 3" with glass effect

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/Components/SlidePillView.swift
git commit -m "Add SlidePillView component with glass effect"
```

---

### Task 7: SlideSectionView Component

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptManager/SlideSectionView.swift`

- [ ] **Step 1: Implement slide section view**

```swift
// Teleprompter/Views/ScriptManager/SlideSectionView.swift
import SwiftUI

struct SlideSectionView: View {
    let section: ScriptSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)

                if section.isAIRefined {
                    Text("AI refined")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                        }
                }

                Spacer()

                Text(ReadTimeEstimator.formatDuration(
                    ReadTimeEstimator.estimateDuration(for: section.content)
                ))
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            }

            Text(section.content)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    SlideSectionView(section: PreviewSampleData.sampleSections[2])
        .padding()
}
```

- [ ] **Step 2: Open preview and verify it renders**

Expected: Slide pill, "AI refined" tag, duration, and content text

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/SlideSectionView.swift
git commit -m "Add SlideSectionView component"
```

---

### Task 8: ScriptRowView Component

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptRowView.swift`

- [ ] **Step 1: Implement sidebar row**

```swift
// Teleprompter/Views/ScriptManager/ScriptRowView.swift
import SwiftUI

struct ScriptRowView: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(script.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text(script.modifiedAt, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ScriptRowView(script: PreviewSampleData.sampleScript())
        .padding()
        .modelContainer(PreviewSampleData.container)
}
```

- [ ] **Step 2: Verify preview renders**

Expected: Script name and relative date

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/ScriptRowView.swift
git commit -m "Add ScriptRowView sidebar component"
```

---

### Task 9: ScriptSidebarView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptSidebarView.swift`

- [ ] **Step 1: Implement sidebar**

```swift
// Teleprompter/Views/ScriptManager/ScriptSidebarView.swift
import SwiftUI
import SwiftData

struct ScriptSidebarView: View {
    @Query(sort: \Script.modifiedAt, order: .reverse) private var scripts: [Script]
    @Binding var selectedScript: Script?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var filteredScripts: [Script] {
        if searchText.isEmpty { return scripts }
        return scripts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 6) {
                Button("+ New") { createNewScript() }
                    .buttonStyle(.glass)

                Button("Import") { /* Plan 2: PPTX import */ }
                    .buttonStyle(.glass)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Script list
            List(filteredScripts, selection: $selectedScript) { script in
                ScriptRowView(script: script)
                    .tag(script)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deleteScript(script)
                        }
                    }
            }
            .searchable(text: $searchText, prompt: "Search scripts...")

            // Model status at bottom (model name wired in Plan 2)
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                Text("No model configured")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
    }

    private func createNewScript() {
        let script = Script(name: "Untitled Script")
        modelContext.insert(script)
        selectedScript = script
    }

    private func deleteScript(_ script: Script) {
        if selectedScript == script {
            selectedScript = nil
        }
        modelContext.delete(script)
    }
}

#Preview {
    ScriptSidebarView(selectedScript: .constant(nil))
        .modelContainer(PreviewSampleData.container)
        .frame(width: 220)
}
```

- [ ] **Step 2: Verify preview renders**

Expected: Sidebar with search, buttons, script list, model status

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/ScriptSidebarView.swift
git commit -m "Add ScriptSidebarView with search, create, and delete"
```

---

### Task 10: ScriptDetailView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptDetailView.swift`

- [ ] **Step 1: Implement detail view**

```swift
// Teleprompter/Views/ScriptManager/ScriptDetailView.swift
import SwiftUI

struct ScriptDetailView: View {
    @Bindable var script: Script
    @State private var isEditingName = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if isEditingName {
                        TextField("Script name", text: $script.name)
                            .font(.system(size: 22, weight: .bold))
                            .textFieldStyle(.plain)
                            .onSubmit {
                                isEditingName = false
                                script.modifiedAt = .now
                            }
                    } else {
                        Text(script.name)
                            .font(.system(size: 22, weight: .bold))
                            .onTapGesture { isEditingName = true }
                    }

                    HStack(spacing: 8) {
                        Text("\(script.sections.count) slides")
                        Text("--")
                            .foregroundStyle(.quaternary)
                        Text("Modified \(script.modifiedAt, style: .relative)")
                        Text("--")
                            .foregroundStyle(.quaternary)
                        Text(ReadTimeEstimator.formatDuration(totalDuration))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Refine with AI") {
                        // Plan 2: open Script Assistant
                    }
                    .buttonStyle(.glass)

                    Button("Present") {
                        // Plan 3: launch teleprompter
                    }
                    .buttonStyle(.glass)
                    .tint(.accentColor)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Script sections
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(script.sortedSections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 {
                            Divider().padding(.vertical, 4)
                        }
                        SlideSectionView(section: section)
                    }

                    if script.sections.isEmpty {
                        ContentUnavailableView(
                            "No script content",
                            systemImage: "doc.text",
                            description: Text("Create sections manually or import a PPTX to generate a script with AI.")
                        )
                    }
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                HStack(spacing: 12) {
                    Text("\(script.sections.count) slides")
                    Text("|").foregroundStyle(.quaternary)
                    Text(ReadTimeEstimator.formatDuration(totalDuration) + " total")
                    Text("|").foregroundStyle(.quaternary)
                    Text("Speed: \(String(format: "%.1f", script.scrollSpeed))x")
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Font size")
                    Button { adjustFontSize(-1) } label: {
                        Text("A-").font(.system(size: 10))
                    }
                    .buttonStyle(.glass)

                    Button { adjustFontSize(1) } label: {
                        Text("A+").font(.system(size: 10))
                    }
                    .buttonStyle(.glass)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var totalDuration: TimeInterval {
        script.sortedSections.reduce(0) { total, section in
            total + ReadTimeEstimator.estimateDuration(for: section.content)
        }
    }

    private func adjustFontSize(_ delta: Double) {
        script.fontSize = max(12, min(32, script.fontSize + delta))
        script.modifiedAt = .now
    }
}

#Preview {
    ScriptDetailView(script: PreviewSampleData.sampleScript())
        .modelContainer(PreviewSampleData.container)
        .frame(width: 700, height: 500)
}
```

- [ ] **Step 2: Verify preview renders**

Expected: Script title, metadata, slide sections with pills, bottom bar with controls

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/ScriptDetailView.swift
git commit -m "Add ScriptDetailView with sections, metadata, and controls"
```

---

### Task 11: ScriptManagerView (Main NavigationSplitView)

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptManagerView.swift`
- Modify: `Teleprompter/Teleprompter/TeleprompterApp.swift`

- [ ] **Step 1: Implement main manager view**

```swift
// Teleprompter/Views/ScriptManager/ScriptManagerView.swift
import SwiftUI
import SwiftData

struct ScriptManagerView: View {
    @State private var selectedScript: Script?

    var body: some View {
        NavigationSplitView {
            ScriptSidebarView(selectedScript: $selectedScript)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let script = selectedScript {
                ScriptDetailView(script: script)
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a script from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
```

- [ ] **Step 2: Wire up to app entry point**

Replace `ContentView()` in `TeleprompterApp.swift`:

```swift
// Teleprompter/TeleprompterApp.swift
import SwiftUI
import SwiftData

@main
struct TeleprompterApp: App {
    var body: some Scene {
        WindowGroup {
            ScriptManagerView()
        }
        .modelContainer(for: [Script.self, ScriptSection.self])
    }
}
```

- [ ] **Step 3: Build and run**

Run: `Cmd+R` in Xcode
Expected: App launches showing NavigationSplitView with sidebar and empty detail. "New" button creates a script, which appears in the sidebar and can be selected.

- [ ] **Step 4: Delete auto-generated ContentView if it exists**

Remove `ContentView.swift` from the project if Xcode generated it.

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/ScriptManagerView.swift Teleprompter/Teleprompter/TeleprompterApp.swift
git rm Teleprompter/Teleprompter/ContentView.swift 2>/dev/null; true
git commit -m "Add ScriptManagerView and wire up as main app view"
```

---

### Task 12: Manual Smoke Test and Polish

- [ ] **Step 1: Run the app and verify end-to-end flow**

Run: `Cmd+R`
Verify:
1. App opens to Script Manager with empty state
2. Click "+ New" creates a script named "Untitled Script"
3. Script appears in sidebar, selecting it shows the detail view
4. Script name is editable by clicking on it
5. Search filters the sidebar list
6. Right-click a script in sidebar shows "Delete" option
7. Font size A-/A+ buttons change the value in the bottom bar
8. Window resizing works, sidebar collapses properly

- [ ] **Step 2: Fix any issues found during smoke test**

- [ ] **Step 3: Final commit**

```bash
# Add only the specific files you modified during the smoke test fix
git add Teleprompter/Teleprompter/<files-you-changed>
git commit -m "Polish Script Manager after smoke test"
```
