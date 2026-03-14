// Teleprompter/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        TabView {
            teleprompterTab
                .tabItem {
                    Label("Teleprompter", systemImage: "play.rectangle")
                }

            aiTab
                .tabItem {
                    Label("AI Assistant", systemImage: "sparkles")
                }

            ModelManagerView()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 550)
    }

    // MARK: - Teleprompter Tab

    private var teleprompterTab: some View {
        Form {
            Section("Next Slide Transition") {
                Toggle("Show next slide banner", isOn: $settings.showNextSlideBanner)

                if settings.showNextSlideBanner {
                    HStack {
                        Text("Transition time")
                        Spacer()
                        Picker("", selection: $settings.transitionDwellSeconds) {
                            Text("1s").tag(1.0)
                            Text("2s").tag(2.0)
                            Text("3s").tag(3.0)
                            Text("4s").tag(4.0)
                            Text("5s").tag(5.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }

                Toggle("Auto-advance to next slide", isOn: $settings.autoAdvance)
            }

            Section("Play Countdown") {
                Toggle("Show countdown before playing", isOn: $settings.showPlayCountdown)

                if settings.showPlayCountdown {
                    HStack {
                        Text("Countdown seconds")
                        Spacer()
                        Picker("", selection: $settings.playCountdownSeconds) {
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }
            }

            Section("Display") {
                Toggle("Show section time remaining", isOn: $settings.showSectionTimer)
                Toggle("Show stage direction badges", isOn: $settings.showStageDirections)
                Toggle("Show slide thumbnails in teleprompter", isOn: $settings.showSlideThumbnails)
                Toggle("Always on top", isOn: $settings.alwaysOnTop)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    // MARK: - AI Tab

    private var aiTab: some View {
        Form {
            Section("LM Studio") {
                HStack {
                    Text("Base URL")
                    Spacer()
                    TextField("http://localhost:1234", text: $settings.lmStudioBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }

            Section("Presentation Style") {
                HStack {
                    Text("Default style")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { SpeechTone(rawValue: settings.speechTone) ?? .conversational },
                        set: { settings.speechTone = $0.rawValue }
                    )) {
                        let grouped = Dictionary(grouping: SpeechTone.allCases, by: \.category)
                        ForEach(["Tone", "Presentation"], id: \.self) { category in
                            Section(category) {
                                ForEach(grouped[category] ?? []) { tone in
                                    Text(tone.label).tag(tone)
                                }
                            }
                        }
                    }
                    .frame(width: 160)
                }
                Text((SpeechTone(rawValue: settings.speechTone) ?? .conversational).description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Parallel Generation") {
                HStack {
                    Text("Max concurrent slides")
                    Spacer()
                    Picker("", selection: $settings.maxParallelSlides) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                        Text("5").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                Text("Higher values generate faster but may overwhelm local models.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Teleprompter")
                .font(.system(size: 22, weight: .bold))

            Text("Made with \u{2764} by Danny Rodriguez")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("AI-powered presentation coach and floating teleprompter overlay for macOS.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
