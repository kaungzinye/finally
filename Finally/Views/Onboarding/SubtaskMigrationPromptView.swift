import SwiftUI

struct SubtaskMigrationPromptView: View {
    let subtaskCount: Int
    let onPromote: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.doc")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Promote local subtasks?")
                .font(.headline)

            Text("Finally found \(subtaskCount) subtask\(subtaskCount == 1 ? "" : "s") saved only on this device. Promote them to real Notion pages?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Not Now", action: onDismiss)
                    .buttonStyle(.bordered)

                Button("Promote", action: onPromote)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .presentationDetents([.height(280)])
    }
}
