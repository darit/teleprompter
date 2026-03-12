# Teleprompter -- Design Spec

## Overview

A native macOS app for preparing and delivering presentation scripts. The app combines an AI-powered script assistant that generates speech scripts from PowerPoint slides with a non-intrusive floating teleprompter for live use during video calls.

**Problem:** When presenting via video call (Teams, Zoom), slide notes serve as supplementary context for distributed decks, not as live speech scripts. Writing a separate speech script is repetitive work, and past HTML-based teleprompters were one-off artisanal efforts.

**Solution:** A reusable macOS app that:
1. Imports PPTX files and extracts slide content
2. Uses a local LLM to collaboratively generate a speech script through conversation
3. Provides a floating teleprompter window invisible to screen sharing

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (macOS Tahoe Liquid Glass) |
| Persistence | SwiftData |
| LLM Inference | MLX (local, Apple Silicon) |
| PPTX Parsing | ZIP decompression + XML parsing |
| Language | Swift 6.2 |
| IDE | Xcode 26 |
| Target | macOS (Apple Silicon, M1+) |

## Architecture

### Views

The app has 4 main views:

1. **Script Manager** -- main window, always open
2. **Script Assistant** -- chat-based script preparation
3. **Settings** -- AI model configuration, teleprompter preferences, keyboard shortcuts
4. **Teleprompter** -- floating overlay window for live presentation

### Data Model

```swift
@Model
class Script {
    var name: String
    var sections: [ScriptSection]  // one per slide, ordered
    var createdAt: Date
    var modifiedAt: Date
    var scrollSpeed: Double
    var fontSize: Double
    var targetDuration: Double?  // desired talk length in seconds (e.g. 900 for 15 min); nil = no target
}

@Model
class ScriptSection {
    var slideNumber: Int
    var label: String           // slide title or custom label
    var content: String         // speech text for this slide
    var order: Int              // explicit sort order for SwiftData persistence
    var accentColorHex: String  // hex color for the slide pill (e.g. "#4A9EFF")
    var isAIRefined: Bool       // whether this section was generated/modified by AI
}
```

Sections are stored as an ordered array rather than character offsets into a single string. This avoids position invalidation when editing and makes each slide's content independently editable.

### LLM Provider Architecture

A protocol-based approach for interchangeable LLM providers:

```swift
struct ChatMessage {
    enum Role { case system, user, assistant }
    var role: Role
    var content: String
}

protocol LLMProvider {
    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String>
    var displayName: String { get }
    var isAvailable: Bool { get }
}
```

The provider takes a full conversation history (`[ChatMessage]`), enabling multi-turn dialogue. The caller manages conversation state and appends messages as the chat progresses. All providers (MLX, local API, remote API) use the OpenAI-compatible chat completions message format over their respective transports.

Implementations:
- `MLXLocalProvider` -- default, runs models in-process via mlx-swift
- `ClaudeCLIProvider` -- invokes Claude Code CLI locally (`claude -p --model <model>`), leverages Claude Max subscription with no API key needed
- `CopilotCLIProvider` -- invokes GitHub Copilot CLI locally (`copilot -p <prompt>`), leverages Copilot subscription with no API key needed
- `LocalAPIProvider` -- HTTP to localhost (LM Studio, Ollama)
- `RemoteAPIProvider` -- HTTP to Claude API, OpenAI API

---

## View 1: Script Manager

The main window. Uses `NavigationSplitView` with a sidebar and detail area.

### Sidebar
- Search bar for filtering scripts
- "New" and "Import" buttons
- List of saved scripts showing name and relative date
- Selected script highlighted with subtle background
- Model status indicator at bottom (green dot + model name + "ready")

### Detail Area (selected script)
- Script name as large title (editable inline)
- Metadata line: slide count, last modified, estimated read time
- "Refine with AI" button -- opens Script Assistant with this script
- "Present" button -- launches teleprompter window
- Script content displayed with slide break markers
- Each slide section has:
  - A pill badge with slide number and distinctive accent color (with glass effect)
  - Separator line
  - Estimated duration for that section
  - "AI refined" indicator if that section was generated/modified by the assistant
- Bottom bar: total slides, total duration, scroll speed, font size controls

