# Script Assistant Window UX Redesign

## Problem

The current Script Assistant chat interface feels cramped and forces excessive scrolling to read AI responses. The 13pt font, 500pt max-width bubbles, tight 12pt spacing, and iMessage-style bubble alignment don't serve long-form AI content well. Additionally, the script preview only updates after streaming completes, missing an opportunity for real-time feedback.

## Goals

- Make the chat panel spacious, readable, and comfortable for long-form content
- Provide real-time script preview updates as the AI streams its response
- Match modern AI chat interface patterns (Claude.ai, ChatGPT) with flat layout
- Add essential interaction features: stop generation, copy messages, regenerate, scroll-to-bottom
- Support block-level markdown for structured assistant responses

## Non-Goals

- Conversation branching or forking
- Message editing or selective deletion
- Sidebar navigation or conversation history browser
- Voice input or file attachments

---

## Section 1: Window & Layout

- **Default window size:** 960w x 720h (up from ~800x600)
- **Minimum window size:** 800w x 600h
- **HSplitView** retained with both panels equally weighted (~50/50)
- **Chat panel minimum width:** 400pt
- **Script preview minimum width:** 350pt
- **Top bar:** Compact single row -- title left, provider + duration center, clear + done right. Height ~40pt.
- **Persistent resize:** Panel proportions remembered via `@AppStorage` so the user's preferred split persists across sessions.

## Section 2: Chat Message Layout (Flat Design)

- **No bubbles.** Messages stack full-width within the chat panel.
- **Role labels:** "You" and "Assistant" in 11pt semibold above each message, secondary color.
- **Body text:** 15pt system font, line spacing 6pt (~1.5 line height).
- **Message padding:** 16pt horizontal, 12pt vertical.
- **Between messages:** 24pt vertical gap.
- **Separator:** Subtle 0.5pt divider line between conversation turns using `quaternary` color.
- **No background tint** on either user or assistant messages. Role labels handle differentiation.
- **Max-width cap removed.** Messages use the full available width of the chat panel (no 500pt limit, no 60pt spacers).
- **Text selection** enabled on all messages.

## Section 3: Input Area

- **Auto-growing text field** with vertical axis, min 1 line, max 8 lines.
- **Rounded container:** 12pt corner radius, subtle border using `quaternary` color, `ultraThinMaterial` background.
- **Padding inside input:** 12pt horizontal, 10pt vertical.
- **Send button:** Inside the input container, bottom-right. Arrow icon at 24pt. Disabled when input is empty or streaming.
- **Stop button:** Replaces send button during streaming. Red-tinted square-in-circle icon (stop.circle.fill), same position. Cancels generation immediately; partial response stays visible in chat.
- **Placeholder text:** "Ask about your script..." in secondary color.
- **Separation from messages:** 16pt gap above the input area.
- **Submit on Enter**, Shift+Enter for newline.

## Section 4: Live Streaming Preview

- **Real-time script updates:** As the assistant streams its response, parse `[SCRIPT_START slide=N]` markers as they arrive (not just after completion). Update the corresponding slide in the preview panel immediately.
- **Visual indicator:** When a slide is being actively updated via streaming, show a subtle pulsing border or highlight on that slide card.
- **Partial content:** Display whatever text has been received so far for a slide, even mid-sentence. Final version replaces it when streaming completes.
- **Auto-scroll preview:** When a slide update is detected during streaming, auto-scroll the preview panel to show that slide.

### Provider Streaming Details

**Claude CLI:** Use `claude -p --output-format stream-json --verbose --include-partial-messages`. Emits NDJSON in real-time. Text chunks arrive as `stream_event` with `event.delta.type == "text_delta"`. Consume via `Process` + `Pipe` with `readabilityHandler` on the file handle.

**LM Studio:** Standard OpenAI-compatible SSE at `POST /v1/chat/completions` with `stream: true`. Chunks arrive as `data: {... "delta": {"content": "token"} ...}`, terminated by `data: [DONE]`. Consume via `URLSession.shared.bytes(for:)` async line iteration.

