import Foundation

/// The add bar's unsaved task: the typed text and the fields its chips hold.
///
/// Text sets fields as the user types. A field the text set follows later edits to the text,
/// and a field the user picked by hand stays as picked.
struct CaptureDraft {
    var text = ""
    var scheduledDay: Date?
    var deadline: Date?
    var deadlineHasTime = false
    var priority: TaskPriority?
    var tags: [String] = []
    var project: ProjectItem?
    var recurrence: Recurrence = .none
    var customRecurrenceRule: RecurrenceRule?
    var parentTask: TaskItem?

    private enum Field { case scheduledDay, deadline, priority, project, tags }

    /// The fields the current text set.
    private var fieldsFromText: Set<Field> = []
    private var cleanTitle = ""

    init(project: ProjectItem? = nil) {
        self.project = project
    }

    /// Reads `text` into the fields it names. `projects` are the workspace's projects an
    /// "@name" can match.
    mutating func readText(projects: [ProjectItem], now: Date = Date(), calendar: Calendar = .current) {
        let parsed = TaskTitleParser.parse(text, now: now, calendar: calendar)
        cleanTitle = parsed.cleanTitle

        set(\.scheduledDay, to: parsed.scheduledDay, field: .scheduledDay)
        set(\.deadline, to: parsed.deadline, field: .deadline)
        set(\.priority, to: parsed.detectedPriority, field: .priority)
        let namedProject = parsed.detectedProjectName.flatMap { name in
            projects.first { $0.title.localizedCaseInsensitiveContains(name) }
        }
        set(\.project, to: namedProject, field: .project)

        if !parsed.detectedTags.isEmpty, tags.isEmpty || fieldsFromText.contains(.tags) {
            tags = parsed.detectedTags
            fieldsFromText.insert(.tags)
        } else if parsed.detectedTags.isEmpty, fieldsFromText.contains(.tags) {
            tags = []
            fieldsFromText.remove(.tags)
        }
    }

    /// Sets the project by hand, so later text leaves it alone.
    mutating func pick(project: ProjectItem) {
        self.project = project
        fieldsFromText.remove(.project)
    }

    /// Adds a tag by hand, so later text leaves the tags alone.
    mutating func pick(tag: String) {
        if !tags.contains(tag) { tags.append(tag) }
        fieldsFromText.remove(.tags)
    }

    /// The task this draft captures, or nil when it has no title. A new deadline takes the
    /// default deadline reminders. A task with no project lands in the Inbox.
    func makeTask(workspaceId: String?, defaults: DefaultDeadlineReminders) -> TaskItem? {
        let title = fieldsFromText.isEmpty ? text.trimmingCharacters(in: .whitespaces) : cleanTitle
        guard !title.isEmpty else { return nil }

        let task = TaskItem(externalTaskID: UUID().uuidString, title: title)
        task.providerWorkspaceId = workspaceId
        task.setDeadline(deadline, hasTime: deadlineHasTime, defaults: defaults)
        task.scheduledDay = scheduledDay
        task.validateScheduledDay()
        task.priority = priority
        task.tags = tags
        task.project = project
        task.recurrence = recurrence
        task.customRecurrenceRule = customRecurrenceRule
        task.isDirty = true

        if let parentTask {
            task.parentId = parentTask.externalTaskID
            task.parent = parentTask
            task.sortIndex = parentTask.subtasks.count
        }
        return task
    }

    private mutating func set<Value>(_ keyPath: WritableKeyPath<CaptureDraft, Value?>, to detected: Value?, field: Field) {
        let ownedByText = fieldsFromText.contains(field)
        if let detected, self[keyPath: keyPath] == nil || ownedByText {
            self[keyPath: keyPath] = detected
            fieldsFromText.insert(field)
        } else if detected == nil, ownedByText {
            self[keyPath: keyPath] = nil
            fieldsFromText.remove(field)
        }
    }
}
