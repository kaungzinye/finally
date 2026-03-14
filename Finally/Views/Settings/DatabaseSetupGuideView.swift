import SwiftUI

struct DatabaseSetupGuideView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Notion workspace needs two databases for Finally to work properly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tasks Database (Required)") {
                propertyRow(name: "Name", type: "Title", required: true, note: "Task name (auto-created)")
                propertyRow(name: "Status", type: "Status", required: true, note: "Options: Not Started, In Progress, Complete")
                propertyRow(name: "Due Date", type: "Date", required: true, note: "Task deadline")
                propertyRow(name: "Priority", type: "Select", required: false, note: "Options: Urgent, High, Medium, Low")
                propertyRow(name: "Tags", type: "Multi-select", required: false, note: "Custom tags for filtering")
                propertyRow(name: "Project", type: "Relation", required: false, note: "Link to Projects database")
                propertyRow(name: "Recurrence", type: "Select", required: false, note: "Options: None, Daily, Weekly, Monthly, Yearly")
            }

            Section("Projects Database (Optional)") {
                propertyRow(name: "Name", type: "Title", required: true, note: "Project name (auto-created)")
            }

            Section("Setup Steps") {
                step(number: 1, text: "Open Notion and create a new database (or use an existing one)")
                step(number: 2, text: "Add the required properties listed above")
                step(number: 3, text: "Create a Notion integration at notion.so/my-integrations")
                step(number: 4, text: "Share your databases with the integration")
                step(number: 5, text: "Connect from the app — databases will be auto-detected")
            }
        }
        .navigationTitle("Database Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func propertyRow(name: String, type: String, required: Bool, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .fontWeight(.medium)
                Spacer()
                Text(type)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
                if required {
                    Text("Required")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(.secondary.opacity(0.1))
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}
