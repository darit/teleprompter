# Teleprompter

A macOS app for preparing and delivering presentations with an AI-powered script assistant and floating teleprompter overlay.

## Features

**Script Management**
- Import PowerPoint (.pptx) files — extracts slide titles, body text, speaker notes, and images
- Per-slide script editor with inline stage direction toolbar ([PAUSE], [SLOW], [LOOK AT CAMERA], [SHOW SLIDE], [BREATHE])
- Read time estimation per slide and total presentation duration
- Persistent storage with SwiftData

**AI Script Assistant**
- Chat-based workflow to generate teleprompter scripts from slide content
- Supports Claude Code CLI and LM Studio (local models) as LLM backends
- Real-time streaming with live preview updates as the model generates
- Parallel "Generate All" — fans out concurrent LLM calls (one per slide) for fast bulk generation
- Slide images passed to vision-capable models for visual context
- Configurable target duration (5–60 min) with per-slide time budgeting

**Teleprompter**
- Floating, always-on-top overlay window (works over video calls, screen shares)
- Karaoke-style word highlighting synced to speaking pace
- Research-backed pacing with punctuation-aware pauses (commas, periods, ellipses, em dashes)
- Stage direction badges with countdown timers
- Adjustable WPM (60–250), font size, background opacity, and window opacity
- "Next slide" transition banner pinned to viewport bottom
- Global keyboard shortcuts for play/pause, next/previous section

## Tech Stack

- **Swift / SwiftUI** — native macOS app
- **SwiftData** — persistence for scripts, sections, and chat history
- **AppKit** — `NSPanel` for the floating teleprompter overlay, `NSHostingView` bridge
- **OpenAI-compatible API** — LM Studio integration with vision support
- **Claude Code CLI** — direct integration via process spawning

## Project Structure

```
Teleprompter/
├── LLM/              # LLM provider protocol, Claude CLI, LM Studio
├── Models/           # SwiftData models (Script, ScriptSection, etc.)
├── PPTX/             # PowerPoint parser (XML extraction, image extraction)
├── Services/         # ConversationManager, PromptTemplates, AsyncSemaphore
├── Teleprompter/     # Window controller, state management
├── Utilities/        # ReadTimeEstimator, GlobalShortcutManager
└── Views/
    ├── Components/   # Shared UI (SlidePillView, etc.)
    ├── ScriptAssistant/  # Chat panel, preview panel, message views
    ├── ScriptManager/    # Main editor, slide sections, detail view
    └── Teleprompter/     # Overlay text view, controls, stage directions
```

## Getting Started

1. Open `Teleprompter.xcodeproj` in Xcode
2. Build and run (macOS 15+)
3. Import a `.pptx` file or create a new script
4. Click **Refine with AI** to open the script assistant
5. Click **Present** to launch the teleprompter overlay

**LLM Setup:**
- **LM Studio** — install and start [LM Studio](https://lmstudio.ai), load a model. The app connects to `localhost:1234`
- **Claude Code CLI** — install with `npm install -g @anthropic-ai/claude-code`

## Author

Made with <3 by **Danny Rodriguez**

## License

Private repository.
