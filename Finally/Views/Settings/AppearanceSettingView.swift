import SwiftUI

struct AppearanceSettingView: View {
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    var body: some View {
        List {
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Choose how Finally appears. \"System\" follows your device settings.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
