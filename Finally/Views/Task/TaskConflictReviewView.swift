import SwiftUI

struct TaskConflictReviewView: View {
    let task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskProviderCoordinator.self) private var provider
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section { values(task.serverMutation) } header: { SectionLabel("On this iPhone") }
                    if let accepted = task.conflictingServerMutation {
                        Section { values(accepted) } header: { SectionLabel("On your server") }
                    }
                    if task.serverTaskMissing {
                        Section {
                            Text("Your edit on this iPhone is safe. Choose what to do with it.")
                            Button("Save it as a new task") { recoverMissing(saveAsNew: true) }
                            Button("Discard this edit", role: .destructive) { recoverMissing(saveAsNew: false) }
                        } header: {
                            SectionLabel("Deleted on your server")
                        }
                    } else {
                        Section {
                            Text("Choose which version to keep. Other changes on the server stay as they are.")
                            Button("Keep this iPhone's version") { resolve(keepingPhoneEdits: true) }
                            Button("Use the server's version") { resolve(keepingPhoneEdits: false) }
                        }
                    }
                    if let error { Section { Text(error) } }
                }
                .foregroundStyle(Palette.ink)
                .cardRow()
            }
            .paperList()
            .navigationTitle("Choose a version")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func values(_ mutation: FinallyServerTaskMutation) -> some View {
        LabeledContent("Task", value: mutation.title)
        LabeledContent("Status", value: mutation.isCompleted ? "Done" : "Open")
        LabeledContent("Scheduled", value: mutation.scheduledDay?.formatted(date: .abbreviated, time: .omitted) ?? "None")
        LabeledContent("Deadline", value: mutation.deadline?.formatted(date: .abbreviated, time: .shortened) ?? "None")
        LabeledContent("Priority", value: mutation.priority?.rawValue ?? "None")
        LabeledContent("Reminders") {
            if mutation.reminders.isEmpty {
                Text("None")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(mutation.reminders) { reminder in
                        ChipView(label: reminder.label, icon: reminder.icon)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        if task.isDeleted { Text("This iPhone deleted the task.") }
    }

    private func recoverMissing(saveAsNew: Bool) {
        do {
            if saveAsNew { try task.saveMissingServerTaskAsDraft(in: modelContext) }
            else { modelContext.delete(task) }
            try modelContext.save()
            provider.clearError()
            dismiss()
            if saveAsNew { Task { await provider.submitPendingChangesReportingFailure(for: [task], store: modelContext) } }
        } catch { self.error = error.localizedDescription }
    }

    private func resolve(keepingPhoneEdits: Bool) {
        do {
            try provider.resolveConflict(for: task, keepingPhoneEdits: keepingPhoneEdits, store: modelContext)
            dismiss()
            if task.isDirty { Task { await provider.submitPendingChangesReportingFailure(for: [task], store: modelContext) } }
        } catch { self.error = error.localizedDescription }
    }
}
