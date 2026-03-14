import Foundation

/// Presentation style presets that shape how AI generates speech scripts.
enum SpeechTone: String, CaseIterable, Identifiable {
    // General tones
    case conversational = "Conversational"
    case professional = "Professional"
    case motivational = "Motivational"
    case educational = "Educational"
    case storytelling = "Storytelling"
    // Presentation types
    case sprintDemo = "Sprint Demo"
    case salesPitch = "Sales Pitch"
    case salesDiscovery = "Sales Discovery"
    case keynote = "Keynote"
    case teamUpdate = "Team Update"
    case investorPitch = "Investor Pitch"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conversational, .professional, .motivational, .educational, .storytelling:
            return rawValue
        case .sprintDemo: return "Sprint Demo"
        case .salesPitch: return "Sales Pitch"
        case .salesDiscovery: return "Discovery Call"
        case .keynote: return "Keynote"
        case .teamUpdate: return "Team Update"
        case .investorPitch: return "Investor Pitch"
        }
    }

    var category: String {
        switch self {
        case .conversational, .professional, .motivational, .educational, .storytelling:
            return "Tone"
        case .sprintDemo, .salesPitch, .salesDiscovery, .keynote, .teamUpdate, .investorPitch:
            return "Presentation"
        }
    }

    var description: String {
        switch self {
        case .conversational:
            return "Relaxed and natural, like talking to a colleague. Uses humor, contractions, and casual phrasing."
        case .professional:
            return "Clear, authoritative, and data-driven. Measured pacing with industry terminology."
        case .motivational:
            return "Energetic and emotionally resonant. Builds to crescendos with repetition and calls to action."
        case .educational:
            return "Patient and structured. Uses analogies, examples, and step-by-step explanations."
        case .storytelling:
            return "Narrative-driven with vivid imagery. Opens with hooks, weaves anecdotes throughout."
        case .sprintDemo:
            return """
            Sprint/iteration demo style. Lead with what shipped, not how. \
            Show outcomes and impact, not implementation details. \
            Keep it brisk -- one clear "here's what changed" per feature, then a quick live walkthrough cue. \
            Use plain language, not Jira ticket titles. Celebrate the team's work without overselling. \
            End each section with what's next or what you need from stakeholders.
            """
        case .salesPitch:
            return """
            Persuasive sales presentation. Open with the prospect's pain point, not your product. \
            Paint the "before and after" -- make the cost of inaction vivid. \
            Use social proof: customer names, concrete metrics ("cut onboarding from 3 weeks to 3 days"). \
            Build urgency without being pushy. Every slide should answer "why should I care?" \
            Close with a clear, specific next step -- not a vague "let's connect."
            """
        case .salesDiscovery:
            return """
            Discovery call / consultative selling style. This is about asking, not telling. \
            Lead with open-ended questions and genuine curiosity about their situation. \
            Acknowledge their challenges before introducing ideas. Mirror their language. \
            Share brief, relevant stories ("we saw something similar at...") to build credibility. \
            Keep your product mentions light -- frame as possibilities, not pitches. \
            End each section by confirming you understood correctly.
            """
        case .keynote:
            return """
            High-energy keynote / conference talk. Open with a bold statement or surprising fact that reframes the topic. \
            Use the stage -- reference visuals, invite audience reactions, vary your energy. \
            Build a narrative arc: setup, tension, resolution. Make the audience feel something. \
            Use callbacks to earlier points for cohesion. Aim for quotable one-liners. \
            Close with a memorable takeaway they'll repeat to colleagues.
            """
        case .teamUpdate:
            return """
            Internal team or all-hands update. Warm but efficient -- respect everyone's time. \
            Lead with headlines: what happened, what it means, what's next. \
            Be transparent about blockers and risks, not just wins. \
            Use "we" language to reinforce shared ownership. Skip the corporate jargon. \
            Call out individual contributions by name. End with clear action items and owners.
            """
        case .investorPitch:
            return """
            Investor / fundraising pitch. Lead with the market opportunity, not your solution. \
            Make the problem feel urgent and large ("$X billion market, growing Y% annually"). \
            Show traction with real numbers: revenue, users, growth rate, retention. \
            Be specific about the ask and how you'll deploy capital. \
            Address the "why now" and "why us" questions before they're asked. \
            Confidence without arrogance -- acknowledge risks, then explain your edge.
            """
        }
    }
}

protocol LLMProvider: Sendable {
    /// Stream a response from the LLM given a conversation history.
    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String>

    /// Human-readable name for this provider (e.g. "Claude Code CLI (Sonnet)").
    var displayName: String { get }

    /// Whether this provider is currently available (e.g. CLI found in PATH).
    var isAvailable: Bool { get async }

    /// Whether this provider can handle multiple concurrent generation requests.
    /// Local models sharing a single GPU should return `false`.
    var supportsParallelGeneration: Bool { get }
}

// Default: existing providers (Claude CLI, LM Studio) support parallel generation
extension LLMProvider {
    var supportsParallelGeneration: Bool { true }
}
