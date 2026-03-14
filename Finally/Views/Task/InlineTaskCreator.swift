import SwiftUI
import SwiftData

struct InlineTaskCreator: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService

    @State private var taskTitle = ""
    @State private var dueDate: Date?
    @State private var priority: TaskPriority?
    @State private var tags: [String] = []
    @State private var project: ProjectItem?
    @State private var recurrence: Recurrence = .none

    @State private var showDatePicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false

    @FocusState private var isFocused: Bool

    var presetProject: ProjectItem?

    var body: some View {
        VStack(spacing: 10) {
            // Text field
            TextField("Add a task...", text: $taskTitle)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, 16)

            // Selected chips
            if hasSelections {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let dueDate {
                            ChipView(
                                label: dueDate.formatted(date: .abbreviated, time: .omitted),
                                icon: "calendar",
                                color: .secondary
                            ) { showDatePicker = true }
                        }
                        if let priority {
                            ChipView(
                                label: priority.rawValue,
                                icon: priority.icon,
                                color: priority.color
                            ) { showPriorityPicker = true }
                        }
                        if !tags.isEmpty {
                            ChipView(
                                label: "\(tags.count) tag\(tags.count == 1 ? "" : "s")",
                                icon: "tag",
                                color: .purple
                            ) { showTagPicker = true }
                        }
                        if let project {
                            ChipView(
                                label: project.title,
                                icon: "folder",
                                color: .secondary
                            ) { showProjectPicker = true }
                        }
                        if recurrence != .none {
                            ChipView(
                                label: recurrence.rawValue,
                                icon: "repeat",
                                color: .green
                            ) { showRecurrencePicker = true }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Property buttons + send
            HStack(spacing: 18) {
                Button { showDatePicker = true } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(dueDate != nil ? .primary : .secondary)
                }
                Button { showPriorityPicker = true } label: {
                    Image(systemName: "flag")
                        .foregroundStyle(priority != nil ? priority!.color : .secondary)
                }
                Button { showTagPicker = true } label: {
                    Image(systemName: "tag")
                        .foregroundStyle(!tags.isEmpty ? .purple : .secondary)
                }
                Button { showProjectPicker = true } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(project != nil ? .primary : .secondary)
                }
                Button { showRecurrencePicker = true } label: {
                    Image(systemName: "repeat")
                        .foregroundStyle(recurrence != .none ? .green : .secondary)
                }
                Spacer()
                Button {
                    createTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(taskTitle.isEmpty ? Color.secondary : Color.primary)
                }
                .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.title3)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(Color(.secondarySystemBackground))
        .onAppear {
            if project == nil, let presetProject {
                project = presetProject
            }
            isFocused = true
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $dueDate)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: $priority)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: $tags)
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: $project)
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(selection: $recurrence)
        }
    }

    private var hasSelections: Bool {
        dueDate != nil || priority != nil || !tags.isEmpty || project != nil || recurrence != .none
    }

    private func createTask() {
        let title = taskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let task = TaskItem(notionPageId: UUID().uuidString, title: title)
        task.dueDate = dueDate
        task.priority = priority
        task.tags = tags
        task.project = project
        task.recurrence = recurrence
        task.isDirty = true

        modelContext.insert(task)

        // Push to Notion in background
        let context = modelContext
        Task {
            if let session = try? context.fetch(FetchDescriptor<UserSession>()).first {
                try? await syncService.pushDirtyChanges(session: session, modelContext: context)
            }
        }

        // Reset for next task
        taskTitle = ""
        dueDate = nil
        priority = nil
        tags = []
        if presetProject == nil { project = nil }
        recurrence = .none
    }
}
