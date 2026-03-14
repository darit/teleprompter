// Teleprompter/Utilities/ReadTimeEstimator.swift
import Foundation

enum ReadTimeEstimator {
    static func estimateDuration(for text: String, wordsPerMinute: Double = 160) -> TimeInterval {
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
