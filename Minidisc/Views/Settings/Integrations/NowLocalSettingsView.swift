import SwiftUI

struct NowLocalSettingsView: View {
    @Environment(\.appContainer) private var container

    @AppStorage("minidisc_motion_artwork_disabled") private var isMotionArtworkDisabled = false
    @AppStorage("minidisc_nowlocal_disabled") private var isNowLocalDisabled = false
    @AppStorage("minidisc_nowlocal_url") private var customNowLocalURL = ""

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }

    private var defaultBaseURL: String {
        guard let active = activeServer?.baseURL, let parsed = URL(string: active), let host = parsed.host else {
            return "http://100.66.40.34:7430"
        }
        let scheme = parsed.scheme ?? "http"
        return "\(scheme)://\(host):7430"
    }

    private var effectiveBaseURL: String {
        let trimmed = customNowLocalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBaseURL : trimmed
    }

    var body: some View {
        Form {
            Section {
                Text("NowLocal enriches your music with Apple Music-style dynamic animated artwork in the player and album view, as well as rich synchronized TTML karaoke lyrics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }

            Section {
                Toggle("Animated Cover Art", isOn: Binding(
                    get: { !isMotionArtworkDisabled },
                    set: { isMotionArtworkDisabled = !$0 }
                ))

                Toggle("NowLocal Enrichment", isOn: Binding(
                    get: { !isNowLocalDisabled },
                    set: { isNowLocalDisabled = !$0 }
                ))
            } header: {
                Text("Features")
            } footer: {
                Text("When enabled, looping animated covers will appear in the full player and in album detail sheets when available.")
            }

            Section {
                TextField("Default: \(defaultBaseURL)", text: $customNowLocalURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)

                if !customNowLocalURL.isEmpty {
                    Button("Reset to Default") {
                        customNowLocalURL = ""
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Server URL")
            } footer: {
                Text("By default, Minidisc connects to port 7430 on the active server (\(effectiveBaseURL)). You can override this if running NowLocal at a custom endpoint.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Animated Artwork & NowLocal")
        .navigationBarTitleDisplayModeInline()
    }
}