## Section 5: Scroll & Navigation

- **Sticky auto-scroll:** When user is near the bottom (~100pt threshold), auto-scroll follows new content smoothly during streaming.
- **Manual scroll respected:** If user scrolls up to read history, auto-scroll stops immediately.
- **Scroll-to-bottom button:** Floating circular button (chevron.down icon) in the bottom-right of the chat panel, visible when the user is scrolled up.
- **Badge indicator:** Small dot on the scroll-to-bottom button when new content arrived while scrolled up.
- **Smooth animation:** Tapping the button smooth-scrolls to the latest message.

## Section 6: Typing Indicator & Streaming UX

- **Before first token:** Animated typing indicator -- three small dots with staggered pulsing opacity, positioned where the assistant message will appear. "Assistant" role label above.
- **During streaming:** Dots replaced by actual text as tokens arrive, rendered with the same flat message styling (15pt, full-width).
- **Blinking cursor:** Thin vertical bar (caret) pulses at the end of streaming text, disappears when generation completes.
- **Stop button active** throughout streaming (see Section 3).

## Section 7: Message Actions

- **On hover** over any message, a small action bar appears in the top-right corner:
  - **Copy** (doc.on.doc icon) -- copies message text to clipboard.
  - **Regenerate** (arrow.counterclockwise icon) -- only on the last assistant message. Re-sends previous user prompt for a new response, replacing the old one.
- **Action bar styling:** Small icon buttons (14pt), secondary color, subtle background pill. Appears on hover, fades on mouse exit.
- **No message editing or deletion.** Clear history remains the reset mechanism.

## Section 8: Markdown Rendering

Upgrade from inline-only to block-level markdown in assistant messages:

- **Bold/italic/inline code** -- already supported, keep as-is.
- **Bullet and numbered lists** -- proper indentation (20pt per level).
- **Code blocks** -- SF Mono 13pt, darker background, 12pt padding, 8pt corner radius, copy button in top-right.
- **Headings** -- h3/h4 support with semibold weight and proportional sizing.
- **Blockquotes** -- left border (3pt, tertiary color), indented, slightly muted text.
- **Implementation:** Use `AttributedString(markdown:)` with full parsing options instead of `inlineOnlyPreservingWhitespace`. For code blocks, detect fenced code markers and render in a custom container view.
- **Streaming safety:** Buffer incomplete markdown blocks during streaming to avoid rendering partial syntax.

---

## Files Affected

| File | Changes |
|------|---------|
| `ScriptAssistantView.swift` | Window sizing, top bar layout, panel proportions, AppStorage for resize |
| `ChatPanelView.swift` | Flat message layout, scroll-to-bottom button, input area redesign, stop button |
| `ChatMessageView.swift` | Remove bubbles, flat full-width layout, role labels, hover actions, markdown upgrade |
| `ConversationManager.swift` | Stop/cancel streaming, regenerate last message, live script parsing during stream |
| `LMStudioProvider.swift` | Verify SSE streaming works for live preview |
| `ScriptPreviewPanel.swift` | Pulsing indicator on actively-updating slides, auto-scroll to active slide |
| New: `TypingIndicatorView.swift` | Animated three-dot typing indicator |
| New: `ScrollToBottomButton.swift` | Floating scroll button with badge |
| New: `MarkdownContentView.swift` | Block-level markdown rendering with code blocks |

## Design Values

| Property | Current | New |
|----------|---------|-----|
| Window default | ~800x600 | 960x720 |
| Body font | 13pt | 15pt |
| Line spacing | 4pt | 6pt |
| Message gap | 12pt | 24pt |
| Message max-width | 500pt | Full panel width |
| Message style | Bubbles with alignment | Flat with role labels |
| Input max lines | 5 | 8 |
| Markdown support | Inline only | Block-level |
| Preview updates | After completion | Live during streaming |
