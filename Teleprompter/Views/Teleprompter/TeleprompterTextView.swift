import SwiftUI

// MARK: - Timeline model

/// Display info for a stage direction marker.
private struct DirectionInfo {
    let label: String
    let icon: String
}

/// A single word with its timing within the section.
private struct TimedWord {
    let text: String
    /// Absolute start time (seconds from section start)
    let startTime: Double
    /// Absolute end time
    let endTime: Double
    /// Which paragraph (line) this word belongs to
    let paragraphIndex: Int
    /// Non-nil if this word is a stage direction (e.g. [PAUSE])
    let direction: DirectionInfo?
}

/// Pre-computed timeline for a section's content.
private struct SectionTimeline {
    let words: [TimedWord]
    let totalDuration: Double
    /// Time when all words finish (before end-of-slide dwell)
    let wordsEndTime: Double
    /// Paragraph count
    let paragraphCount: Int
    /// Start time of each paragraph (for scroll tracking)
    let paragraphStartTimes: [Double]
}

struct TeleprompterTextView: View {
    @Bindable var state: TeleprompterState
    @State private var timer: Timer?
    @State private var sectionElapsed: Double = 0
    @State private var sectionDuration: Double = 0
    @State private var timeline: SectionTimeline?
    @State private var currentParaIndex: Int = 0
    @State private var scrollProxy: ScrollViewProxy?
    /// Seconds remaining in the end-of-slide transition countdown (0 = not in transition)
    @State private var transitionCountdown: Double = 0
    /// Seconds remaining in the initial play countdown (0 = not counting down)
    @State private var playCountdown: Int = 0

    private var settings: AppSettings { .shared }
    private var transitionDwell: Double { settings.showNextSlideBanner ? settings.transitionDwellSeconds : 0.0 }
    private var playCountdownSeconds: Int { settings.showPlayCountdown ? settings.playCountdownSeconds : 0 }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Top spacer so content can scroll into the visible zone
                        Spacer()
                            .frame(height: 32)

                        ForEach(Array(state.sections.enumerated()), id: \.element.id) { index, section in
                            sectionView(section: section, index: index)
                                .id("sectionBlock-\(index)")
                        }

