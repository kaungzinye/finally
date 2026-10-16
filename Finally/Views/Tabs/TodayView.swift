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

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var dailyFocus: DailyFocus?
    @State private var selectedTask: TaskItem?
    @State private var replanningFocus: DailyFocus?
    @State private var isSaving = false
    @State private var showPicker = false
    @State private var showEditor = false

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
    private var isIdle: Bool { !isSaving && replanningFocus == nil && !showPicker && !showEditor }

    private var otherTasks: [Today.Member<TaskItem>] {
        let scoped = tasks.scoped(to: workspace)
        guard let dailyFocus else { return Today.members(of: scoped, at: Date()) }
        return dailyFocus.otherTasks(among: scoped, at: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                TodayHeader(day: day)
                    .paperRow()
                if let dailyFocus {
                    DailyFocusSection(
                        focus: dailyFocus,
                        onChange: { save(dailyFocus) },
                        onSelectTask: { selectedTask = $0 },
                        onAddPick: { showPicker = true },
                        onEditPicks: { showEditor = true },
                        onReviewDay: { replanningFocus = dailyFocus }
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
                            TaskRowView(task: member.task)
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
            .paperList()
            .toolbar(.hidden, for: .navigationBar)
            .disabled(isSaving)
            .task(id: loadID) { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && isIdle {
                    day = Calendar.current.startOfDay(for: Date())
                    Task { await load() }
                }
            }
            // Midnight passing while the app stays open moves Today to the new day.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                if isIdle {
                    day = Calendar.current.startOfDay(for: Date())
                }
            }
            .refreshable {
                day = Calendar.current.startOfDay(for: Date())
                try? await taskProvider.synchronize(.launch, store: modelContext)
                await load()
            }
        }
        .sheet(isPresented: $showPicker) {
            if let dailyFocus {
                DailyFocusPickerView(focus: dailyFocus, onPick: { picked($0, into: dailyFocus) })
            }
        }
        .sheet(isPresented: $showEditor) {
            if let dailyFocus {
                DailyFocusEditorView(focus: dailyFocus, onChange: { save(dailyFocus) })
                    .disabled(isSaving)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
        .sheet(item: $replanningFocus) { focus in
            DailyFocusReplanningView(focus: focus)
        }
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

    /// Picking scheduled the task for the day, so the task's edit syncs alongside the focus.
    private func picked(_ task: TaskItem, into focus: DailyFocus) {
        save(focus)
        guard task.isDirty else { return }
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: [task], store: modelContext)
        }
    }
}

/// The page heading: the weekday and the date.
private struct TodayHeader: View {
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today · \(day.formatted(.dateTime.weekday(.wide)))".uppercased())
                .font(.eyebrow)
                .tracking(0.5)
                .foregroundStyle(Palette.muted)
            Text(day.formatted(.dateTime.day().month(.wide)))
                .font(.pageTitle)
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
