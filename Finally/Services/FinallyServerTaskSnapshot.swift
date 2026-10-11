import Foundation

extension FinallyServerTask {
    var mutation: FinallyServerTaskMutation {
        FinallyServerTaskMutation(title: title, isCompleted: isCompleted, plannedDay: plannedDay.map { Calendar.current.startOfDay(for: $0) }, deadline: deadline, priority: priority, deadlineHasTime: deadlineHasTime, reminders: reminders)
    }
}

extension FinallyServerTaskMutation {
    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> Self? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func differences(from other: Self) -> Set<String> {
        var fields: Set<String> = []
        if title != other.title { fields.insert("title") }
        if isCompleted != other.isCompleted { fields.insert("done") }
        if !sameInstant(plannedDay, other.plannedDay) { fields.insert("start_date") }
        if !sameInstant(deadline, other.deadline) { fields.insert("due_date") }
        if deadlineHasTime != other.deadlineHasTime { fields.formUnion(["due_date", "deadline_has_time"]) }
        if reminders != other.reminders { fields.insert("reminder_rules") }
        if priority != other.priority { fields.insert("priority") }
        return fields
    }

    private func sameInstant(_ left: Date?, _ right: Date?) -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case let (left?, right?): abs(left.timeIntervalSince(right)) < 1
        default: false
        }
    }
}

extension TaskItem {
    var serverMutation: FinallyServerTaskMutation {
        FinallyServerTaskMutation(title: title, isCompleted: status == .done, plannedDay: plannedDay, deadline: deadline, priority: priority, deadlineHasTime: deadlineHasTime, reminders: taskReminders)
    }

    var acceptedServerMutation: FinallyServerTaskMutation? { .decode(serverSnapshotJSON) }
    var conflictingServerMutation: FinallyServerTaskMutation? { .decode(serverConflictJSON) }

    func applyServerMutation(_ mutation: FinallyServerTaskMutation, fields: Set<String>) {
        if fields.contains("title") { title = mutation.title }
        if fields.contains("done") { status = mutation.isCompleted ? .done : .notStarted }
        if fields.contains("start_date") { plannedDay = mutation.plannedDay }
        if fields.contains("due_date") { deadline = mutation.deadline }
        if fields.contains("deadline_has_time") { deadlineHasTime = mutation.deadlineHasTime }
        if fields.contains("reminder_rules") { taskReminders = mutation.reminders }
        if fields.contains("priority") { priority = mutation.priority }
    }

    func saveMissingServerTaskAsDraft() {
        externalTaskID = UUID().uuidString
        lastSyncedAt = nil
        serverRevision = 0
        serverSnapshotJSON = nil
        serverConflictJSON = nil
        serverConflictFields = []
        serverTaskMissing = false
        isDeleted = false
        isDirty = true
    }

    func resolveServerConflict(keepingPhoneEdits: Bool) {
        guard let current = conflictingServerMutation else { return }
        let localStatus = status
        let local = serverMutation
        let fields = local.differences(from: acceptedServerMutation ?? current)
        applyServerMutation(current, fields: ["title", "done", "start_date", "due_date", "priority", "deadline_has_time", "reminder_rules"])
        if keepingPhoneEdits {
            applyServerMutation(local, fields: fields)
            if status != .done && localStatus == .inProgress { status = .inProgress }
        }
        else { isDeleted = false }
        serverSnapshotJSON = current.json
        serverConflictJSON = nil
        serverConflictFields = []
        isDirty = keepingPhoneEdits && (!serverMutation.differences(from: current).isEmpty || isDeleted)
    }
}
