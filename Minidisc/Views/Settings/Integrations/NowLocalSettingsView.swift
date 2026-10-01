import SwiftUI

struct NowLocalSettingsView: View {
    @Environment(\.appContainer) private var container

    @AppStorage("minidisc_motion_artwork_disabled") private var isMotionArtworkDisabled = false
    @AppStorage("minidisc_nowlocal_disabled") private var isNowLocalDisabled = false
    @AppStorage("minidisc_nowlocal_url") private var customNowLocalURL = ""

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }

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
                TextField("http://your-server-ip:7430", text: $customNowLocalURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)

                if !customNowLocalURL.isEmpty {
                    Button("Clear URL") {
                        customNowLocalURL = ""
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Server URL & Port")
            } footer: {
                Text("Enter the server URL and port where your NowLocal service is hosted (e.g. http://192.168.1.100:7430). Both URL and port must be specified.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Animated Artwork & NowLocal")
        .navigationBarTitleDisplayModeInline()
    }
}