### Visual Design
- Liquid Glass throughout via `.glassEffect()` and `.ultraThinMaterial`
- `NavigationSplitView` for native macOS sidebar behavior
- `.matchedGeometryEffect` for smooth transitions when selecting scripts
- Slide pills use distinct accent colors with glass overlay for visual scanning
- No gradients -- neutral backgrounds, let the system materials do the work
- `.buttonStyle(.glass)` for action buttons

---

## View 2: Script Assistant

A split-view chat interface for collaboratively building a speech script from slide content.

### Left Panel: Chat
- Context bar at top: number of slides loaded, active model name, target duration selector (e.g. "15 min talk"), "Attach context" button
- Chat messages in bubbles:
  - AI messages: left-aligned, neutral glass bubble
  - User messages: right-aligned, subtle tinted bubble
- AI behavior:
  - Reads all slides on import and summarizes what it found
  - Asks questions one at a time to enrich the script per slide
  - Questions reference specific slides by number and quote relevant content
  - Accepts pasted context (Jira tickets, metrics, anecdotes, any text)
  - Updates the script preview in real time as context is provided
- Chat input at bottom: text field with "Attach" button (paste or drag-drop plain text files -- .txt, .md, .json -- to add context to the conversation) and "Send" button

### Right Panel: Script Preview
- Header: "Script Preview" with "Live updating" indicator, "Edit" and "Save & Present" buttons
- Script content organized by slide:
  - Slide pill with number and status icon:
    - Green checkmark: script generated
    - Blue: just updated
    - Amber "asking about this...": AI is currently asking about this slide
    - Gray "Waiting for context...": not yet addressed
  - Generated text for completed slides
- Progress bar at bottom: "X of Y slides ready", visual progress bar, estimated duration vs target (e.g. "~12 min / 15 min target")

### Flow
1. User clicks "Import" in Script Manager and selects a PPTX file
2. App extracts text from all slides (ZIP + XML parsing)
3. Script Assistant opens with slide content loaded as LLM context; user sets target duration (optional)
4. LLM analyzes slides, notes the target duration, and begins asking questions about the first slide that needs enrichment
5. User responds with additional context, the LLM generates/refines that slide's script
6. LLM moves to the next slide, repeating the process
7. User can skip slides, go back, or manually edit the preview at any time
8. When satisfied, user clicks "Save & Present" which saves the script and launches the teleprompter

---

## View 3: Settings

Organized with a sidebar for setting categories: General, Teleprompter, AI Models, Keyboard Shortcuts.

### General Section
- App name display and version
- Launch at login toggle
- Default new script behavior: blank or import PPTX prompt
- Data storage location (SwiftData store path)

### Keyboard Shortcuts Section
- Table listing all global shortcuts with their current bindings
- Shortcuts are customizable: click a shortcut cell, press new key combination to rebind
- "Reset to Defaults" button
- Conflict detection: warns if a chosen shortcut conflicts with another binding

### AI Models Section

#### System Info Card
- Auto-detected: Mac model, chip, RAM amount
- Recommendation badge: "Can run models up to ~XB" based on RAM

#### Models Directory
- Text field showing path, default: `~/.cache/lm-studio/models/`
- "Browse" button to select a different directory
- If the directory doesn't exist, the app creates it on first model download
- If LM Studio is not installed and the default path doesn't exist, the app creates it anyway -- the directory works standalone and will be picked up by LM Studio if installed later
- Note: "Shared with LM Studio. Models downloaded here are available in both apps."

#### Active Model
- Highlighted card showing currently selected model name, quantization, size

#### Installed Models
- List of models found in the models directory
- Each entry: name, quantization type, file size, estimated RAM needed
- "Use" button to set as active, "RECOMMENDED" badge for best fit given system RAM

#### Download from Hugging Face
- Search field for MLX models on Hugging Face
- Curated list of recommended models based on system RAM:

| RAM | Recommended Models |
|-----|-------------------|
| 8GB | 3-4B models, 4-bit quantized |
| 16GB | 7-8B models, 4-bit quantized |
| 32GB+ | 14-24B models, 4-bit quantized |

- Each download entry shows: model name, HF repo path, file size
- Models that exceed system RAM show a warning and disabled download button
- Download progress: progress bar, bytes downloaded / total, time remaining, cancel button
- Downloads go to the configured models directory

