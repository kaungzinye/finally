import SwiftUI
import SwiftData

/// The reminders section of task detail: the task's deadline reminders as chips, a + chip that
/// adds from a short list, its exact reminders, and "Remind me at". Task detail presents the
/// "Remind me at" sheet, because a sheet owned by a list row closes when the row redraws.
struct ReminderSection: View {
    @Bindable var task: TaskItem
    let onRemindMeAt: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    private var deadlineReminders: [DeadlineReminder] {
        task.taskReminders.compactMap { if case .deadline(let rule) = $0 { rule } else { nil } }
    }

    private var exactReminders: [ExactReminder] {
        task.taskReminders.compactMap { if case .exact(let rule) = $0 { rule } else { nil } }
    }

    private var note: String? {
        if task.deadline == nil { return "Deadline reminders start when the task has a deadline." }
        if !task.deadlineHasTime, task.deadlineReminderOffsets.contains(.hourBefore) {
            return "1 hour before waits for a deadline time."
        }
        return nil
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(deadlineReminders) { rule in
                        RemovableChip(label: rule.offset.label, icon: "bell", isInert: isInert(rule.offset)) {
                            edit { task.removeReminder(id: rule.id) }
                        }
                    }
                    if !task.addableDeadlineReminderOffsets.isEmpty {
                        AddChipMenu(
                            choices: task.addableDeadlineReminderOffsets,
                            title: \.label,
                            accessibilityLabel: "Add deadline reminder"
                        ) { offset in
                            edit(asksPermission: true) { task.addDeadlineReminder(offset) }
                        }
                        .accessibilityIdentifier("add-deadline-reminder")
                    }
                    ForEach(exactReminders) { rule in
                        RemovableChip(label: rule.label,
                                      icon: "clock", isInert: rule.at <= Date()) {
                            edit { task.removeReminder(id: rule.id) }
                        }
                    }
                    ChipView(label: "Remind me at", icon: "clock", isPlaceholder: true, action: onRemindMeAt)
                }
                if let note {
                    Text(note)
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.vertical, 8)
        } header: {
            SectionLabel("Reminders")
        }
    }

    private func isInert(_ offset: DeadlineReminderOffset) -> Bool {
        task.deadline == nil || (offset == .hourBefore && !task.deadlineHasTime)
    }

    private func edit(asksPermission: Bool = false, _ change: () -> Void) {
        Self.save(task, store: modelContext, provider: taskProvider, asksPermission: asksPermission, change)
    }

    /// Reminder edits save as they happen, then push and reschedule. Adding a reminder asks
    /// for notification permission the first time.
    @MainActor
    static func save(
        _ task: TaskItem,
        store: ModelContext,
        provider: TaskProviderCoordinator,
        asksPermission: Bool,
        _ change: () -> Void
    ) {
        change()
        task.isDirty = true
        try? store.save()
        if asksPermission {
            Task {
                if await NotificationService.shared.checkPermissionStatus() == .notDetermined {
                    _ = await NotificationService.shared.requestPermission()
                }
            }
        }
        Task { await provider.submitPendingChangesReportingFailure(for: [task], store: store) }
        NotificationService.shared.rescheduleAllReminders(modelContext: store)
    }
}

/// Picks the instant for an exact reminder.
struct RemindMeAtSheet: View {
    let onAdd: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.nextDate(
        after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime
    ) ?? Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Remind me at", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Button("Add reminder") {
                    onAdd(date)
                    dismiss()
                }
                .buttonStyle(.ink)
                .accessibilityIdentifier("add-exact-reminder")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .background(Palette.sheet)
            .navigationTitle("Remind me at")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.sheet)
    }
}