                        Spacer()
                            .frame(height: 300)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .mask {
                    VStack(spacing: 0) {
                        // Top fade — gentle so section headers stay readable
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)

                        Color.white

                        // Bottom fade — eased curve for natural falloff
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.6), location: 0.4),
                                .init(color: .white.opacity(0.15), location: 0.75),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                    }
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: state.currentSectionIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo("section-\(newIndex)", anchor: .top)
                    }
                    if state.isPlaying {
                        startAutoAdvance()
                    } else {
                        sectionElapsed = 0
                        timeline = nil
                    }
                }
                .onChange(of: state.isPlaying) { _, playing in
                    if playing {
                        beginPlayWithCountdown()
                    } else {
                        cancelPlayCountdown()
                        stopAutoAdvance()
                    }
                }
                .onChange(of: state.scrollSpeed) {
                    if state.isPlaying && playCountdown == 0 {
                        rebuildTimelineKeepingPosition()
                    }
                }
                .onChange(of: currentParaIndex) { _, newPara in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // Anchor at upper-third so the speaker has more look-ahead text visible
                        proxy.scrollTo("para-\(state.currentSectionIndex)-\(newPara)", anchor: UnitPoint(x: 0.5, y: 0.33))
                    }
                }
            }

            // Transition banner overlay pinned to bottom of viewport
            if settings.showNextSlideBanner,
               transitionCountdown > 0,
               state.currentSectionIndex < state.sections.count - 1 {
                let next = state.sections[state.currentSectionIndex + 1]
                VStack {
                    Spacer()
                    slideTransitionBanner(nextSection: next, countdown: transitionCountdown)
                        .padding(.horizontal, 0)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Play countdown overlay
            if playCountdown > 0 {
                playCountdownOverlay
            }
        }
        .onDisappear {
            stopAutoAdvance()
        }
    }

    // MARK: - Play countdown

    private var playCountdownOverlay: some View {
        VStack(spacing: 12) {
            Text("\(playCountdown)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.7))
                .contentTransition(.numericText())

            Text("GET READY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.interactive(), in: .rect)
    }

    private func beginPlayWithCountdown() {
        // If resuming mid-section, skip countdown
        if timeline != nil && sectionElapsed > 0 {
            resumeAutoAdvance()
            return
        }

        playCountdown = playCountdownSeconds
        countdownTick()
    }

    private func countdownTick() {
        guard playCountdown > 0, state.isPlaying else {
            playCountdown = 0
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard state.isPlaying else {
                playCountdown = 0
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                playCountdown -= 1
            }
            if playCountdown > 0 {
                countdownTick()
            } else {
                resumeAutoAdvance()
            }
        }
    }

    private func cancelPlayCountdown() {
        playCountdown = 0
    }

    // MARK: - Section rendering

    private func sectionView(section: TeleprompterSection, index: Int) -> some View {
        let isCurrent = index == state.currentSectionIndex
        let isPast = index < state.currentSectionIndex
        let isJustBefore = index == state.currentSectionIndex - 1
        let accentColor = Color(hex: section.accentColorHex) ?? .blue

        return VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 8) {
                SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)

                Text(section.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isCurrent ? accentColor : .secondary)

                Spacer()

                if isCurrent && state.isPlaying && playCountdown == 0 && settings.showSectionTimer {
                    Text(formatTimeRemaining())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if isPast {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green.opacity(0.6))
                }
            }
            .id("section-\(index)")
            .padding(.top, index > 0 ? 20 : 0)
            .padding(.bottom, 4)

            // Section divider
            if index > 0 && !isCurrent {
                Rectangle()
                    .fill(accentColor.opacity(isPast ? 0.1 : 0.2))
                    .frame(height: 1)
                    .padding(.bottom, 8)
            }

            // Content
            if isCurrent {
                currentSectionContent(content: section.content, accentColor: accentColor)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor)
                            .frame(width: 3)
                            .padding(.vertical, 2)
                    }
            } else if isJustBefore {
                previousSectionTail(content: section.content, accentColor: accentColor)
            } else if !isPast {
                plainSectionText(content: section.content, isPast: false)
            }
            // Past sections (other than just-before) show nothing - keeps view clean
        }
        .padding(.bottom, 12)
        .padding(.horizontal, 4)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.05))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            }
        }
    }

    // MARK: - Current section (sing-along)

    private func currentSectionContent(content: String, accentColor: Color) -> some View {
        let paragraphs = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return VStack(alignment: .leading, spacing: state.fontSize * 0.4) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { pIdx, paragraph in
                coloredParagraph(
                    paragraph.trimmingCharacters(in: .whitespaces),
                    paragraphIndex: pIdx,
                    accentColor: accentColor
                )
                .id("para-\(state.currentSectionIndex)-\(pIdx)")
            }
        }
    }

    private func slideTransitionBanner(nextSection: TeleprompterSection, countdown: Double) -> some View {
        let nextColor = Color(hex: nextSection.accentColorHex) ?? .blue
        let seconds = Int(ceil(countdown))
        let preview = nextSectionPreview(nextSection.content, maxLines: 1)

        return VStack(spacing: 0) {
            Rectangle()
                .fill(nextColor)
                .frame(height: 2)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(0..<min(seconds, 4), id: \.self) { i in
                        Circle()
                            .fill(nextColor.opacity(Double(min(seconds, 4) - i) / 4.0))
                            .frame(width: 6, height: 6)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(nextColor)

                    Text(nextSection.label)
                        .font(.system(size: state.fontSize * 0.7, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }

                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: state.fontSize * 0.65))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Text("\(seconds)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(nextColor)

                Button {
                    skipTransition()
                } label: {
                    Text("SKIP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(nextColor.opacity(0.4))
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(white: 0.1))
    }

    /// Extracts the first couple of lines from the next section, stripping stage directions.
    private func nextSectionPreview(_ content: String, maxLines: Int) -> String {
        content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("[")
            }
            .prefix(maxLines)
            .joined(separator: "\n")
    }

    private func skipTransition() {
        guard let tl = timeline else { return }
        sectionElapsed = tl.totalDuration
    }

    private func coloredParagraph(_ text: String, paragraphIndex: Int, accentColor: Color) -> some View {
        guard let tl = timeline else {
            return AnyView(
                StageDirectionRenderer.render(text)
                    .font(.system(size: state.fontSize))
                    .lineSpacing(state.fontSize * 0.5)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }

        let paraWords = tl.words.filter { $0.paragraphIndex == paragraphIndex }
        guard !paraWords.isEmpty else {
            return AnyView(EmptyView())
        }

        // Group consecutive regular words; stage directions are their own groups
        enum WordGroup {
            case text(words: [TimedWord])
            case direction(word: TimedWord, info: DirectionInfo)
        }

        var groups: [WordGroup] = []
        var currentTextGroup: [TimedWord] = []

        for word in paraWords {
            if let info = word.direction {
                if !currentTextGroup.isEmpty {
                    groups.append(.text(words: currentTextGroup))
                    currentTextGroup = []
                }
                groups.append(.direction(word: word, info: info))
            } else {
                currentTextGroup.append(word)
            }
        }
        if !currentTextGroup.isEmpty {
            groups.append(.text(words: currentTextGroup))
        }

        var result = Text("")
        for (idx, group) in groups.enumerated() {
            if idx > 0 { result = result + Text(" ") }
            switch group {
            case .text(let words):
                result = result + coloredTextGroup(words: words, accentColor: accentColor)
            case .direction(let word, let info):
                result = result + stageDirectionBadge(word: word, info: info)
            }
        }

        return AnyView(
            result
                .font(.system(size: state.fontSize))
                .lineSpacing(state.fontSize * 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    /// Renders a group of regular words with markdown and karaoke coloring.
    private func coloredTextGroup(words: [TimedWord], accentColor: Color) -> Text {
        let rawText = words.map(\.text).joined(separator: " ")
        var attributed = (try? AttributedString(
            markdown: rawText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(rawText)

        let chars = attributed.characters
        var wordRanges: [Range<AttributedString.Index>] = []
        var wordStart: AttributedString.Index?

        for idx in chars.indices {
            if chars[idx] == " " {
                if let start = wordStart {
                    wordRanges.append(start..<idx)
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = idx
            }
        }
        if let start = wordStart {
            wordRanges.append(start..<attributed.endIndex)
        }

        let wordCount = min(wordRanges.count, words.count)
        for i in 0..<wordCount {
            let range = wordRanges[i]
            let word = words[i]
            if sectionElapsed >= word.endTime {
                attributed[range].foregroundColor = .primary
            } else if sectionElapsed >= word.startTime {
                attributed[range].foregroundColor = accentColor
                let existing = attributed[range].inlinePresentationIntent ?? []
                attributed[range].inlinePresentationIntent = existing.union(.stronglyEmphasized)
            } else if sectionElapsed >= word.startTime - (word.endTime - word.startTime) * 2 {
                // Pre-highlight: next 1-2 words get a subtle brightness boost (look-ahead cue)
                attributed[range].foregroundColor = Color.primary.opacity(0.45)
            } else {
                attributed[range].foregroundColor = Color.primary.opacity(0.28)
            }
        }

        return Text(attributed)
    }

    /// Renders a stage direction badge with a countdown timer.
    private func stageDirectionBadge(word: TimedWord, info: DirectionInfo) -> Text {
        let duration = word.endTime - word.startTime
        let seconds = Int(ceil(duration))

        if sectionElapsed >= word.endTime {
            return Text(" \(Image(systemName: info.icon)) \(info.label) ")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow.opacity(0.25))
        } else if sectionElapsed >= word.startTime {
            let remaining = Int(ceil(word.endTime - sectionElapsed))
            return Text(" \(Image(systemName: info.icon)) \(info.label) \(remaining)s ")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
        } else {
            return Text(" \(Image(systemName: info.icon)) \(info.label) \(seconds)s ")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow.opacity(0.4))
        }
    }

    // MARK: - Previous section tail

    private func previousSectionTail(content: String, accentColor: Color) -> some View {
        let paragraphs = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let tail = paragraphs.suffix(2)

        return VStack(alignment: .leading, spacing: state.fontSize * 0.4) {
            ForEach(Array(tail.enumerated()), id: \.offset) { _, paragraph in
                StageDirectionRenderer.render(paragraph.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: state.fontSize))
                    .lineSpacing(state.fontSize * 0.5)
                    .foregroundStyle(.tertiary)
                    .opacity(0.35)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 12)
    }

    // MARK: - Plain section text

    private func plainSectionText(content: String, isPast: Bool) -> some View {
        StageDirectionRenderer.render(content)
            .font(.system(size: state.fontSize))
            .lineSpacing(state.fontSize * 0.5)
            .foregroundStyle(isPast ? .tertiary : .secondary)
            .opacity(isPast ? 0.35 : 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: state.currentSectionIndex)
    }

    // MARK: - Time display

    private func formatTimeRemaining() -> String {
        let remaining = max(0, sectionDuration - sectionElapsed)
        let seconds = Int(remaining)
        return "\(seconds)s"
    }

    // MARK: - Build timeline

    // MARK: - Stage direction definitions

    private static let knownDirections: [(pattern: String, icon: String, baseDuration: Double)] = [
        ("[PAUSE]", "pause.fill", 2.0),
        ("[SLOW]", "tortoise.fill", 1.0),
        ("[LOOK AT CAMERA]", "eye.fill", 2.0),
        ("[SHOW SLIDE]", "rectangle.on.rectangle.angled", 1.5),
        ("[BREATHE]", "wind", 3.0),
    ]

    private static func parseDirection(_ text: String) -> (info: DirectionInfo, baseDuration: Double)? {
        let upper = text.uppercased()
        for (pattern, icon, dur) in knownDirections {
            if upper == pattern {
                let label = pattern.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                return (DirectionInfo(label: label, icon: icon), dur)
            }
        }
        // Unknown [DIRECTION] pattern
        if upper.hasPrefix("[") && upper.hasSuffix("]") {
            let label = String(upper.dropFirst().dropLast())
            guard !label.hasPrefix("SCRIPT_START") && !label.hasPrefix("SCRIPT_END") else { return nil }
            guard label.allSatisfy({ $0.isUppercase || $0.isWhitespace }) else { return nil }
            return (DirectionInfo(label: label, icon: "text.bubble"), 1.5)
        }
        return nil
    }

    // MARK: - Build timeline

    private func buildTimeline(for content: String, wpm: Double) -> SectionTimeline? {
        let paragraphs = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !paragraphs.isEmpty else { return nil }

        // Pause durations based on speech corpus research.
        // All scale proportionally with word duration (basePause = secondsPerWord).
        let secondsPerWord = 60.0 / max(60, wpm)
        let basePause = secondsPerWord
        let commaPause      = basePause * 0.5    // ~0.2s at 150 WPM
        let semicolonPause   = basePause * 0.7    // ~0.28s
        let colonPause       = basePause * 0.85   // ~0.34s
        let periodPause      = basePause * 1.0    // ~0.4s
        let questionPause    = basePause * 1.0
        let exclamationPause = basePause * 0.9    // slightly shorter, more energetic
        let ellipsisPause    = basePause * 1.5    // ~0.6s, deliberate thinking pause
        let dashPause        = basePause * 0.35   // ~0.14s, brief structural pause
        let breathPause      = periodPause * 1.5  // paragraph boundary ~1.5x sentence
        let speedFactor = 120.0 / max(60, wpm)    // for stage direction scaling
        let endOfSlideDwell = transitionDwell

        var words: [TimedWord] = []
        var currentTime: Double = 0
        var paragraphStarts: [Double] = []

        for (pIdx, paragraph) in paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            let rawWords = trimmed.split(separator: " ").map(String.init)
            guard !rawWords.isEmpty else { continue }

            // Merge multi-word stage directions: [LOOK AT CAMERA] -> single token
            var mergedWords: [String] = []
            var i = 0
            while i < rawWords.count {
                if rawWords[i].hasPrefix("[") {
                    if rawWords[i].hasSuffix("]") {
                        mergedWords.append(rawWords[i])
                        i += 1
                    } else {
                        var merged = rawWords[i]
                        i += 1
                        while i < rawWords.count {
                            merged += " " + rawWords[i]
                            if rawWords[i].hasSuffix("]") { i += 1; break }
                            i += 1
                        }
                        mergedWords.append(merged)
                    }
                } else {
                    mergedWords.append(rawWords[i])
                    i += 1
                }
            }

            paragraphStarts.append(currentTime)

            for word in mergedWords {
                if let dir = Self.parseDirection(word) {
                    let dirDuration = dir.baseDuration * speedFactor
                    words.append(TimedWord(
                        text: word,
                        startTime: currentTime,
                        endTime: currentTime + dirDuration,
                        paragraphIndex: pIdx,
                        direction: dir.info
                    ))
                    currentTime += dirDuration
                } else {
                    words.append(TimedWord(
                        text: word,
                        startTime: currentTime,
                        endTime: currentTime + secondsPerWord,
                        paragraphIndex: pIdx,
                        direction: nil
                    ))
                    currentTime += secondsPerWord

                    // Punctuation pauses (research-backed hierarchy)
                    let stripped = word.trimmingCharacters(in: .init(charactersIn: "\"'*)]}"))
                    if stripped.hasSuffix("...") || stripped.hasSuffix("\u{2026}") {
                        currentTime += ellipsisPause
                    } else if stripped.hasSuffix("?") {
                        currentTime += questionPause
                    } else if stripped.hasSuffix("!") {
                        currentTime += exclamationPause
                    } else if stripped.hasSuffix(".") {
                        currentTime += periodPause
                    } else if stripped.hasSuffix(":") {
                        currentTime += colonPause
                    } else if stripped.hasSuffix(";") {
                        currentTime += semicolonPause
                    } else if stripped.hasSuffix(",") {
                        currentTime += commaPause
                    } else if stripped.hasSuffix("--") || stripped.hasSuffix("\u{2014}") {
                        currentTime += dashPause
                    }
                }
            }

            let isSentenceEnd = trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
            let isLast = pIdx == paragraphs.count - 1

            if !isLast && isSentenceEnd {
                currentTime += breathPause
            }
        }

        let wordsEnd = currentTime
        currentTime += endOfSlideDwell

        return SectionTimeline(
            words: words,
            totalDuration: currentTime,
            wordsEndTime: wordsEnd,
            paragraphCount: paragraphs.count,
            paragraphStartTimes: paragraphStarts
        )
    }

    // MARK: - Auto-advance

    private func startAutoAdvance() {
        stopAutoAdvance()

        guard state.isPlaying,
              state.currentSectionIndex < state.sections.count else {
            state.isPlaying = false
            return
        }

        let section = state.sections[state.currentSectionIndex]
        timeline = buildTimeline(for: section.content, wpm: state.scrollSpeed)
        guard let tl = timeline else {
            advanceToNextSection()
            return
        }

        sectionDuration = tl.totalDuration
        sectionElapsed = 0
        currentParaIndex = 0
        transitionCountdown = 0

        startTimer()
    }

    /// Rebuild the timeline with the new WPM while staying on the same word.
    private func rebuildTimelineKeepingPosition() {
        guard state.isPlaying,
              state.currentSectionIndex < state.sections.count,
              let oldTimeline = timeline else {
            return
        }

        // Find which word we're currently on
        var currentWordIndex = 0
        for (i, word) in oldTimeline.words.enumerated() {
            if sectionElapsed >= word.startTime {
                currentWordIndex = i
            }
        }

        let section = state.sections[state.currentSectionIndex]
        guard let newTimeline = buildTimeline(for: section.content, wpm: state.scrollSpeed),
              !newTimeline.words.isEmpty else {
            return
        }

        // Map elapsed time to the same word position in the new timeline
        let clampedIndex = min(currentWordIndex, newTimeline.words.count - 1)
        let newElapsed = newTimeline.words[clampedIndex].startTime

        timer?.invalidate()
        timer = nil
        timeline = newTimeline
        sectionDuration = newTimeline.totalDuration
        sectionElapsed = newElapsed
        startTimer()
    }

    private func resumeAutoAdvance() {
        guard state.isPlaying,
              state.currentSectionIndex < state.sections.count else {
            state.isPlaying = false
            return
        }

        if timeline == nil {
            startAutoAdvance()
            return
        }

        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = nil
        let interval: TimeInterval = 1.0 / 20.0
        // Use common run loop mode so the timer fires even during tracking
        // and defer state mutations to avoid CA commit conflicts
        timer = Timer(timeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                guard state.isPlaying else {
                    stopAutoAdvance()
                    return
                }
                tickPlayback(interval)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tickPlayback(_ dt: Double) {
        guard let tl = timeline else {
            advanceToNextSection()
            return
        }

        sectionElapsed += dt

        // Track which paragraph we're in for auto-scroll
        var newPara = 0
        for (i, startTime) in tl.paragraphStartTimes.enumerated() {
            if sectionElapsed >= startTime {
                newPara = i
            }
        }
        if newPara != currentParaIndex {
            currentParaIndex = newPara
        }

        // Track transition countdown
        let isNotLastSection = state.currentSectionIndex < state.sections.count - 1
        if sectionElapsed >= tl.wordsEndTime && isNotLastSection {
            let newCountdown = max(0, tl.totalDuration - sectionElapsed)
            transitionCountdown = newCountdown
        } else {
            transitionCountdown = 0
        }

        // Check if section is complete
        if sectionElapsed >= tl.totalDuration {
            transitionCountdown = 0
            advanceToNextSection()
        }
    }

    private func advanceToNextSection() {
        stopAutoAdvance()
        if state.currentSectionIndex < state.sections.count - 1 {
            if settings.autoAdvance {
                state.jumpForward()
                startAutoAdvance()
            } else {
                // Pause at end of section, user must manually advance
                sectionElapsed = sectionDuration
                state.isPlaying = false
            }
        } else {
            sectionElapsed = sectionDuration
            state.isPlaying = false
        }
    }

    private func stopAutoAdvance() {
        timer?.invalidate()
        timer = nil
    }
}
