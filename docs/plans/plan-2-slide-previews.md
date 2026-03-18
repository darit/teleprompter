# Plan 2: PPTX Slide Previews

**Priority:** 2
**Estimated effort:** 2-3 sessions
**Risk:** Low
**Depends on:** Plan 1 (for `PersistenceManager.appSupportDirectory`) — or use inline fallback

## Problem

We extract images from PPTX slides and pass them to the LLM for vision context, but:
- Images are **not persisted** — they live in `SlideContent.images` (transient, in-memory only)
- Images are **not displayed** in the UI — no visual reference of what each slide looks like
- When rehearsing, users can't see the actual slide content they're talking about

## Strategy: Three-tier rendering with zero required dependencies

Every slide gets a visual preview. The quality depends on what's available, falling through three tiers:

### Tier 1: LibreOffice CLI (pixel-perfect, optional)
If LibreOffice is installed, render every slide to PNG via `soffice --headless --convert-to png`. Identical to what the audience sees. Detected automatically at import time.

### Tier 2: Native SwiftUI content cards (always available, primary approach)
Use `ImageRenderer` (macOS 14+) to render a SwiftUI view that lays out each slide's parsed content — title, body text, and extracted media images — in a 16:9 card. Not a pixel-perfect replica, but shows what each slide is *about*. **Works standalone with zero dependencies.**

### Tier 3: Extracted media only (fallback)
If a slide has no parsed text and no embedded images, it gets no preview (rare — would only happen for completely empty slides).

**Priority cascade on import:**
1. Try LibreOffice → if available, use Tier 1 for all slides
2. Else → use Tier 2 (native content cards) for all slides
3. Additionally → always persist extracted media images for LLM vision context

## Goal

1. **Every slide gets a visual preview** — either rendered or content card
2. **Persist extracted media images** for LLM vision context across sessions
3. **Show previews** in Script Assistant and optionally teleprompter, with a toggle

---

## Step 0: Inline fallback for PersistenceManager (if Plan 1 not done yet)

If Plan 1 hasn't been implemented, add this helper directly in `SlideImageStore.swift`:

```swift
private static let appSupportDirectory: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let appDir = appSupport.appendingPathComponent("com.dannyrodriguez.Teleprompter", isDirectory: true)
    try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    return appDir
}()
```

If Plan 1 IS done, use `PersistenceManager.appSupportDirectory` instead.

---

## Step 1: Native slide content card renderer

**New file:** `Teleprompter/Services/SlideCardRenderer.swift`

Builds a SwiftUI view from parsed slide data and snapshots it to a PNG using `ImageRenderer`. This is the primary approach — works standalone, no external dependencies.

```swift
import SwiftUI

enum SlideCardRenderer {

    /// Render a content card for a single slide.
    /// Returns PNG data of a 16:9 card showing title, body text, and first image.
    @MainActor
    static func render(slide: SlideContent) -> Data? {
        let cardView = SlideCardView(slide: slide)
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 2.0  // Retina

        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        return pngData
    }

    /// Render content cards for all slides.
    @MainActor
    static func renderAll(slides: [SlideContent]) -> [(slideNumber: Int, data: Data)] {
        slides.compactMap { slide in
            guard let data = render(slide: slide) else { return nil }
            return (slide.slideNumber, data)
        }
    }
}

/// SwiftUI view that mimics a slide layout from parsed content.
/// 16:9 aspect ratio, dark background, title + bullets + optional image.
private struct SlideCardView: View {
    let slide: SlideContent

    // Split body text into bullet points
    private var bullets: [String] {
        slide.bodyText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var firstImage: NSImage? {
        slide.images.first.flatMap { NSImage(data: $0) }
    }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                // Slide number badge
                HStack {
                    Text("SLIDE \(slide.slideNumber)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.bottom, 8)

                // Title
                if !slide.title.isEmpty {
                    Text(slide.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.bottom, 12)
                }

                // Content area: text on left, image on right (if image exists)
                HStack(alignment: .top, spacing: 16) {
                    // Bullet points
                    if !bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(bullets.prefix(8), id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(.white.opacity(0.5))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(bullet)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(2)
                                }
                            }
                            if bullets.count > 8 {
                                Text("+ \(bullets.count - 8) more...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // First extracted image (if any)
                    if let firstImage {
                        Image(nsImage: firstImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 180, maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer(minLength: 0)

                // Notes indicator
                if !slide.notes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                        Text("Has speaker notes")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 270)  // 16:9 at reasonable preview size
    }
}
```

