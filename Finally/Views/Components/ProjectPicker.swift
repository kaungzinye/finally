import SwiftUI
import SwiftData

struct ProjectPicker: View {
    @Binding var selection: ProjectItem?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("Inbox (No Project)")
                        Spacer()
                        if selection == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                ForEach(projects) { project in
                    Button {
                        selection = project
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(project.title)
                            Spacer()
                            if selection?.notionPageId == project.notionPageId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