#### CLI Providers (subscription-based, no API keys)

**Claude Code CLI**
- Auto-detected: checks if `claude` is available in PATH
- Status indicator: "Claude CLI detected" (green) or "Not installed" (gray) with install hint (`npm install -g @anthropic-ai/claude-code`)
- Model selector: opus or sonnet
- Leverages the user's Claude Max subscription -- no API key needed
- Implementation: spawns `claude -p --model <model>` via `Process`, writes prompt to stdin, reads stdout in chunks
- Reference implementation: `../vision-builder/src/vision_builder/core/llm.py` (ClaudeProvider class)

**GitHub Copilot CLI**
- Auto-detected: checks if `copilot` is available in PATH
- Status indicator: "Copilot CLI detected" (green) or "Not installed" (gray) with install hint (`npm install -g @github/copilot-cli`)
- Leverages the user's Copilot subscription -- no API key needed
- Implementation: spawns `copilot -p <prompt>` via `Process`, reads stdout in chunks
- No model selection -- Copilot manages routing internally

#### Remote API Providers
- LM Studio / Ollama: endpoint URL field (default: localhost:1234)
- Claude API: API key field (stored in macOS Keychain, never in plaintext)
- OpenAI API: API key field (stored in macOS Keychain, never in plaintext)

### Teleprompter Section

#### Style Setting
- **Glass** -- full Liquid Glass, refracts desktop content behind the bar
- **Solid** -- opaque dark background with adjustable transparency
- **Adaptive** -- glass material whose opacity responds to the opacity slider

#### Other Settings
- Default scroll speed
- Default font size
- Default position preset (top, center, bottom)
- Default opacity
- Click-through default state (on/off)

---

## View 4: Teleprompter (Floating Window)

A floating overlay window for use during live presentations.

### Window Behavior
- `NSWindow` with `level: .floating` (always on top)
- `window.sharingType = .none` (invisible to screen sharing / screen capture)
- Free positioning via drag, with position presets:
  - **Top center** (near webcam) -- recommended for video calls
  - **Center**
  - **Bottom center**
- Remembers last used position between sessions
- Width: configurable, max ~800-1000px, centered at chosen position
- Resizable height to show more or fewer lines

### Two-Zone Architecture

#### Text Zone (upper)
- Displays the script with continuous scroll
- Shows 3 visual rows at the current font size: previous text (faded), current text (bright), next text (faded). The amount of text per row depends on window width and font size.
- Click-through toggleable:
  - **ON (LOCK OFF):** mouse events pass through to windows below. User can interact with PowerPoint/Teams through the text area
  - **OFF (LOCK ON):** text zone captures clicks. User can click to jump to a position in the script
- Visual indicator of current click-through state

#### Controls Zone (lower)
- Always interactive, never click-through
- Controls:
  - **LOCK toggle** -- switches text zone click-through on/off
  - **Rewind** (|<<) -- jump back one slide section
  - **Play/Pause** -- toggle auto-scroll
  - **Forward** (>>|) -- jump forward one slide section
  - **Speed** -- current scroll speed (adjustable)
  - **Opacity slider** -- adjusts window transparency in real time

