import SwiftUI
import SwiftData

/// The Board: the Tasks tab's columns of Not started, In progress, and Complete.
/// The status bar names every column with its count, jumps to it on tap, and takes dropped cards,
/// so each column stays reachable without scrolling sideways.
struct BoardView: View {
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var allTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var showFilterSheet = false
    @State private var filterProjects: Set<String> = []
    @State private var filterPriorities: Set<String> = []
    @State private var visibleStatus: TaskStatus? = .notStarted
    @State private var targetedStatus: TaskStatus?

    private var board: BoardColumns {
        BoardColumns(
            tasks: allTasks, workspace: sessions.selectedProviderWorkspace,
            projects: filterProjects, priorities: filterPriorities
        )
    }

    private var hasActiveFilters: Bool {
        !filterProjects.isEmpty || !filterPriorities.isEmpty
    }

    var body: some View {
        Group {
            if taskProvider.isSyncing && allTasks.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Getting your tasks…")
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let board = board
                VStack(spacing: 8) {
                    statusBar(board)
                        .padding(.horizontal, 16)
                    GeometryReader { geo in
                        columns(board, in: geo.size)
                    }
                }
            }
        }
        .background(Palette.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilterSheet = true } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            BoardFilterView(filterProjects: $filterProjects, filterPriorities: $filterPriorities)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.fraction(0.8)])
        }
    }

    // MARK: - Status bar

    private func statusBar(_ board: BoardColumns) -> some View {
        HStack(spacing: 4) {
            ForEach(board.columns) { column in
                let isVisible = visibleStatus == column.status
                let isTargeted = targetedStatus == column.status
                Button {
                    withAnimation(.snappy) { visibleStatus = column.status }
                } label: {
                    HStack(spacing: 6) {
                        Text(column.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("\(column.tasks.count)")
                            .foregroundStyle(isVisible ? Palette.onInk.opacity(0.7) : Palette.muted)
                    }
                    .font(.chip)
                    .foregroundStyle(isVisible ? Palette.onInk : Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        isVisible ? Palette.ink : (isTargeted ? Palette.selection : Color.clear),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("board-status-\(Self.key(column.status))")
                .accessibilityAddTraits(isVisible ? .isSelected : [])
                .dropDestination(for: String.self) { ids, _ in
                    drop(ids, on: column.status)
                } isTargeted: { targeted in
                    targetedStatus = targeted ? column.status : (targetedStatus == column.status ? nil : targetedStatus)
                }
            }
        }
        .padding(4)
        .background(Palette.wash, in: Capsule())
    }

    // MARK: - Columns

    /// Portrait shows one column at a time with the next one peeking. Landscape fits all three.
    private func columns(_ board: BoardColumns, in size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let spacing: CGFloat = 12
        let columnWidth = isLandscape
            ? (size.width - 32 - spacing * 2) / 3
            : size.width - 32 - 40

        return ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(board.columns) { column in
                        columnView(column)
                            .frame(width: columnWidth)
                            .id(column.status)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $visibleStatus, anchor: .leading)
            .padding(.bottom, 72)
        }
        .refreshable {
            try? await taskProvider.synchronize(.launch, store: modelContext)
        }
    }

    /// A column grows only as tall as its cards.
    private func columnView(_ column: BoardColumns.Column) -> some View {
        let isTargeted = targetedStatus == column.status
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: column.title) { Text("\(column.tasks.count)") }
                .padding(.horizontal, 6)
                .padding(.top, 4)

            if column.tasks.isEmpty {
                Text("Drop a card here")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
            } else {
                ForEach(column.tasks, id: \.externalTaskID) { task in
                    BoardCard(task: task, onOpen: { selectedTask = task }, onCycle: { submit(task) })
                        .draggable(task.externalTaskID) {
                            BoardCard(task: task, onOpen: {}, onCycle: {})
                                .frame(width: 240)
                                .onAppear { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        }
                }
            }
        }
        .padding(8)
        .background(
            isTargeted ? Palette.selection : Palette.wash,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-column-\(Self.key(column.status))")
        .dropDestination(for: String.self) { ids, _ in
            drop(ids, on: column.status)
        } isTargeted: { targeted in
            targetedStatus = targeted ? column.status : (targetedStatus == column.status ? nil : targetedStatus)
        }
    }

    // MARK: - Moves

    private func drop(_ ids: [String], on status: TaskStatus) -> Bool {
        targetedStatus = nil
        guard let id = ids.first,
              let task = board.card(withID: id),
              task.status != status else { return false }
        withAnimation(.snappy) {
            let recycled = task.move(to: status)
            if task.status == .done, !recycled {
                NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
            } else {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        submit(task)
        return true
    }

    private func submit(_ task: TaskItem) {
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: modelContext)
        }
    }

    /// A stable accessibility key for a status, free of spaces.
    static func key(_ status: TaskStatus) -> String {
        switch status {
        case .notStarted: "notStarted"
        case .inProgress: "inProgress"
        case .done: "complete"
        }
    }
}

// MARK: - Card

/// One task on the Board: its priority ring and title, then its status chip, date, and project.
/// A card in the window between scheduled day and deadline carries the orange deadline tint.
private struct BoardCard: View {
    @Bindable var task: TaskItem
    let onOpen: () -> Void
    let onCycle: () -> Void

    private var isDone: Bool { task.status == .done }
    private var isTinted: Bool { task.isInActiveWindow }
    private var rowDate: TaskRowDate? { TaskRowDate(for: task, at: Date()) }

    private func color(for date: TaskRowDate) -> Color {
        guard date.kind == .deadline else { return Palette.muted }
        if task.isOverdue { return Palette.urgent }
        if task.isInActiveWindow { return Palette.high }
        return Palette.muted
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                PriorityRing(color: task.priority?.color ?? Palette.low, isDone: isDone, diameter: 18)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .strikethrough(isDone, color: Palette.hairline)
                    .foregroundStyle(isDone ? Palette.muted : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                StatusChip(task: task, onCycle: onCycle)
                Spacer(minLength: 0)
                if let rowDate {
                    Text(rowDate.text)
                        .foregroundStyle(color(for: rowDate))
                }
                if let emoji = task.project?.iconEmoji {
                    Text(emoji)
                } else if let projectTitle = task.project?.title {
                    Text(projectTitle)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
            }
            .font(.meta)
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Palette.card)
            if isTinted { shape.fill(Palette.high.opacity(0.1)) }
        }
        .overlay(shape.strokeBorder(isTinted ? Palette.high.opacity(0.45) : Palette.hairline, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-card-\(task.externalTaskID)")
    }
}