**Why this works well:**
- Every slide with any content gets a visual card — title, bullets, images, notes indicator
- Dark theme looks good at small sizes as a thumbnail
- `ImageRenderer` is native macOS 14+ (we target macOS 26.2)
- Zero dependencies, instant, works offline
- Shows what the slide is *about* — which is what you need for rehearsal

---

## Step 2: LibreOffice renderer (optional, pixel-perfect upgrade)

**New file:** `Teleprompter/Services/SlideRenderer.swift`

When LibreOffice is installed, override the content cards with pixel-perfect renders:

```swift
import Foundation

enum SlideRenderer {
    private static let searchPaths = [
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/usr/local/bin/soffice",
        "/opt/homebrew/bin/soffice",
    ]

    static var isAvailable: Bool {
        resolvedPath() != nil
    }

    private static func resolvedPath() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Render all slides in a PPTX to PNG via LibreOffice headless.
    /// Returns empty array if LibreOffice is not installed.
    static func renderSlides(pptxURL: URL) async throws -> [(slideNumber: Int, data: Data)] {
        guard let sofficePath = resolvedPath() else { return [] }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("teleprompter-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sofficePath)
        process.arguments = [
            "--headless",
            "--convert-to", "png",
            "--outdir", tempDir.path,
            pptxURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }

        // Collect output PNGs sorted by filename
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.enumerated().map { (index, file) in
            (index + 1, try Data(contentsOf: file))
        }
    }
}
```

> **Note:** If `--convert-to png` only outputs a single file, the fallback is `--convert-to pdf` then use `PDFKit`'s `PDFPage.thumbnail(of:for:)` per page. Test at implementation time.

---

## Step 3: Persist slide images to disk

**New file:** `Teleprompter/Services/SlideImageStore.swift`

Stores three types of images per slide, keyed by stable UUID:

```swift
import Foundation
import AppKit

enum SlideImageStore {
    /// Image source type
    enum ImageType: String {
        case preview   // Content card or LibreOffice render (shown in UI)
        case media     // Extracted media from PPTX (for LLM vision context)
    }

    static let baseDirectory: URL = {
        let dir = PersistenceManager.appSupportDirectory
            .appendingPathComponent("SlideImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Save images for a slide. Returns relative paths.
    @discardableResult
    static func save(images: [Data], scriptId: String, slideNumber: Int, type: ImageType) -> [String] {
        let typeDir = baseDirectory
            .appendingPathComponent(scriptId, isDirectory: true)
            .appendingPathComponent(type.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: typeDir, withIntermediateDirectories: true)

        var paths: [String] = []
        for (index, imageData) in images.enumerated() {
            let filename = "slide-\(slideNumber)-\(index).jpg"
            let fileURL = typeDir.appendingPathComponent(filename)

            if let thumbnail = createThumbnail(from: imageData, maxWidth: 480) {
                do {
                    try thumbnail.write(to: fileURL, options: .atomic)
                    paths.append("\(scriptId)/\(type.rawValue)/\(filename)")
                } catch {
                    print("SlideImageStore: failed to write \(filename): \(error)")
                }
            }
        }
        return paths
    }

    /// Load a thumbnail image. Async to avoid main-thread I/O.
    static func load(relativePath: String) async -> NSImage? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return await Task.detached {
            NSImage(contentsOf: url)
        }.value
    }

    /// Delete all images for a script.
    static func delete(scriptId: String) {
        let scriptDir = baseDirectory.appendingPathComponent(scriptId)
        try? FileManager.default.removeItem(at: scriptDir)
    }

    /// Modern thumbnail creation (no deprecated lockFocus).
    private static func createThumbnail(from data: Data, maxWidth: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0 else { return nil }

        let scale = min(maxWidth / size.width, 1.0)
        if scale >= 1.0 {
            // Already small enough — just re-encode as JPEG
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else { return nil }
            return jpegData
        }

        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }

        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return nil }

        return jpegData
    }
}
```

