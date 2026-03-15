import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Inline Reminder Content (for embedding in TaskDetailView's List)

struct ReminderSectionContent: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @State private var showAddReminder = false

    var body: some View {
        Section("Reminders") {
            if task.reminders.isEmpty {
                Text("No reminders set")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.reminders, id: \.id) { reminder in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "bell")
                                    .foregroundStyle(.orange)
                                Text(reminder.label)
                            }
                            if let fireDate = reminder.fireDate {
                                if reminder.absoluteDate != nil {
                                    Text(fireDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(fireDate.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if reminder.isScheduled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let reminder = task.reminders[index]
                        UNUserNotificationCenter.current()
                            .removePendingNotificationRequests(withIdentifiers: [reminder.notificationId])
                        modelContext.delete(reminder)
                    }
                    NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                }
            }

            Button {
                showAddReminder = true
            } label: {
                Label("Add Reminder", systemImage: "plus.circle")
            }
        }
        .sheet(isPresented: $showAddReminder) {
            ReminderAddSheet(task: task)
        }
    }
}

// MARK: - Standalone ReminderListView (for sheet presentation from TaskRowView)

struct ReminderListView: View {
    @Bindable var task: TaskItem

    var body: some View {
        NavigationStack {
            List {
                ReminderSectionContent(task: task)
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add Reminder Sheet

struct ReminderAddSheet: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomDatePicker = false
    @State private var customDate = Date()

    private let presetIntervals: [(String, Int)] = [
        ("5 minutes before", 300),
        ("15 minutes before", 900),
        ("30 minutes before", 1800),
        ("1 hour before", 3600),
        ("2 hours before", 7200),
        ("1 day before", 86400),
        ("2 days before", 172800),
        ("1 week before", 604800),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    ForEach(presetIntervals, id: \.1) { label, seconds in
                        let alreadyAdded = task.reminders.contains { $0.intervalSeconds == seconds && $0.absoluteDate == nil }
                        Button {
                            addReminder(label: label, seconds: seconds)
                            dismiss()
                        } label: {
                            HStack {
                                Text(label)
                                Spacer()
                                if alreadyAdded {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .disabled(alreadyAdded)
                    }
                }

                Section("Custom") {
                    Button {
                        showCustomDatePicker.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                            Text("Pick exact date & time")
                            Spacer()
                            if showCustomDatePicker {
                                Image(systemName: "chevron.up")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if showCustomDatePicker {
                        DatePicker(
                            "Remind at",
                            selection: $customDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)

                        Button {
                            addAbsoluteReminder(date: customDate)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Add Reminder")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addReminder(label: String, seconds: Int) {
        Task {
            let status = await NotificationService.shared.checkPermissionStatus()
            if status == .notDetermined {
                _ = await NotificationService.shared.requestPermission()
            }
        }

        let reminder = ReminderItem(
            intervalSeconds: seconds,
            label: label,
            taskNotionPageId: task.notionPageId
        )
        reminder.task = task
        modelContext.insert(reminder)

        NotificationService.shared.scheduleReminder(for: task, reminder: reminder)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }

    private func addAbsoluteReminder(date: Date) {
        Task {
            let status = await NotificationService.shared.checkPermissionStatus()
            if status == .notDetermined {
                _ = await NotificationService.shared.requestPermission()
            }
        }

        let label = date.formatted(date: .abbreviated, time: .shortened)
        let reminder = ReminderItem(
            absoluteDate: date,
            label: label,
            taskNotionPageId: task.notionPageId
        )
        reminder.task = task
        modelContext.insert(reminder)

        NotificationService.shared.scheduleReminder(for: task, reminder: reminder)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }
}
