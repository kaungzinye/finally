import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Modular interval unit

private enum ReminderIntervalUnit: String, CaseIterable, Identifiable {
    case minutes = "Minutes"
    case hours   = "Hours"
    case days    = "Days"
    case weeks   = "Weeks"
    case months  = "Months"

    var id: String { rawValue }

    var bounds: ClosedRange<Int> {
        switch self {
        case .minutes: return 1...59
        case .hours:   return 1...23
        case .days:    return 1...27
        case .weeks:   return 1...8
        case .months:  return 1...11
        }
    }

    /// Seconds equivalent — used for ReminderItem storage and duplicate detection only.
    /// Months use an average (not Calendar math) because intervalSeconds is an approximation.
    func toSeconds(_ value: Int) -> Int {
        switch self {
        case .minutes: return value * 60
        case .hours:   return value * 3_600
        case .days:    return value * 86_400
        case .weeks:   return value * 604_800
        case .months:  return value * 2_629_746 // ~30.44 days average
        }
    }

    /// Returns the precise fire date using Calendar math for months, simple offset otherwise.
    func fireDate(before baseDate: Date, value: Int) -> Date? {
        switch self {
        case .months:
            return Calendar.current.date(byAdding: .month, value: -value, to: baseDate)
        default:
            return baseDate.addingTimeInterval(-TimeInterval(toSeconds(value)))
        }
    }

    func label(for value: Int) -> String {
        let unit = value == 1 ? String(rawValue.dropLast()) : rawValue
        return "\(value) \(unit.lowercased()) before"
    }
}

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

    @State private var selectedTab: Int = 0
    @State private var intervalValue: Int = 30
    @State private var intervalUnit: ReminderIntervalUnit = .minutes
    @State private var showAbsolutePicker = false
    @State private var absoluteDate = Date()

    private var intervalSeconds: Int { intervalUnit.toSeconds(intervalValue) }
    private var intervalLabel: String { intervalUnit.label(for: intervalValue) }

    private var previewFireDate: Date? {
        guard let base = task.effectiveDate else { return nil }
        return intervalUnit.fireDate(before: base, value: intervalValue)
    }
    private var fireDateIsInPast: Bool { previewFireDate.map { $0 <= Date() } ?? false }
    private var alreadyAdded: Bool {
        task.reminders.contains { $0.intervalSeconds == intervalSeconds && $0.absoluteDate == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Type", selection: $selectedTab) {
                    Text("Interval").tag(0)
                    Text("Exact Date").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if selectedTab == 0 {
                    intervalSection
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
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var intervalSection: some View {
        Section {
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
                ForEach(ReminderIntervalUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            if let fire = previewFireDate {
                if fireDateIsInPast {
                    Label("This time is already in the past", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("Fires: \(fire.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Task has no due date — reminder won't fire")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Button {
                addReminder(label: intervalLabel, seconds: intervalSeconds)
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Add Reminder").fontWeight(.medium)
                    Spacer()
                }
            }
            .disabled(fireDateIsInPast || alreadyAdded || task.effectiveDate == nil)
        }
    }

    @ViewBuilder private var exactDateSection: some View {
        Section {
            Button {
                showAbsolutePicker.toggle()
            } label: {
                HStack {
                    Image(systemName: "clock").foregroundStyle(.orange)
                    Text("Pick exact date & time").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showAbsolutePicker ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if showAbsolutePicker {
                DatePicker(
                    "Remind at",
                    selection: $absoluteDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)

                Button {
                    addAbsoluteReminder(date: absoluteDate)
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Add Reminder").fontWeight(.medium)
                        Spacer()
                    }
                }
            }
        }
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

// MARK: - Subtask Reminder Sheet

struct SubtaskReminderSheet: View {
    @Bindable var subtask: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var intervalValue: Int = 30
    @State private var intervalUnit: ReminderIntervalUnit = .minutes

    private var intervalSeconds: Int { intervalUnit.toSeconds(intervalValue) }
    private var intervalLabel: String { intervalUnit.label(for: intervalValue) }

    private var previewFireDate: Date? {
        guard let base = subtask.effectiveDate else { return nil }
        return intervalUnit.fireDate(before: base, value: intervalValue)
    }
    private var fireDateIsInPast: Bool { previewFireDate.map { $0 <= Date() } ?? false }
    private var alreadyAdded: Bool {
        subtask.reminders.contains { $0.intervalSeconds == intervalSeconds && $0.absoluteDate == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if !subtask.reminders.isEmpty {
                    Section("Current Reminders") {
                        ForEach(subtask.reminders, id: \.id) { reminder in
                            HStack {
                                Image(systemName: "bell").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.label)
                                    if let fire = reminder.fireDate {
                                        Text(fire.formatted(date: .abbreviated, time: .shortened))
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
                                let r = subtask.reminders[index]
                                UNUserNotificationCenter.current()
                                    .removePendingNotificationRequests(withIdentifiers: [r.notificationId])
                                modelContext.delete(r)
                            }
                            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                        }
                    }
                }

                Section {
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
                        ForEach(ReminderIntervalUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Add Reminder")
                } footer: {
                    if let fire = previewFireDate {
                        if fireDateIsInPast {
                            Label("This time is already in the past", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else {
                            Text("Fires: \(fire.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Subtask has no scheduled date yet")
                            .foregroundStyle(.secondary)
                    }
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
                    .disabled(fireDateIsInPast || alreadyAdded || subtask.effectiveDate == nil)
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
        .presentationCompactAdaptation(.sheet)
    }

    private func addSubtaskReminder() {
        Task {
            let status = await NotificationService.shared.checkPermissionStatus()
            if status == .notDetermined {
                _ = await NotificationService.shared.requestPermission()
            }
        }
        let reminder = ReminderItem(
            intervalSeconds: intervalSeconds,
            label: intervalLabel,
            taskNotionPageId: subtask.notionPageId
        )
        reminder.task = subtask
        modelContext.insert(reminder)
        NotificationService.shared.scheduleReminder(for: subtask, reminder: reminder)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }
}
