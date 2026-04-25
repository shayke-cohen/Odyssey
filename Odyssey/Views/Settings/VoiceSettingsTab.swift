import SwiftUI
import AVFoundation

struct VoiceSettingsTab: View {
    @AppStorage("voice.featuresEnabled") private var voiceFeaturesEnabled: Bool = false
    @AppStorage("voice.voiceIdentifier") private var ttsVoiceIdentifier: String = ""
    @AppStorage("voice.autoSpeak") private var autoSpeak: Bool = false
    @AppStorage("voice.speakingRate") private var speakingRate: Double = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("voice.showSpeakerButton") private var showSpeakerButton: Bool = false

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section("Voice") {
                Toggle("Voice Features", isOn: $voiceFeaturesEnabled)
                    .help("Enable mic input, speaker buttons, and voice conversation mode")
                    .accessibilityIdentifier("settings.voice.featuresEnabledToggle")
            }

            Section {
                Picker("Voice", selection: $ttsVoiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                .help("Voice used for reading agent responses aloud")
                .accessibilityIdentifier("settings.voice.voicePicker")

                Toggle("Auto-speak responses in Voice Mode", isOn: $autoSpeak)
                    .help("Automatically read agent responses aloud when Voice Mode is active")
                    .accessibilityIdentifier("settings.voice.autoSpeakToggle")

                LabeledContent("Speaking Rate") {
                    HStack {
                        Text("Slow").foregroundStyle(.secondary).font(.caption)
                        Slider(value: $speakingRate,
                               in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate))
                            .accessibilityIdentifier("settings.voice.speakingRateSlider")
                        Text("Fast").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .help("How fast the agent speaks")

                Toggle("Show speaker button on messages", isOn: $showSpeakerButton)
                    .help("Show a speaker button under every agent message")
                    .accessibilityIdentifier("settings.voice.showSpeakerButtonToggle")
            }
            .disabled(!voiceFeaturesEnabled)
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
    }
}
