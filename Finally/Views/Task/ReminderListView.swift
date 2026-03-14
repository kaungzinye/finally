import SwiftUI
import SwiftData

struct ReminderListView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @State private var showAddReminder = false

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
                                        Text(fireDate.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showAddReminder) {
            addReminderSheet
        }
    }

    private var addReminderSheet: some View {
        NavigationStack {
            List {
                ForEach(presetIntervals, id: \.1) { label, seconds in
                    let alreadyAdded = task.reminders.contains { $0.intervalSeconds == seconds }
                    Button {
                        addReminder(label: label, seconds: seconds)
                        showAddReminder = false
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
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddReminder = false }
                }
            }
        }
        .presentationDetents([.medium])
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
}

import UserNotifications