---

## Step 4: Add model properties

**File to modify:** `Teleprompter/Models/ScriptSection.swift`

```swift
/// Relative path to the slide preview image (content card or LibreOffice render).
var thumbnailRelativePath: String = ""
```

**File to modify:** `Teleprompter/Models/Script.swift`

```swift
/// Stable identifier for file-based storage (slide images, etc.)
var storageId: String = UUID().uuidString
```

SwiftData lightweight migration handles new properties with defaults automatically.

---

## Step 5: Generate and save previews during PPTX import

**File to modify:** `Teleprompter/Views/ScriptManager/ScriptManagerView.swift`

In `importPPTX()`, after creating sections:

```swift
modelContext.insert(script)
selectedScript = script

// Generate slide previews
Task { @MainActor in
    // Try LibreOffice first (pixel-perfect)
    let libreOfficeRenders = (try? await SlideRenderer.renderSlides(pptxURL: url)) ?? []

    for slide in result.slides {
        guard let section = script.sections.first(where: { $0.slideNumber == slide.slideNumber }) else { continue }

        if let rendered = libreOfficeRenders.first(where: { $0.slideNumber == slide.slideNumber }) {
            // Tier 1: LibreOffice pixel-perfect render
            let paths = SlideImageStore.save(
                images: [rendered.data],
                scriptId: script.storageId,
                slideNumber: slide.slideNumber,
                type: .preview
            )
            section.thumbnailRelativePath = paths.first ?? ""
        } else {
            // Tier 2: Native content card
            if let cardData = SlideCardRenderer.render(slide: slide) {
                let paths = SlideImageStore.save(
                    images: [cardData],
                    scriptId: script.storageId,
                    slideNumber: slide.slideNumber,
                    type: .preview
                )
                section.thumbnailRelativePath = paths.first ?? ""
            }
        }

        // Always persist extracted media for LLM vision context
        if !slide.images.isEmpty {
            SlideImageStore.save(
                images: slide.images,
                scriptId: script.storageId,
                slideNumber: slide.slideNumber,
                type: .media
            )
        }
    }

    try? modelContext.save()
}
```

Same approach in `updatePPTX()` — re-render and re-save for updated slides.

---

## Step 6: Wire up image cleanup on script deletion

Wherever scripts are deleted (likely `ScriptSidebarView.swift`):

```swift
SlideImageStore.delete(scriptId: script.storageId)
modelContext.delete(script)
```

---

## Step 7: Create thumbnail view component

**New file:** `Teleprompter/Views/Components/SlidePreviewThumbnail.swift`

```swift
import SwiftUI

struct SlidePreviewThumbnail: View {
    let relativePath: String
    var maxWidth: CGFloat = 160
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 0.5)
                    }
            }
        }
        .task(id: relativePath) {
            image = await SlideImageStore.load(relativePath: relativePath)
        }
    }
}
```

---

## Step 8: Show in ScriptPreviewPanel

**File to modify:** `Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift`

Add to `SectionSnapshot` (default value avoids breaking call sites):

```swift
struct SectionSnapshot: Identifiable, Equatable {
    var id: Int { slideNumber }
    let slideNumber: Int
    let label: String
    let content: String
    let accentColorHex: String
    var thumbnailRelativePath: String = ""
}
```

Add toggle + thumbnail in `previewSection(_:)`:

