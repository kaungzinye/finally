import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService

    @State private var showDatePicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false

    @State private var editedTitle: String = ""
    @State private var editedDueDate: Date?
    @State private var editedPriority: TaskPriority?
    @State private var editedTags: [String] = []
    @State private var editedProject: ProjectItem?
    @State private var editedRecurrence: Recurrence = .none

    var body: some View {
        NavigationStack {
            List {
                // Title
                Section {
                    TextField("Task name", text: $editedTitle)
                        .font(.title3)
                }

                // Properties
                Section {
                    // Due Date
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            Label("Due Date", systemImage: "calendar")
                            Spacer()
                            if let date = editedDueDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Priority
                    Button {
                        showPriorityPicker = true
                    } label: {
                        HStack {
                            Label("Priority", systemImage: "flag")
                            Spacer()
                            if let priority = editedPriority {
                                HStack(spacing: 4) {
                                    Image(systemName: priority.icon)
                                        .foregroundStyle(priority.color)
                                    Text(priority.rawValue)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Project
                    Button {
                        showProjectPicker = true
                    } label: {
                        HStack {
                            Label("Project", systemImage: "folder")
                            Spacer()
                            Text(editedProject?.title ?? "Inbox")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Tags
                    Button {
                        showTagPicker = true
                    } label: {
                        HStack {
                            Label("Tags", systemImage: "tag")
                            Spacer()
                            if editedTags.isEmpty {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(editedTags.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Recurrence
                    Button {
                        showRecurrencePicker = true
                    } label: {
                        HStack {
                            Label("Repeat", systemImage: "repeat")
                            Spacer()
                            Text(editedRecurrence.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Status
                Section("Status") {
                    Picker("Status", selection: Binding(
                        get: { task.status },
                        set: { newStatus in
                            task.status = newStatus
                            task.isDirty = true
                        }
                    )) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }

                // Reminders
                ReminderListView(task: task)
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            editedTitle = task.title
            editedDueDate = task.dueDate
            editedPriority = task.priority
            editedTags = task.tags
            editedProject = task.project
            editedRecurrence = task.recurrence
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $editedDueDate)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: $editedPriority)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: $editedTags)
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: $editedProject)
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(selection: $editedRecurrence)
        }
    }

    private func saveChanges() {
        let dueDateChanged = task.dueDate != editedDueDate

        task.title = editedTitle
        task.dueDate = editedDueDate
        task.priority = editedPriority
        task.tags = editedTags
        task.project = editedProject
        task.recurrence = editedRecurrence
        task.isDirty = true

        // Reschedule reminders if due date changed
        if dueDateChanged {
            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        }

        // Push in background
        let context = modelContext
        Task {
            if let session = try? context.fetch(FetchDescriptor<UserSession>()).first {
                try? await syncService.pushDirtyChanges(session: session, modelContext: context)
            }
        }
    }
}
