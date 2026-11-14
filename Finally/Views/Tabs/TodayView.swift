import SwiftData
import SwiftUI

/// The first tab. It leads with the Daily Focus and lists the rest of Today under Other tasks.
struct TodayView: View {
    @Query private var sessions: [UserSession]
    @Query private var focuses: [DailyFocus]
    @Query private var tasks: [TaskItem]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(DailyFocusService.self) private var dailyFocusService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppConstants.focusLimitKey) private var focusLimit = DailyFocus.defaultFocusLimit
    /// Settings > Developer switches Today to the UIKit list while it is being built.
    @AppStorage(AppConstants.uikitTodayKey) private var usesUIKitList = false

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var dailyFocus: DailyFocus?
    @State private var selectedTask: TaskItem?
    @State private var replanningFocus: DailyFocus?
    @State private var isSaving = false
    @State private var showPicker = false
    /// A task picked from Other tasks while Daily Focus is full, waiting for the pick it swaps with.
    @State private var swapCandidate: TaskItem?

    private var workspace: UserSession? { sessions.selectedProviderWorkspace }
    private var loadID: String { "\(workspace?.workspaceId ?? "")/\(DailyFocus.dayKey(for: day))" }
    private var unfinishedDays: [DailyFocus] {
        focuses.filter { focus in
            focus.storageWorkspaceID == (workspace?.workspaceId ?? "") && focus.day < day && focus.resolvedPicks(among: tasks).contains {
                $0.task == nil || $0.task?.status != .done
            }
        }.sorted { $0.day < $1.day }
    }

    /// No save or sheet is in flight, so Today can move to another day.
    private var isIdle: Bool { !isSaving && replanningFocus == nil && !showPicker && swapCandidate == nil }

    private var otherTasks: [Today.Member<TaskItem>] {
        let scoped = tasks.scoped(to: workspace)
        guard let dailyFocus else { return Today.members(of: scoped, at: Date()) }
        return dailyFocus.otherTasks(among: scoped, at: Date())
    }

    var body: some View {
        let otherTasks = otherTasks
        NavigationStack {
            Group {
                if usesUIKitList {
                    TodayList(content: TodayListContent(
                        focusHeading: DailyFocusHeading.text(focusLimit: dailyFocus?.focusLimit ?? focusLimit),
                        focus: dailyFocus.map { DailyFocusList(focus: $0, tasks: tasks) },
                        otherTasks: otherTasks.map(\.task)
                    ))
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    swiftUIList(otherTasks)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .disabled(isSaving)
            .task(id: loadID) { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && isIdle {
                    moveToCurrentDay()
                    Task { await load() }
                }
            }
            // Midnight passing while the app stays open moves Today to the new day. A sheet or
            // save open across midnight defers the move until it finishes.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                if isIdle { moveToCurrentDay() }
            }
            .onChange(of: isIdle) { _, idle in
                if idle { moveToCurrentDay() }
            }
            .refreshable {
                moveToCurrentDay()
                try? await taskProvider.synchronize(.launch, store: modelContext)
                await load()
            }
        }
        .sheet(isPresented: $showPicker) {
            if let dailyFocus {
                DailyFocusPickerView(focus: dailyFocus, onPick: { picked($0, into: dailyFocus) })
            }
        }
        .confirmationDialog(
            "Swap with which?",
            isPresented: Binding(get: { swapCandidate != nil }, set: { if !$0 { swapCandidate = nil } }),
            titleVisibility: .visible,
            presenting: swapCandidate
        ) { task in
            if let dailyFocus {
                ForEach(dailyFocus.resolvedPicks(among: tasks)) { item in
                    Button(item.task?.title ?? "Deleted") {
                        pick(task, into: dailyFocus, replacing: item.pick)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text("All \(dailyFocus?.focusLimit ?? focusLimit) picks are taken. \(task.title) takes the place of the one you choose, which keeps its dates.")
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
        .sheet(item: $replanningFocus) { focus in
            DailyFocusReplanningView(focus: focus)
        }
    }



    private func swiftUIList(_ otherTasks: [Today.Member<TaskItem>]) -> some View {
        List {
            // A section header, unlike a row, draws outside its group's rounded clip, so
            // the heading reaches the large-title inset.
            Section {} header: { TodayHeader(day: day) }
                .listSectionSpacing(.compact)
            if let dailyFocus {
                DailyFocusSection(
                    focus: dailyFocus,
                    onChange: { save(dailyFocus) },
                    onSelectTask: { selectedTask = $0 },
                    onAddPick: {
                        // A new day reloads Today, and the user picks into the new day's focus.
                        guard !moveToCurrentDay() else { return }
                        showPicker = true
                    },
                    onReviewDay: DailyFocus.showsReviewTheDay(
                        for: dailyFocus, hasUnfinishedEarlierDay: !unfinishedDays.isEmpty, at: Date()
                    ) ? { replanningFocus = dailyFocus } : nil
                )
                .disabled(isSaving)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .paperRow()
            }
            ForEach(unfinishedDays) { focus in
                Section {
                    Button {
                        replanningFocus = focus
                    } label: {
                        Label("Replan \(focus.day.formatted(.dateTime.weekday(.wide)))", systemImage: "arrow.triangle.branch")
                    }
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("daily-focus-unfinished-day")
                    .cardRow()
                } footer: {
                    SectionNote("Choose what happens to each unfinished task.")
                }
            }
            if !otherTasks.isEmpty {
                Section {
                    ForEach(otherTasks, id: \.task.persistentModelID) { member in
                        TaskRowView(task: member.task, focusAction: .pick { pickFromOtherTasks(member.task) }, layout: .compact)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTask = member.task }
                    }
                } header: {
                    SectionLabel(title: "Other tasks") {
                        Text("\(otherTasks.count)")
                    }
                }
            }
        }
        .paperList(minRowHeight: 40)
        .contentMargins(.top, 4, for: .scrollContent)
    }

    /// Moves Today to the current calendar day. Returns whether the day changed.
    @discardableResult
    private func moveToCurrentDay() -> Bool {
        guard let current = Today.dayChange(from: day, at: Date()) else { return false }
        day = current
        return true
    }

    private func load() async {
        let requestedID = loadID
        if dailyFocus?.storageWorkspaceID != (workspace?.workspaceId ?? "") || dailyFocus?.dayKey != DailyFocus.dayKey(for: day) {
            dailyFocus = nil
        }
        do {
            let loaded = try await dailyFocusService.dailyFocus(
                for: day, workspace: workspace, store: modelContext, focusLimit: focusLimit
            )
            try Task.checkCancellation()
            guard requestedID == loadID else { return }
            dailyFocus = loaded
        } catch is CancellationError {
        } catch {
            dailyFocusService.lastError = error.localizedDescription
        }
    }

    private func save(_ focus: DailyFocus) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await dailyFocusService.save(focus, workspace: workspace, store: modelContext)
            } catch {
                dailyFocusService.lastError = error.localizedDescription
            }
        }
    }

    /// Focus on a task in Other tasks picks it for the day. A full Daily Focus first asks which
    /// pick it swaps with.
    private func pickFromOtherTasks(_ task: TaskItem) {
        guard let dailyFocus, !moveToCurrentDay() else { return }
        if dailyFocus.isFull {
            swapCandidate = task
        } else {
            pick(task, into: dailyFocus, replacing: nil)
        }
    }

    private func pick(_ task: TaskItem, into focus: DailyFocus, replacing displaced: DailyFocusPick?) {
        swapCandidate = nil
        do {
            try focus.pick(task, replacing: displaced)
            picked(task, into: focus)
        } catch {
            dailyFocusService.lastError = error.localizedDescription
        }
    }

    /// Picking scheduled the task for the day, so the task's edit syncs alongside the focus.
    private func picked(_ task: TaskItem, into focus: DailyFocus) {
        save(focus)
        guard task.isDirty else { return }
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: modelContext)
        }
    }
}

/// The page heading: the weekday over the date, at the leading inset of the large titles on
/// Upcoming and Tasks.
private struct TodayHeader: View {
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today · \(day.formatted(.dateTime.weekday(.wide)))".uppercased())
                .font(.eyebrow)
                .tracking(0.5)
                .foregroundStyle(Palette.muted)
            Text(day.formatted(.dateTime.day().month(.wide)))
                .font(.todayTitle)
                .foregroundStyle(Palette.ink)
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, -16)
    }
}
