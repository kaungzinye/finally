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
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if unfinished.isEmpty {
                    ContentUnavailableView("Day reviewed", systemImage: "checkmark.seal", description: Text("Each unfinished pick has a decision."))
                }
                ForEach(unfinished) { item in
                    Section {
                        if let task = item.task {
                            Button("Keep for \(nextDay.formatted(date: .abbreviated, time: .omitted))") {
                                prepareKeep(item.pick)
                            }
                            Button("Break down") { breakdownTask = task }
                            Button("Schedule") {
                                scheduleDay = max(nextDay, task.plannedDay ?? nextDay)
                                scheduleTask = task
                            }
                            Button("Defer") { decide(item, .deferTask) }
                        }
                        Button("Drop focus pick") { decide(item, .drop) }
                            .accessibilityIdentifier("daily-focus-drop-pick")
                    } header: {
                        Text(item.task?.title ?? "Unavailable task")
                    } footer: {
                        Text("Drop keeps the task and its dates. Defer clears its planned day. Schedule sets its planned day.")
                    }
                }
            }
            .navigationTitle("Review the day")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(isSaving)
                }
            }
            .sheet(isPresented: Binding(get: { keepPick != nil }, set: { if !$0 { keepPick = nil } })) {
                if let nextFocus, let keepPick {
                    NavigationStack {
                        List(nextFocus.resolvedPicks(among: tasks)) { item in
                            Button(item.task?.title ?? "Unavailable task") {
                                let source = ResolvedDailyFocusPick(pick: keepPick, task: tasks.first { $0.dailyFocusPick == keepPick && !$0.isDeleted })
                                decide(source, .keep, nextFocus: nextFocus, displacing: item.pick)
                                self.keepPick = nil
                            }
                        }
                        .navigationTitle("Choose a pick to replace")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { self.keepPick = nil }
                            }
                        }
                    }
                }
            }
            .sheet(item: $scheduleTask) { task in
                NavigationStack {
                    Form {
                        DatePicker("Planned day", selection: $scheduleDay, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        Text("The task's deadline stays fixed.").foregroundStyle(.secondary)
                    }
                    .navigationTitle("Schedule task")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { scheduleTask = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Schedule") {
                                decide(ResolvedDailyFocusPick(pick: task.dailyFocusPick, task: task), .schedule(scheduleDay))
                                scheduleTask = nil
                            }
                        }
                    }
                }
            }
            .sheet(item: $breakdownTask) { task in
                NavigationStack {
                    List {
                        Text("Create unfinished steps for this task, then finish the decision.")
                        Button("Edit task and steps") { showTaskDetail = true }
                        ForEach(task.activeSubtasks) { step in
                            Label(step.title, systemImage: step.status == .done ? "checkmark.circle" : "circle")
                        }
                        Button("Finish breaking down") {
                            decide(ResolvedDailyFocusPick(pick: task.dailyFocusPick, task: task), .breakDown)
                            breakdownTask = nil
                        }
                        .disabled(task.nextActionableSubtask == nil)
                    }
                    .navigationTitle("Break down")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { breakdownTask = nil }
                        }
                    }
                    .sheet(isPresented: $showTaskDetail) { TaskDetailView(task: task) }
                }
            }
        }
    }

    private func prepareKeep(_ pick: DailyFocusPick) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let next = try await service.dailyFocus(for: nextDay, workspace: workspace, store: store, focusLimit: focusLimit)
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
            await taskProvider.submitPendingChangesReportingFailure(for: [task], store: store)
        }
        if let focusError { throw focusError }
    }
}
