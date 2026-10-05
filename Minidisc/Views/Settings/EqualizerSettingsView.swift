import SwiftUI

struct EqualizerSettingsView: View {
    @Environment(\.appContainer) private var container
    @Bindable var settings: EqualizerSettings

    var body: some View {
        Form {
            Section {
                Toggle("Equalizer", isOn: $settings.enabled)
                    .onChange(of: settings.enabled) { _, _ in
                        notifySettingsChanged()
                    }
            } footer: {
                Text("Enables real-time frequency processing during audio playback.")
            }

            if settings.enabled {
                presetsSection()
                manualBandsSection()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayModeInline()
    }

    // MARK: - Presets

    private func presetsSection() -> some View {
        Section {
            Picker("Preset", selection: Binding(
                get: { settings.preset },
                set: { newPreset in
                    settings.selectPreset(newPreset)
                    notifySettingsChanged()
                }
            )) {
                ForEach(EqualizerPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        } header: {
            Text("Presets")
        } footer: {
            Text("Select a preset tuning or adjust the sliders below to create a custom profile.")
        }
    }

    // MARK: - Manual Frequencies

    private func manualBandsSection() -> some View {
        Section {
            ForEach(EqualizerBandInfo.bands) { band in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(band.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        let gain = bandGain(for: band.id)
                        Text(formatGain(gain))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(gain != 0 ? MinidiscColors.accent : Color.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(bandGain(for: band.id)) },
                            set: { newValue in
                                settings.setBandGain(at: band.id, to: Float(newValue))
                                notifySettingsChanged()
                            }
                        ),
                        in: -12.0...12.0,
                        step: 0.5
                    )
                    .tint(MinidiscColors.accent)
                }
                .padding(.vertical, 2)
            }

            Button(role: .cancel) {
                withAnimation {
                    settings.resetToFlat()
                    notifySettingsChanged()
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Reset to Flat (0 dB)")
                        .font(.subheadline)
                    Spacer()
                }
            }
        } header: {
            Text("Manual Equalizer")
        } footer: {
            Text("Ranges from -12 dB to +12 dB across 6 selected frequency bands.")
        }
    }

    // MARK: - Helpers

    private func bandGain(for index: Int) -> Float {
        guard index >= 0, index < settings.gains.count else { return 0 }
        return settings.gains[index]
    }

    private func formatGain(_ gain: Float) -> String {
        if abs(gain) < 0.05 {
            return "0 dB"
        } else if gain > 0 {
            return String(format: "+%.1f dB", gain)
        } else {
            return String(format: "%.1f dB", gain)
        }
    }

    private func notifySettingsChanged() {
        Task {
            await container?.playerService.equalizerSettingsDidChange()
        }
    }
}