### Global Keyboard Shortcuts
These work regardless of which app has focus:

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+T` | Show/hide teleprompter |
| `Cmd+Shift+P` | Play/pause auto-scroll |
| `Cmd+Shift+Up` | Increase scroll speed |
| `Cmd+Shift+Down` | Decrease scroll speed |
| `Cmd+Shift+Left` | Rewind |
| `Cmd+Shift+Right` | Forward |
| `Cmd+Shift+L` | Toggle click-through |
| `Cmd+Shift+[` | Decrease opacity |
| `Cmd+Shift+]` | Increase opacity |

### Visual Style
- Configurable via Settings (Glass / Solid / Adaptive)
- Slide break markers visible as subtle dividers during scroll
- Slide pills with accent colors visible during scroll for orientation

---

## PPTX Parsing

PPTX files are ZIP archives containing XML files following the ECMA-376 Open XML standard.

### Extraction Process
1. Decompress the PPTX file (it's a ZIP)
2. Read `[Content_Types].xml` to identify slide parts
3. Read `ppt/presentation.xml` for slide ordering
4. For each slide, parse `ppt/slides/slideN.xml`:
   - Extract text from `<a:t>` elements within text body shapes
   - Preserve text grouping by shape/text box
   - Extract slide title from title placeholder shapes
5. Optionally read `ppt/notesSlides/notesSlideN.xml` for existing speaker notes
6. Return structured data: ordered list of slides with title, body text, and notes

### Implementation
Use Foundation's built-in ZIP handling and XMLParser. No third-party dependencies needed for basic text extraction.

### Error Handling
- Malformed PPTX (invalid ZIP, missing XML): show error alert with "This file could not be read as a PowerPoint presentation"
- Password-protected PPTX: show alert explaining the file is encrypted and cannot be imported
- Partial extraction (some slides fail): import what is readable, show warning with slide numbers that failed

---

## LLM Integration

### MLX Local Provider (Default)

Uses `mlx-swift` and `mlx-swift-lm` packages for in-process inference on Apple Silicon.

- Models loaded from the configured models directory
- Supports safetensors format (MLX-optimized models from HuggingFace mlx-community)
- Streaming token generation via `AsyncStream`
- Model loading happens once, stays in memory for the session

### Claude Code CLI Provider

Invokes the Claude Code CLI as a subprocess to leverage a Claude Max subscription without API keys.

- Availability check: `Process` to run `which claude` (equivalent to `shutil.which("claude")` in the vision-builder reference)
- Invocation: `claude -p --model <model>` with the full prompt written to stdin
- Output: read stdout in chunks (4096 bytes) for streaming token delivery via `AsyncStream`
- Timeout: 300 seconds default, configurable
- Error handling: capture stderr, check exit code, surface errors in the chat UI
- Model options: `opus` (deep reasoning, slower) or `sonnet` (faster, general purpose)

### Copilot CLI Provider

Invokes the GitHub Copilot CLI as a subprocess to leverage a Copilot subscription.

- Availability check: `which copilot`
- Invocation: `copilot -p <prompt>` with the prompt passed as argument or via stdin
- Output: read stdout in chunks for streaming via `AsyncStream`
- Timeout: 300 seconds default
- Error handling: capture stderr, check exit code, surface errors in the chat UI
- No model selection needed -- Copilot manages model routing internally

### Model Download

- Uses HuggingFace Hub API to search and download models
- Filters to `mlx-community` namespace for pre-converted models
- RAM detection via `ProcessInfo.processInfo.physicalMemory`
- Downloads write directly to the models directory
- Progress tracking via URLSession delegate

### Script Generation Prompt Strategy

The system prompt for script generation:

1. Provides all slide content as context
2. Provides target duration if set (e.g. "The presenter wants this talk to be ~15 minutes"); model budgets time across slides proportionally to content density
3. Instructs the model to act as a presentation coach
4. Model should ask questions one slide at a time to gather additional context
5. Model generates natural speech text (not bullet points, not formal writing)
6. Model should suggest mentioning team members, concrete numbers, and anecdotes
7. Output should be conversational and match the presenter's speaking style
8. If a target duration is set, model flags when the running total is trending over/under and suggests trimming or expanding specific slides

---

## Non-Functional Requirements

- **macOS only** -- Apple Silicon required (M1+) for MLX inference
- **Minimum macOS version** -- macOS Tahoe (for Liquid Glass support)
- **Offline capable** -- core teleprompter and MLX inference work without internet
- **Privacy** -- all LLM inference happens locally by default; remote providers are opt-in
- **Performance** -- teleprompter scroll must be butter-smooth (target 120fps on ProMotion displays)
- **Accessibility** -- respect system font size preferences, support VoiceOver for Script Manager and Settings

---

## Mockups Reference

Visual mockups created during the design phase are available in:
`.superpowers/brainstorm/58752-1773335469/`

## Credits

Made with <3 by Danny Rodriguez

---

### Mockup Files Reference

Key files:
- `screen-premium-v2-manager.html` -- Script Manager (final design)
- `screen-premium-chat.html` -- Script Assistant
- `screen-settings-ai.html` -- Settings / AI Models
- `screen-teleprompter-live.html` -- Teleprompter in context
- `screen-teleprompter-glass.html` -- Teleprompter glass style options
- `teleprompter-clickthrough.html` -- Click-through zone behavior
- `teleprompter-position.html` -- Position options for ultrawide
