// Teleprompter/Services/AppSettings.swift
import Foundation
import SwiftUI

/// Centralized app settings backed by UserDefaults via @AppStorage.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Teleprompter: Next Slide Banner

    /// Show the "next slide" transition banner
    var showNextSlideBanner: Bool {
        get { UserDefaults.standard.object(forKey: "showNextSlideBanner") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showNextSlideBanner") }
    }

    /// Seconds to dwell at end of slide before auto-advancing (transition banner duration)
    var transitionDwellSeconds: Double {
        get { UserDefaults.standard.object(forKey: "transitionDwellSeconds") as? Double ?? 2.0 }
        set { UserDefaults.standard.set(newValue, forKey: "transitionDwellSeconds") }
    }

    // MARK: - Teleprompter: Play Countdown

    /// Show the "3, 2, 1" countdown before playback starts
    var showPlayCountdown: Bool {
        get { UserDefaults.standard.object(forKey: "showPlayCountdown") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showPlayCountdown") }
    }

    /// Seconds to count down before starting playback
    var playCountdownSeconds: Int {
        get { UserDefaults.standard.object(forKey: "playCountdownSeconds") as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "playCountdownSeconds") }
    }

    // MARK: - Teleprompter: Display

    /// Show the time remaining for the current section
    var showSectionTimer: Bool {
        get { UserDefaults.standard.object(forKey: "showSectionTimer") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showSectionTimer") }
    }

    /// Show stage direction badges in the teleprompter
    var showStageDirections: Bool {
        get { UserDefaults.standard.object(forKey: "showStageDirections") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showStageDirections") }
    }

    // MARK: - Teleprompter: Behavior

    /// Auto-advance to next slide when the current one finishes
    var autoAdvance: Bool {
        get { UserDefaults.standard.object(forKey: "autoAdvance") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoAdvance") }
    }

    /// Teleprompter window always on top
    var alwaysOnTop: Bool {
        get { UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysOnTop") }
    }

    // MARK: - AI Assistant

    /// Default LLM provider
    var defaultProvider: String {
        get { UserDefaults.standard.string(forKey: "defaultProvider") ?? "lmStudio" }
        set { UserDefaults.standard.set(newValue, forKey: "defaultProvider") }
    }

    /// Max concurrent LLM calls for "Generate All"
    var maxParallelSlides: Int {
        get { UserDefaults.standard.object(forKey: "maxParallelSlides") as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "maxParallelSlides") }
    }

    /// LM Studio base URL
    var lmStudioBaseURL: String {
        get { UserDefaults.standard.string(forKey: "lmStudioBaseURL") ?? "http://localhost:1234" }
        set { UserDefaults.standard.set(newValue, forKey: "lmStudioBaseURL") }
    }
}
