import SwiftUI
import SwiftData

struct UpcomingView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false && task.deadline != nil
        },
        sort: \TaskItem.deadline
    )
    private var allFutureTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var collapsedDays: Set<Date> = []
    @State private var isSelectionMode = false
    @State private var selectedTasks: Set<String> = []
    @State private var showSearch = false
    @State private var showSortConfig = false
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString

    private var sortStack: SortStack {
        SortStack.from(sortStackJSON)
    }

    private var upcomingTasks: [TaskItem] {
        allFutureTasks.filter {
            $0.belongs(to: sessions.selectedProviderWorkspace) &&
                ($0.deadline ?? .distantFuture) > Date() &&
                !$0.isSubtask
        }
    }

    private var groupedByDay: [(Date, [TaskItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcomingTasks) { task in
            calendar.startOfDay(for: task.deadline ?? .distantFuture)
        }
        return grouped.keys.sorted().map { day in
            (day, sortStack.sorted(grouped[day] ?? []))
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.weekday(.abbreviated).day())
        if calendar.isDateInToday(day) { return "Today · \(date)" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow · \(date)" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        NavigationStack {
            if taskProvider.isSyncing && allFutureTasks.isEmpty {
                // First-load sync: replace content entirely
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Syncing your tasks…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Upcoming")
            } else {
                ScrollViewReader { proxy in
                    List {
                        WeekStrip(daysWithTasks: Set(groupedByDay.map(\.0))) { day in
                            collapsedDays.remove(day)
                            withAnimation { proxy.scrollTo(day, anchor: .top) }
                        }
                        .paperRow()

                        ForEach(groupedByDay, id: \.0) { day, tasks in
                            Section {
                                if !collapsedDays.contains(day) {
                                    ForEach(tasks, id: \.externalTaskID) { task in
                                        taskRow(task)
                                    }
                                }
                            } header: {
                                Button {
                                    withAnimation {
                                        if collapsedDays.contains(day) {
                                            collapsedDays.remove(day)
                                        } else {
                                            collapsedDays.insert(day)
                                        }
                                    }
                                } label: {
                                    SectionLabel(title: dayTitle(day)) {
                                        HStack(spacing: 6) {
                                            Text("\(tasks.count)")
                                            Image(systemName: "chevron.right")
                                                .rotationEffect(.degrees(collapsedDays.contains(day) ? 0 : 90))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .id(day)
                        }
                }
                .paperList()
                }
                .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "Upcoming")
                .refreshable {
                    try? await taskProvider.synchronize(.launch, store: modelContext)
                }
                .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            withAnimation {
                                isSelectionMode = false
                                selectedTasks.removeAll()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                bulkDeleteTasks()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(selectedTasks.isEmpty)

                            Button {
                                bulkCompleteTasks()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .disabled(selectedTasks.isEmpty)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button { showSortConfig = true } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }

                            Button { showSearch = true } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                }
            }
            .overlay {
                if upcomingTasks.isEmpty {
                    ContentUnavailableView(
                        "No upcoming tasks",
                        systemImage: "calendar",
                        description: Text("Tasks with deadlines will appear here")
                    )
                }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.fraction(0.8)])
            }
            .sheet(isPresented: $showSearch) {
                SearchFilterView()
            }
            .sheet(isPresented: $showSortConfig) {
                SortConfigView(sortStack: Binding(
                    get: { SortStack.from(sortStackJSON) },
                    set: { sortStackJSON = $0.jsonString }
                ))
                .presentationDetents([.medium])
            }
            }
        }
    }

    // MARK: - Reusable Row

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
        .listRowBackground(
            isSelectionMode && selectedTasks.contains(task.externalTaskID)
                ? Palette.selection
                : Palette.card
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                if selectedTasks.contains(task.externalTaskID) {
                    selectedTasks.remove(task.externalTaskID)
                } else {
                    selectedTasks.insert(task.externalTaskID)
                }
            } else {
                selectedTask = task
            }
        }
        .onLongPressGesture {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            withAnimation {
                isSelectionMode = true
                selectedTasks.insert(task.externalTaskID)
            }
        }
    }

    // MARK: - Bulk Actions

    private func bulkDeleteTasks() {
        let tasksToDelete = allFutureTasks.filter { selectedTasks.contains($0.externalTaskID) }
        for task in tasksToDelete {
            task.isDeleted = true
            task.isDirty = true
        }
        submitMutations(tasksToDelete)
        withAnimation {
            isSelectionMode = false
            selectedTasks.removeAll()
        }
    }

    private func bulkCompleteTasks() {
        let tasksToComplete = allFutureTasks.filter { selectedTasks.contains($0.externalTaskID) }
        for task in tasksToComplete {
            let recycled = task.complete()
            if recycled {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task)
            }
        }
        submitMutations(tasksToComplete)
        withAnimation {
            isSelectionMode = false
            selectedTasks.removeAll()
        }
    }

    private func submitMutations(_ tasks: [TaskItem]) {
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: tasks, store: modelContext)
        }
    }
}

/// The next seven days. A dot marks a day with deadlines, and tapping a day scrolls to it.
private struct WeekStrip: View {
    let daysWithTasks: Set<Date>
    let onSelect: (Date) -> Void

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = day == selectedDay
                Button {
                    selectedDay = day
                    onSelect(day)
                } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.meta)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(isSelected ? Palette.onInk : Palette.ink)
                        Circle()
                            .frame(width: 4, height: 4)
                            .opacity(daysWithTasks.contains(day) ? 0.6 : 0)
                    }
                    .foregroundStyle(isSelected ? Palette.onInk : Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Palette.ink : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
