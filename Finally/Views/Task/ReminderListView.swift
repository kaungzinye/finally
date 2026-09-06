import SwiftUI
import SwiftData
import UserNotifications

struct ReminderSectionContent: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @State private var showAddReminder = false

    var body: some View {
        Section("Reminders") {
            if task.taskReminders.isEmpty {
                Text("No reminders set")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.taskReminders) { reminder in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "bell")
                                    .foregroundStyle(.orange)
                                Text(reminder.displayLabel)
                            }
                            if let fireDate = reminder.fireDate(for: task) {
                                Text(fireDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .onDelete { indexSet in
                    var reminders = task.taskReminders
                    for index in indexSet.sorted(by: >) {
                        UNUserNotificationCenter.current()
                            .removePendingNotificationRequests(withIdentifiers: [reminders[index].notificationId])
                        reminders.remove(at: index)
                    }
                    task.taskReminders = reminders
                    NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                }
            }

            Button {
                showAddReminder = true
            } label: {
                Label("Add Reminder", systemImage: "plus.circle")
            }
            .disabled(!task.hasValidAnchoredReminderAnchor && task.deadline == nil && task.plannedDay == nil)
        }
        .sheet(isPresented: $showAddReminder) {
            ReminderAddSheet(task: task)
        }
    }
}

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

struct ReminderAddSheet: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var anchor: ReminderAnchor = .deadline
    @State private var direction: ReminderOffsetDirection = .before
    @State private var intervalValue = 30
    @State private var intervalUnit: ReminderOffsetUnit = .minutes
    @State private var absoluteDate = Date()

    private var availableAnchors: [ReminderAnchor] {
        var anchors: [ReminderAnchor] = []
        if task.deadline != nil { anchors.append(.deadline) }
        if task.plannedDay != nil { anchors.append(.plannedDay) }
        return anchors
    }

    private var draftAnchoredReminder: AnchoredReminder {
        AnchoredReminder(anchor: anchor, value: intervalValue, unit: intervalUnit, direction: direction)
    }

    private var draftReminder: TaskReminder {
        selectedTab == 0
            ? .anchored(draftAnchoredReminder)
            : .explicitDate(ExplicitDateReminder(dateTime: absoluteDate))
    }

    private var previewFireDate: Date? {
        draftReminder.fireDate(for: task)
    }

    private var fireDateIsInPast: Bool {
        previewFireDate.map { $0 <= Date() } ?? false
    }

    private var alreadyAdded: Bool {
        task.taskReminders.contains { $0.isDuplicate(of: draftReminder) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Type", selection: $selectedTab) {
                    Text("Anchored").tag(0)
                    Text("Exact Date").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if selectedTab == 0 {
                    anchoredSection
                } else {
                    exactDateSection
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                anchor = availableAnchors.first ?? .deadline
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var anchoredSection: some View {
        Section {
            if availableAnchors.isEmpty {
                Text("Set a deadline or planned day to use anchored reminders.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Anchor", selection: $anchor) {
                    ForEach(availableAnchors) { option in
                        Text(option.label).tag(option)
                    }
                }

                Picker("Direction", selection: $direction) {
                    ForEach(ReminderOffsetDirection.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $intervalValue, in: intervalUnit.bounds, step: 1) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("\(intervalValue)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .onChange(of: intervalUnit) { _, newUnit in
                    intervalValue = min(max(intervalValue, newUnit.bounds.lowerBound), newUnit.bounds.upperBound)
                }

                Picker("Unit", selection: $intervalUnit) {
                    ForEach(ReminderOffsetUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }
        } footer: {
            if let fire = previewFireDate {
                if fireDateIsInPast {
                    Label("This time is already in the past", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("Fires: \(fire.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            Button {
                addReminder(draftReminder)
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Add Reminder").fontWeight(.medium)
                    Spacer()
                }
            }
            .disabled(availableAnchors.isEmpty || fireDateIsInPast || alreadyAdded || !draftAnchoredReminder.isValidValue())
        }
    }

    @ViewBuilder private var exactDateSection: some View {
        Section {
            DatePicker(
                "Remind at",
                selection: $absoluteDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)

            Button {
                addReminder(.explicitDate(ExplicitDateReminder(dateTime: absoluteDate)))
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Add Reminder").fontWeight(.medium)
                    Spacer()
                }
            }
            .disabled(fireDateIsInPast || alreadyAdded)
        }
    }

    private func addReminder(_ reminder: TaskReminder) {
        Task {
            let status = await NotificationService.shared.checkPermissionStatus()
            if status == .notDetermined {
                _ = await NotificationService.shared.requestPermission()
            }
        }

        var reminders = task.taskReminders
        reminders.append(reminder)
        task.taskReminders = reminders

        NotificationService.shared.scheduleReminder(for: task, reminder: reminder)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }
}

struct SubtaskReminderSheet: View {
    @Bindable var subtask: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var intervalValue = 30
    @State private var intervalUnit: ReminderOffsetUnit = .minutes
    @State private var direction: ReminderOffsetDirection = .before

    private var draftReminder: TaskReminder {
        .anchored(AnchoredReminder(anchor: .deadline, value: intervalValue, unit: intervalUnit, direction: direction))
    }

    var body: some View {
        NavigationStack {
            List {
                if !subtask.taskReminders.isEmpty {
                    Section("Current Reminders") {
                        ForEach(subtask.taskReminders) { reminder in
                            HStack {
                                Image(systemName: "bell").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.displayLabel)
                                    if let fire = reminder.fireDate(for: subtask) {
                                        Text(fire.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            var reminders = subtask.taskReminders
                            for index in indexSet.sorted(by: >) {
                                UNUserNotificationCenter.current()
                                    .removePendingNotificationRequests(withIdentifiers: [reminders[index].notificationId])
                                reminders.remove(at: index)
                            }
                            subtask.taskReminders = reminders
                            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                        }
                    }
                }

                Section("Add Reminder") {
                    Stepper(value: $intervalValue, in: intervalUnit.bounds, step: 1) {
                        HStack {
                            Text("Amount")
                            Spacer()
                            Text("\(intervalValue)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Unit", selection: $intervalUnit) {
                        ForEach(ReminderOffsetUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        addSubtaskReminder()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add Reminder").fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(subtask.effectiveSuggestedDate == nil)
                }
            }
            .navigationTitle(subtask.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(480), .large])
    }

    private func addSubtaskReminder() {
        Task {
            let status = await NotificationService.shared.checkPermissionStatus()
            if status == .notDetermined {
                _ = await NotificationService.shared.requestPermission()
            }
        }
        var reminders = subtask.taskReminders
        reminders.append(draftReminder)
        subtask.taskReminders = reminders
        NotificationService.shared.scheduleReminder(for: subtask, reminder: draftReminder)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }
}

private extension TaskItem {
    var hasValidAnchoredReminderAnchor: Bool {
        deadline != nil || plannedDay != nil
    }
}
