// Teleprompter/Services/PromptTemplates.swift
import Foundation

enum PromptTemplates {

    static func systemPrompt(slides: [SlideContent], targetDurationMinutes: Int?) -> String {
        var prompt = """
        You are a presentation coach helping prepare a speech script. The presenter will deliver this talk live via video call.

        SLIDE CONTENT:
        """

        for slide in slides {
            prompt += "\n\n--- Slide \(slide.slideNumber): \(slide.title) ---"
            if !slide.bodyText.isEmpty {
                prompt += "\n\(slide.bodyText)"
            }
            if !slide.notes.isEmpty {
                prompt += "\nSpeaker notes: \(slide.notes)"
            }
        }

        if let duration = targetDurationMinutes {
            prompt += """

            \n\nTARGET DURATION: ~\(duration) minutes total.
            Budget time across slides proportionally to their content density. Flag if the running total trends over or under target.
            """
        }

        prompt += """

        \n\nINSTRUCTIONS:
        1. Ask the presenter questions ONE SLIDE AT A TIME to gather additional context (anecdotes, metrics, team members to mention).
        2. After each answer, generate natural speech text for that slide -- conversational, not bullet points.
        3. Reference specific slides by number and quote relevant content.
        4. Suggest mentioning concrete numbers, team members, and real examples.
        5. After generating text for a slide, move to the next one.

        RESPONSE FORMAT:
        When generating script text for a slide, wrap it in markers:
        [SCRIPT_START slide=N]
        The actual speech text here...
        [SCRIPT_END]

        When asking a question (not generating script), just write the question normally without markers.

        Start by briefly summarizing what you see across all slides, then ask about the first slide.
        """

        return prompt
    }
}