```swift
// Property on ScriptPreviewPanel:
var showSlideImages: Bool = true

// In previewSection(_:), before the text:
if showSlideImages && !section.thumbnailRelativePath.isEmpty {
    SlidePreviewThumbnail(relativePath: section.thumbnailRelativePath, maxWidth: 200)
        .padding(.bottom, 4)
}
```

Toggle in the header:

```swift
Toggle("Slides", isOn: /* binding */)
    .toggleStyle(.switch)
    .controlSize(.mini)
```

**File to modify:** `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`

Update all snapshot creation:

```swift
SectionSnapshot(
    slideNumber: section.slideNumber,
    label: section.label,
    content: section.content,
    accentColorHex: section.accentColorHex,
    thumbnailRelativePath: section.thumbnailRelativePath
)
```

---

## Step 9: Optional thumbnail in teleprompter view

**File to modify:** `Teleprompter/Views/Teleprompter/TeleprompterContentView.swift`

```swift
if AppSettings.shared.showSlideThumbnails,
   !currentSection.thumbnailRelativePath.isEmpty {
    SlidePreviewThumbnail(relativePath: currentSection.thumbnailRelativePath, maxWidth: 120)
}
```

**File to modify:** `Teleprompter/Services/AppSettings.swift`

```swift
var showSlideThumbnails: Bool {
    get { defaults.object(forKey: "showSlideThumbnails") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "showSlideThumbnails") }
}
```

**File to modify:** `Teleprompter/Views/SettingsView.swift`

```swift
Toggle("Show slide thumbnails", isOn: $settings.showSlideThumbnails)
```

---

## Files summary

| Action | File |
|--------|------|
| **Create** | `Teleprompter/Services/SlideCardRenderer.swift` — native SwiftUI content card → PNG |
| **Create** | `Teleprompter/Services/SlideRenderer.swift` — optional LibreOffice CLI integration |
| **Create** | `Teleprompter/Services/SlideImageStore.swift` — disk persistence (preview + media) |
| **Create** | `Teleprompter/Views/Components/SlidePreviewThumbnail.swift` — async thumbnail view |
| **Modify** | `Teleprompter/Models/ScriptSection.swift` — add `thumbnailRelativePath` |
| **Modify** | `Teleprompter/Models/Script.swift` — add `storageId` |
| **Modify** | `Teleprompter/Views/ScriptManager/ScriptManagerView.swift` — render + save on import |
| **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift` — thumbnails + toggle |
| **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` — pass thumbnail path |
| **Modify** | `Teleprompter/Views/Teleprompter/TeleprompterContentView.swift` — optional thumbnail |
| **Modify** | `Teleprompter/Services/AppSettings.swift` — showSlideThumbnails setting |
| **Modify** | `Teleprompter/Views/SettingsView.swift` — toggle |
| **Modify** | Script deletion site — cleanup images |

## Verification

1. Import a PPTX **without** LibreOffice installed → every slide should get a dark content card preview showing title + bullets + images.
2. Import a PPTX **with** LibreOffice installed → every slide should get a pixel-perfect render.
3. Check `~/Library/Application Support/.../SlideImages/{uuid}/preview/` — JPEGs should exist.
4. Check `.../media/` subdirectory — extracted images preserved for LLM vision.
5. Open Script Assistant → thumbnails visible in preview panel.
6. Toggle "Slides" off → thumbnails hidden.
7. Delete a script → images cleaned from disk.
8. Rename a script → thumbnails still work (keyed by storageId).
9. Launch teleprompter with setting on → small thumbnails visible in header.

## Future enhancements

- **LLM-generated SVG sketches** — during script generation, ask the model to also sketch a simple SVG of each slide's intended visual layout. Useful for visualizing "what the audience sees" vs "what the slide contains."
- **Bundled LibreOffice runtime** — ship a minimal Collabora Online renderer (~200MB) for guaranteed pixel-perfect previews without requiring users to install LibreOffice.
- **Re-render on PPTX update** — when `updatePPTX()` is called, automatically re-render changed slides.
