// Teleprompter/Services/AppSettings.swift
import Foundation
import SwiftUI

/// Centralized app settings backed by a suite-scoped UserDefaults
/// that survives Xcode clean builds and app reinstalls.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults(suiteName: "com.dannyrodriguez.Teleprompter.settings")!

    init() {
        migrateFromStandardIfNeeded()
    }

    // MARK: - Teleprompter: Next Slide Banner

    /// Show the "next slide" transition banner
    var showNextSlideBanner: Bool {
        get { defaults.object(forKey: "showNextSlideBanner") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showNextSlideBanner") }
    }

    /// Seconds to dwell at end of slide before auto-advancing (transition banner duration)
    var transitionDwellSeconds: Double {
        get { defaults.object(forKey: "transitionDwellSeconds") as? Double ?? 2.0 }
        set { defaults.set(newValue, forKey: "transitionDwellSeconds") }
    }

    // MARK: - Teleprompter: Play Countdown

    /// Show the "3, 2, 1" countdown before playback starts
    var showPlayCountdown: Bool {
        get { defaults.object(forKey: "showPlayCountdown") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPlayCountdown") }
    }

    /// Seconds to count down before starting playback
    var playCountdownSeconds: Int {
        get { defaults.object(forKey: "playCountdownSeconds") as? Int ?? 3 }
        set { defaults.set(newValue, forKey: "playCountdownSeconds") }
    }

    // MARK: - Teleprompter: Display

    /// Show the time remaining for the current section
    var showSectionTimer: Bool {
        get { defaults.object(forKey: "showSectionTimer") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showSectionTimer") }
    }

    /// Show stage direction badges in the teleprompter
    var showStageDirections: Bool {
        get { defaults.object(forKey: "showStageDirections") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showStageDirections") }
    }

    // MARK: - Teleprompter: Slide Previews

    /// Show slide thumbnails in the teleprompter header
    var showSlideThumbnails: Bool {
        get { defaults.object(forKey: "showSlideThumbnails") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showSlideThumbnails") }
    }

    // MARK: - Teleprompter: Behavior

    /// Auto-advance to next slide when the current one finishes
    var autoAdvance: Bool {
        get { defaults.object(forKey: "autoAdvance") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoAdvance") }
    }

    /// Teleprompter window always on top
    var alwaysOnTop: Bool {
        get { defaults.object(forKey: "alwaysOnTop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alwaysOnTop") }
    }

    // MARK: - AI Assistant

    /// Default LLM provider (auto-detected based on hardware if not set)
    var defaultProvider: String {
        get {
            if let saved = defaults.string(forKey: "defaultProvider") { return saved }
            #if arch(arm64)
            return "Apple On-Device"
            #else
            return "LM Studio (Local)"
            #endif
        }
        set { defaults.set(newValue, forKey: "defaultProvider") }
    }

    /// Max concurrent LLM calls for "Generate All"
    var maxParallelSlides: Int {
        get { defaults.object(forKey: "maxParallelSlides") as? Int ?? 3 }
        set { defaults.set(newValue, forKey: "maxParallelSlides") }
    }

    /// LM Studio base URL
    var lmStudioBaseURL: String {
        get { defaults.string(forKey: "lmStudioBaseURL") ?? "http://localhost:1234" }
        set { defaults.set(newValue, forKey: "lmStudioBaseURL") }
    }

    /// Speech tone preset
    var speechTone: String {
        get { defaults.string(forKey: "speechTone") ?? "Conversational" }
        set { defaults.set(newValue, forKey: "speechTone") }
    }

    // MARK: - MLX Local Model

    var mlxSelectedModelId: String {
        get { defaults.string(forKey: "mlxSelectedModelId") ?? "" }
        set { defaults.set(newValue, forKey: "mlxSelectedModelId") }
    }

    var mlxTemperature: Double {
        get { defaults.object(forKey: "mlxTemperature") as? Double ?? 0.7 }
        set { defaults.set(newValue, forKey: "mlxTemperature") }
    }

    var mlxTopP: Double {
        get { defaults.object(forKey: "mlxTopP") as? Double ?? 0.9 }
        set { defaults.set(newValue, forKey: "mlxTopP") }
    }

    var mlxMaxTokens: Int {
        get { defaults.object(forKey: "mlxMaxTokens") as? Int ?? 2048 }
        set { defaults.set(newValue, forKey: "mlxMaxTokens") }
    }

    /// Security-scoped bookmarks for user-granted local model folders (sandbox support).
    var mlxLocalModelBookmarks: [String: Data] {
        get { defaults.object(forKey: "mlxLocalModelBookmarks") as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: "mlxLocalModelBookmarks") }
    }

    // MARK: - Migration

    private func migrateFromStandardIfNeeded() {
        let migrationKey = "didMigrateToSuiteDefaults"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let standard = UserDefaults.standard
        let keysToMigrate = [
            "showNextSlideBanner", "transitionDwellSeconds", "showPlayCountdown",
            "playCountdownSeconds", "showSectionTimer", "showStageDirections",
            "autoAdvance", "alwaysOnTop", "defaultProvider", "maxParallelSlides",
            "lmStudioBaseURL", "speechTone"
        ]
        for key in keysToMigrate {
            if let value = standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: migrationKey)
    }
}
