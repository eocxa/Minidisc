import SwiftUI

struct DataSaverSettingsView: View {
    @AppStorage("minidisc_data_saver_enabled") private var isDataSaverEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Data Saver", isOn: $isDataSaverEnabled)
            } header: {
                Text("Data Usage")
            } footer: {
                Text("Reduces network data usage when streaming over cellular networks or metered connections.")
            }
        }
        .navigationTitle("Data Saver")
        .navigationBarTitleDisplayMode(.inline)
    }
}
