import Foundation

/// The add bar's unsaved task: the typed text and the fields its chips hold.
///
/// Text sets fields as the user types. A field the text set follows later edits to the text,
/// and a field the user picked by hand, cleared included, stays as picked.
struct CaptureDraft {
    var text = ""
    private(set) var scheduledDay: Date?
    private(set) var deadline: Date?
    private(set) var deadlineHasTime = false
    private(set) var priority: TaskPriority?
    private(set) var tags: [String] = []
    private(set) var project: ProjectItem?
    var recurrence: Recurrence = .none
    var customRecurrenceRule: RecurrenceRule?
    var parentTask: TaskItem?

    private enum Field { case scheduledDay, deadline, priority, project, tags }

    /// The fields the current text set.
    private var fieldsFromText: Set<Field> = []
    /// The fields the user picked by hand, which text no longer sets.
    private var pickedFields: Set<Field> = []
    /// The text with its shortcut phrases removed, or nil when the text holds no shortcut.
    /// The title drops shortcut phrases whether or not their fields were later picked by hand.
    private var titleWithoutShortcuts: String?

    init(project: ProjectItem? = nil) {
        self.project = project
    }

    /// Reads `text` into the fields it names. `projects` are the workspace's projects an
    /// "@name" can match.
    mutating func readText(projects: [ProjectItem], now: Date = Date(), calendar: Calendar = .current) {
        let parsed = TaskTitleParser.parse(text, now: now, calendar: calendar)
        let namedProject = parsed.detectedProjectName.flatMap { name in
            projects.first { $0.title.localizedCaseInsensitiveContains(name) }
        }
        let holdsShortcut = parsed.scheduledDay != nil || parsed.deadline != nil
            || parsed.detectedPriority != nil || namedProject != nil || !parsed.detectedTags.isEmpty
        titleWithoutShortcuts = holdsShortcut ? parsed.cleanTitle : nil

        set(\.scheduledDay, to: parsed.scheduledDay, field: .scheduledDay)
        set(\.deadline, to: parsed.deadline, field: .deadline)
        set(\.priority, to: parsed.detectedPriority, field: .priority)
        set(\.project, to: namedProject, field: .project)

        guard !pickedFields.contains(.tags) else { return }
        if !parsed.detectedTags.isEmpty, tags.isEmpty || fieldsFromText.contains(.tags) {
            tags = parsed.detectedTags
            fieldsFromText.insert(.tags)
        } else if parsed.detectedTags.isEmpty, fieldsFromText.contains(.tags) {
            tags = []
            fieldsFromText.remove(.tags)
        }
    }

    /// Sets the deadline by hand, so later text leaves it alone.
    mutating func pick(deadline: Date?, hasTime: Bool) {
        self.deadline = deadline
        deadlineHasTime = hasTime
        pick(.deadline)
    }

    /// Sets the scheduled day by hand, so later text leaves it alone.
    mutating func pick(scheduledDay: Date?) {
        self.scheduledDay = scheduledDay
        pick(.scheduledDay)
    }

    /// Sets the priority by hand, so later text leaves it alone.
    mutating func pick(priority: TaskPriority?) {
        self.priority = priority
        pick(.priority)
    }

    /// Sets the project by hand, so later text leaves it alone.
    mutating func pick(project: ProjectItem?) {
        self.project = project
        pick(.project)
    }

    /// Sets the tags by hand, so later text leaves them alone.
    mutating func pick(tags: [String]) {
        self.tags = tags
        pick(.tags)
    }

    /// Adds a tag by hand, so later text leaves the tags alone.
    mutating func pick(tag: String) {
        pick(tags: tags.contains(tag) ? tags : tags + [tag])
    }

    /// The task this draft captures, or nil when it has no title. A new deadline takes the
    /// default deadline reminders. A task with no project lands in the Inbox.
    func makeTask(workspaceId: String?, defaults: DefaultDeadlineReminders) -> TaskItem? {
        let title = titleWithoutShortcuts ?? text.trimmingCharacters(in: .whitespaces)
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

    private mutating func pick(_ field: Field) {
        pickedFields.insert(field)
        fieldsFromText.remove(field)
    }

    private mutating func set<Value>(_ keyPath: WritableKeyPath<CaptureDraft, Value?>, to detected: Value?, field: Field) {
        guard !pickedFields.contains(field) else { return }
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
