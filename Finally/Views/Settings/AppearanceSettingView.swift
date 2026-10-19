import SwiftUI

struct AppearanceSettingView: View {
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    private let modes = [(0, "Match iPhone"), (1, "Light"), (2, "Dark")]

    var body: some View {
        List {
            Section {
                ForEach(modes, id: \.0) { mode, title in
                    CheckRow(isSelected: appearanceMode == mode, action: { appearanceMode = mode }) {
                        Text(title)
                    }
                    .accessibilityIdentifier("theme-\(mode)")
                }
            } footer: {
                SectionNote("Match iPhone follows your Light and Dark setting.")
            }
        }
        .paperList()
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
