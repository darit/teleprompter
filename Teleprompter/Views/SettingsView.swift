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

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 400)
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
}

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

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
