import SwiftData
import SwiftUI

struct DailyFocusReplanningView: View {
    let focus: DailyFocus

    @Query private var tasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(DailyFocusService.self) private var service
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConstants.focusLimitKey) private var focusLimit = DailyFocus.defaultFocusLimit

    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var nextFocus: DailyFocus?
    @State private var keepPick: DailyFocusPick?
    @State private var scheduleTask: TaskItem?
    @State private var scheduleDay = Calendar.current.startOfDay(for: Date())
    @State private var breakdownTask: TaskItem?
    @State private var showTaskDetail = false

    private var workspace: UserSession? { sessions.selectedProviderWorkspace }
    private var unfinished: [ResolvedDailyFocusPick] {
        focus.resolvedPicks(among: tasks).filter { $0.task?.status != .done }
    }
    private var nextDay: Date {
        max(Calendar.current.startOfDay(for: Date()), Calendar.current.date(byAdding: .day, value: 1, to: focus.day) ?? focus.day)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Callout(message: errorMessage)
                        .paperRow()
                }
                if unfinished.isEmpty {
                    ContentUnavailableView("Day reviewed", systemImage: "checkmark.seal", description: Text("Every unfinished task has a decision."))
                        .paperRow()
                }
                ForEach(unfinished) { item in
                    Section {
                        if let task = item.task {
                            Button("Keep for \(nextDay.formatted(.dateTime.weekday(.wide)))") {
                                prepareKeep(item.pick)
                            }
                            Button("Break it down") { breakdownTask = task }
                            Button("Schedule") {
                                scheduleDay = max(nextDay, task.scheduledDay ?? nextDay)
                                scheduleTask = task
                            }
                            Button("Defer") { decide(item, .deferTask) }
                        }
                        Button("Drop") { decide(item, .drop) }
                            .accessibilityIdentifier("daily-focus-drop-pick")
                    } header: {
                        SectionLabel(item.task?.title ?? "Deleted")
                    } footer: {
                        SectionNote("Drop keeps the task and its dates. Defer clears its scheduled day. Schedule picks a new one.")
                    }
                    .foregroundStyle(Palette.ink)
                    .cardRow()
                }
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Review the day")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ConfirmToolbarButton("Done", isDisabled: isSaving) { dismiss() }
            }
            .sheet(isPresented: Binding(get: { keepPick != nil }, set: { if !$0 { keepPick = nil } })) {
                if let nextFocus, let keepPick {
                    NavigationStack {
                        List {
                            Section {
                                ForEach(nextFocus.resolvedPicks(among: tasks)) { item in
                                    Button(item.task?.title ?? "Deleted") {
                                        let source = ResolvedDailyFocusPick(pick: keepPick, task: tasks.first { $0.dailyFocusPick == keepPick && !$0.isDeleted })
                                        decide(source, .keep, nextFocus: nextFocus, displacing: item.pick)
                                        self.keepPick = nil
                                    }
                                    .foregroundStyle(Palette.ink)
                                    .cardRow()
                                }
                            } header: {
                                SectionNote("\(nextDay.formatted(.dateTime.weekday(.wide))) is full. The task you replace keeps its dates.")
                            }
                        }
                        .paperList(background: Palette.sheet)
                        .navigationTitle("Choose a task to replace")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { self.keepPick = nil }
                            }
                        }
                    }
                    .paperSheet()
                }
            }
            .sheet(item: $scheduleTask) { task in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Scheduled", selection: $scheduleDay, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Palette.inkControl)
                        SectionNote("The deadline stays where it is.")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .background(Palette.sheet)
                    .navigationTitle("Schedule")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { scheduleTask = nil }
                        }
                        ConfirmToolbarButton("Schedule") {
                            decide(ResolvedDailyFocusPick(pick: task.dailyFocusPick, task: task), .schedule(scheduleDay))
                            scheduleTask = nil
                        }
                    }
                }
                .paperSheet()
            }
            .sheet(item: $breakdownTask) { task in
                NavigationStack {
                    List {
                        Section {
                            Button("Edit the task and its steps") { showTaskDetail = true }
                            ForEach(task.activeSubtasks) { step in
                                HStack(spacing: 12) {
                                    PriorityRing(color: step.priority?.color ?? Palette.low, isDone: step.status == .done, diameter: 18)
                                    Text(step.title)
                                }
                            }
                        } header: {
                            SectionNote("Add the unfinished steps, then finish here.")
                        }
                        .foregroundStyle(Palette.ink)
                        .cardRow()

                        Section {
                            Button("Finish breaking down") {
                                decide(ResolvedDailyFocusPick(pick: task.dailyFocusPick, task: task), .breakDown)
                                breakdownTask = nil
                            }
                            .buttonStyle(.ink)
                            .disabled(task.nextActionableSubtask == nil)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    .paperList(background: Palette.sheet)
                    .navigationTitle("Break it down")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { breakdownTask = nil }
                        }
                    }
                    .sheet(isPresented: $showTaskDetail) { TaskDetailView(task: task) }
                }
                .paperSheet()
            }
        }
        .paperSheet()
    }

    private func prepareKeep(_ pick: DailyFocusPick) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let next = try await service.dailyFocus(for: nextDay, workspace: workspace, store: store, focusLimit: focusLimit, requireServerLoad: true)
                nextFocus = next
                if next.isFull && !next.picks.contains(pick) {
                    keepPick = pick
                } else {
                    let item = ResolvedDailyFocusPick(pick: pick, task: tasks.first { $0.dailyFocusPick == pick && !$0.isDeleted })
                    try focus.replan(item.pick, decision: .keep, task: item.task, nextFocus: next)
                    try await persist(item.task, nextFocus: next)
                    errorMessage = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func decide(
        _ item: ResolvedDailyFocusPick,
        _ decision: DailyFocusReplanningDecision,
        nextFocus: DailyFocus? = nil,
        displacing: DailyFocusPick? = nil
    ) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try focus.replan(item.pick, decision: decision, task: item.task, nextFocus: nextFocus, displacing: displacing)
                try await persist(item.task, nextFocus: nextFocus)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func persist(_ task: TaskItem?, nextFocus: DailyFocus?) async throws {
        let changed = nextFocus.map { [$0, focus] } ?? [focus]
        var focusError: Error?
        do {
            try await service.save(changed, workspace: workspace, store: store)
        } catch {
            focusError = error
        }
        if let task, task.isDirty {
            NotificationService.shared.rescheduleAllReminders(modelContext: store)
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: store)
        }
        if let focusError { throw focusError }
    }
}
