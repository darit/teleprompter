# Teleprompter

A macOS app for preparing and delivering presentations with an AI-powered script assistant and floating teleprompter overlay.

Import your PowerPoint slides, let AI generate natural speaking scripts, then present with a karaoke-style floating teleprompter that stays on top of any app — video calls, screen shares, whatever you need.

<p align="center">
  <em>Built with Swift, SwiftUI, and SwiftData</em>
</p>

## Features

### Script Management
- Import PowerPoint (.pptx) files — extracts slide titles, body text, speaker notes, and embedded images
- Per-slide script editor with inline stage directions (`[PAUSE]`, `[SLOW]`, `[LOOK AT CAMERA]`, `[SHOW SLIDE]`, `[BREATHE]`)
- Read time estimation per slide and total presentation duration
- Automatic backups before bulk AI updates

### AI Script Assistant
- Chat-based workflow to generate teleprompter scripts from your slide content
- Multiple LLM backends:
  - **Apple On-Device** — uses the built-in Foundation model, no setup required
  - **LM Studio** — connect to any local model via OpenAI-compatible API
  - **MLX** — run Hugging Face models natively on Apple Silicon
  - **Claude Code CLI** — use Anthropic's Claude models locally
- Real-time streaming with live preview as the model writes
- "Generate All" with parallel slide processing (configurable concurrency)
- Slide images passed to vision-capable models for richer context
- 11 speech tones (Conversational, Formal, Enthusiastic, etc.)
- Configurable target duration (5–60 min) with automatic per-slide time budgeting

### Teleprompter Overlay
- Floating, always-on-top window — works over video calls, screen shares, anything
- Karaoke-style word highlighting synced to your speaking pace
- Punctuation-aware pacing (commas, periods, ellipses, em dashes add natural pauses)
- Stage direction badges with countdown timers
- "Next slide" transition banner with configurable dwell time
- Click-through mode (window passes mouse events through)
- Play countdown (2–5 seconds) before starting
- Adjustable WPM (60–250), font size (10–48pt), background and window opacity

### Keyboard Shortcuts

All global shortcuts use `Cmd+Shift+`:

| Key | Action |
|-----|--------|
| `T` | Toggle teleprompter |
| `P` | Play / Pause |
| `Up/Down` | Adjust WPM |
| `Left/Right` | Previous / Next slide |
| `+/-` | Font size |
| `[/]` | Window opacity |
| `L` | Toggle click-through |

## Getting Started

### Requirements
- macOS 15+ (Sonoma)
- Xcode 16+

### Build & Run
1. Clone the repo
2. Open `Teleprompter.xcodeproj` in Xcode
3. Build and run (`Cmd+R`)
4. Import a `.pptx` file or create a new script
5. Click **Refine with AI** to open the script assistant
6. Click **Present** to launch the teleprompter overlay

### AI Provider Setup

**Apple On-Device** — works out of the box on supported hardware, no configuration needed.

**LM Studio** — install [LM Studio](https://lmstudio.ai), load a model, and start the local server. The app connects to `localhost:1234` by default (configurable in Settings).

**MLX Local Models** — browse and download models from Hugging Face directly in Settings > Models. Runs natively on Apple Silicon.

**Claude Code CLI** — install with `npm install -g @anthropic-ai/claude-code` and ensure the `claude` binary is in your PATH.

## Project Structure

```
Teleprompter/
├── LLM/                  # LLM provider protocol + implementations
│   ├── LLMProvider.swift         # Protocol, SpeechTone enum
│   ├── FoundationModelProvider   # Apple on-device
│   ├── LMStudioProvider          # OpenAI-compatible API
│   ├── MLXProvider               # Apple Silicon native inference
│   ├── MLXModelManager           # Model discovery & download
│   └── ClaudeCLIProvider         # Claude Code CLI integration
├── Models/               # SwiftData models
│   ├── Script.swift
│   ├── ScriptSection.swift
│   └── PersistedChatMessage.swift
├── PPTX/                 # PowerPoint parser (ZIP + XML extraction)
├── Services/             # Business logic
│   ├── ConversationManager       # Chat + streaming orchestration
│   ├── PromptTemplates           # System prompt builder
│   ├── AppSettings               # UserDefaults wrapper
│   ├── ScriptBackupManager       # Auto-backups
│   ├── SlideImageStore           # File-based image caching
│   └── AsyncSemaphore            # Concurrency control
├── Teleprompter/         # Overlay window management
│   ├── TeleprompterWindowController  # NSPanel lifecycle
│   ├── TeleprompterState             # Playback state machine
│   └── GlobalShortcutManager         # Keyboard shortcuts
├── Views/
│   ├── ScriptManager/    # Main editor, sidebar, detail view
│   ├── ScriptAssistant/  # Chat panel, preview, markdown renderer
│   ├── Teleprompter/     # Overlay text, controls, stage directions
│   ├── Components/       # Shared UI components
│   └── Settings/         # Preferences, model manager
└── Utilities/            # ReadTimeEstimator, ColorHex
```

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Author

Made with <3 by [Danny Rodriguez](https://github.com/darit)
