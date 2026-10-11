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
                Section("Your phone edit") { values(task.serverMutation) }
                if let accepted = task.conflictingServerMutation {
                    Section("Accepted server state") { values(accepted) }
                }
                if task.serverTaskMissing {
                    Section("Server task deleted") {
                        Text("Your phone edit is saved. Choose how to recover it.")
                        Button("Save as a new task") { recoverMissing(saveAsNew: true) }
                        Button("Discard this phone edit", role: .destructive) { recoverMissing(saveAsNew: false) }
                    }
                } else {
                    Section {
                        Text("Choose the task state to keep. Other server changes stay intact.")
                        Button("Keep my phone edits") { resolve(keepingPhoneEdits: true) }
                        Button("Use accepted server state") { resolve(keepingPhoneEdits: false) }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Palette.ink) } }
            }
            .paperList()
            .navigationTitle("Review conflict")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func values(_ mutation: FinallyServerTaskMutation) -> some View {
        LabeledContent("Task", value: mutation.title)
        LabeledContent("State", value: mutation.isCompleted ? "Done" : "Open")
        LabeledContent("Planned day", value: mutation.plannedDay?.formatted(date: .abbreviated, time: .omitted) ?? "Unset")
        LabeledContent("Deadline", value: mutation.deadline?.formatted(date: .abbreviated, time: .shortened) ?? "Unset")
        LabeledContent("Priority", value: mutation.priority?.rawValue ?? "Unset")
        if task.isDeleted { Text("Your phone edit deletes this task.") }
    }

    private func recoverMissing(saveAsNew: Bool) {
        if saveAsNew { task.saveMissingServerTaskAsDraft() }
        else { modelContext.delete(task) }
        do {
            try modelContext.save()
            provider.clearError()
            dismiss()
            if saveAsNew { Task { await provider.submitPendingChangesReportingFailure(for: [task], store: modelContext) } }
        } catch { self.error = error.localizedDescription }
    }

    private func resolve(keepingPhoneEdits: Bool) {
        task.resolveServerConflict(keepingPhoneEdits: keepingPhoneEdits)
        do {
            try modelContext.save()
            provider.clearError()
            dismiss()
            if task.isDirty { Task { await provider.submitPendingChangesReportingFailure(for: [task], store: modelContext) } }
        } catch { self.error = error.localizedDescription }
    }
}
