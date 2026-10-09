import SwiftData
import SwiftUI

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

    private var workspace: UserSession? { sessions.selectedProviderWorkspace }
    private var loadID: String { "\(workspace?.workspaceId ?? "")/\(DailyFocus.dayKey(for: day))" }
    private var unfinishedDays: [DailyFocus] {
        let today = Calendar.current.startOfDay(for: Date())
        return focuses.filter { focus in
            focus.storageWorkspaceID == (workspace?.workspaceId ?? "") && focus.day < today && focus.resolvedPicks(among: tasks).contains {
                $0.task == nil || $0.task?.status != .done
            }
        }.sorted { $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Focus day", selection: $day, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        .accessibilityIdentifier("daily-focus-day")
                    if !Calendar.current.isDateInToday(day) {
                        Text("Review the picks for this day. Confirmation keeps each task's planned day and deadline.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(unfinishedDays) { focus in
                    Section {
                        Button {
                            replanningFocus = focus
                        } label: {
                            Label("Replan \(focus.day.formatted(date: .abbreviated, time: .omitted))", systemImage: "arrow.triangle.branch")
                        }
                        .accessibilityIdentifier("daily-focus-unfinished-day")
                    } footer: {
                        Text("Choose what happens to each unfinished pick.")
                    }
                }
                if let dailyFocus {
                    DailyFocusSection(
                        focus: dailyFocus,
                        onChange: { save(dailyFocus) },
                        onSelectTask: { selectedTask = $0 }
                    )
                    .disabled(isSaving)
                    if Calendar.current.isDateInToday(day), !dailyFocus.picks.isEmpty {
                        Section {
                            Button {
                                replanningFocus = dailyFocus
                            } label: {
                                Label("Review the day", systemImage: "arrow.triangle.branch")
                            }
                            .accessibilityIdentifier("daily-focus-review-day")
                        }
                    }
                } else {
                    ProgressView("Loading Daily Focus…")
                }
                Section {
                    NavigationLink {
                        DeadlineReviewView()
                    } label: {
                        Label("Review deadlines", systemImage: "calendar.badge.exclamationmark")
                    }
                    .accessibilityIdentifier("daily-focus-deadlines")
                }
            }
            .paperList()
            .navigationTitle("Daily Focus")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tomorrow") {
                        day = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    }
                    .accessibilityIdentifier("daily-focus-tomorrow")
                }
            }
            .disabled(isSaving)
            .task(id: loadID) { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !isSaving { Task { await load() } }
            }
            .refreshable {
                try? await taskProvider.synchronize(.launch, store: modelContext)
                await load()
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
        dailyFocus = nil
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
}
