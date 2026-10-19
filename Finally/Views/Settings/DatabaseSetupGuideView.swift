import SwiftUI

struct DatabaseSetupGuideView: View {
    var body: some View {
        List {
            Group {
                Section {
                    Text("Finally reads your tasks from one Notion database, and your projects from a second one if you have it.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                Section {
                    propertyRow(name: "Name", type: "Title", required: true, note: "The task's name. Every database has one.")
                    propertyRow(name: "Status", type: "Status", required: true, note: "Not started, In progress, and Complete")
                    propertyRow(name: "Due Date", type: "Date", required: true, note: "The task's deadline, when it must be done")
                    propertyRow(name: "Priority", type: "Select", required: false, note: "Urgent, High, Medium, and Low")
                    propertyRow(name: "Tags", type: "Multi-select", required: false, note: "Any tags you like")
                    propertyRow(name: "Project", type: "Relation", required: false, note: "Links to your projects database")
                    propertyRow(name: "Recurrence", type: "Select", required: false, note: "None, Daily, Weekly, Monthly, and Yearly")
                } header: {
                    SectionLabel("Tasks database")
                }

                Section {
                    propertyRow(name: "Name", type: "Title", required: true, note: "The project's name")
                } header: {
                    SectionLabel("Projects database, if you want one")
                }

                Section {
                    step(number: 1, text: "Open Notion and make a database, or use one you have.")
                    step(number: 2, text: "Add the properties listed above.")
                    step(number: 3, text: "Connect Notion from Finally and share your databases with it.")
                    step(number: 4, text: "Choose your tasks database. Finally checks its properties for you.")
                } header: {
                    SectionLabel("Steps")
                }
            }
            .cardRow()
        }
        .paperList()
        .navigationTitle("Database setup guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func propertyRow(name: String, type: String, required: Bool, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(type)
                    .font(.meta)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Palette.wash, in: Capsule())
                if required {
                    Text("Required")
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                }
            }
            Text(note)
                .font(.meta)
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 2)
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.meta.bold())
                .foregroundStyle(Palette.ink)
                .frame(width: 24, height: 24)
                .background(Palette.wash, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
        }
    }
}
