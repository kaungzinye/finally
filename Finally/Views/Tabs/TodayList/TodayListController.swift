import SwiftData
import SwiftUI
import UIKit

/// Draws Today with a `UICollectionView`, Apple's list and grid view, in three parts:
/// - The **layout** decides where rows go. A list layout stacks them in sections and draws
///   rounded groups, the same look as SwiftUI's inset grouped `List`.
/// - The **data source** decides which rows exist. It takes a snapshot, a list of sections and
///   the row IDs in each, and animates the difference from the snapshot before it.
/// - A **cell registration** decides what one kind of row looks like. The collection view reuses
///   cells as they scroll off screen, so a registration fills a recycled cell for a given row.
///
/// A Daily Focus pick is a native cell whose height eases between open and done. The rows that
/// never resize host their SwiftUI views.
final class TodayListController: UIViewController, UICollectionViewDelegate {
    enum Section: Hashable {
        case heading
        case focus
        case confirm
        case unfinishedDays
        case otherTasks
    }

    /// One row on Today. Each case carries only what identifies the row, so the data source can
    /// tell a changed row from a new one. The content behind it lives in the lookups below.
    enum Row: Hashable {
        /// The weekday over the date.
        case heading
        /// Stands in for Daily Focus while the day's focus loads.
        case loading
        /// A Daily Focus pick, open, done, or with its task deleted.
        case pick(DailyFocusPick)
        /// An open place in Daily Focus, by its number.
        case emptySlot(Int)
        case reviewDay
        case confirm
        /// An earlier day with unfinished picks.
        case unfinishedDay(PersistentIdentifier)
        /// A task in Other tasks.
        case otherTask(PersistentIdentifier)
    }

    var actions: TodayListActions?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

    /// The content behind the current snapshot, read when a cell or header is filled.
    private var content = TodayListContent(
        day: .now, focusHeading: "", focus: nil, needsConfirmation: false, showsReviewTheDay: false,
        unfinishedDays: [], otherTasks: [], isSaving: false
    )
    private var picks: [DailyFocusPick: DailyFocusList.Row] = [:]
    private var otherTasks: [PersistentIdentifier: TaskItem] = [:]
    private var unfinishedDays: [PersistentIdentifier: DailyFocus] = [:]
    /// Whether each pick was last drawn done, so a change eases instead of jumping.
    private var shownDone: [DailyFocusPick: Bool] = [:]
    /// Whether each pick last had its task. A deleted task's pick draws in another kind of cell,
    /// which reconfiguring can't swap in, so that row reloads.
    private var shownHasTask: [DailyFocusPick: Bool] = [:]

    /// A drag is moving a pick. Updates wait for the drop, since a new snapshot mid-drag would
    /// cancel it.
    private var isReordering = false
    private var contentWaitingForDrop: TodayListContent?

    /// The same curve the SwiftUI pick used for its collapse and reopen.
    private static let pickSpring = (duration: 0.3, damping: 1.0)

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        // The collection view fills the controller's view and follows its size.
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = UIColor(Palette.paper)
        collectionView.delegate = self
        // A cell whose constraints change asks for a new height on the next layout pass.
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        // The last row scrolls clear of the floating add button.
        collectionView.contentInset.bottom = 96
        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)
        collectionView.refreshControl = refreshControl
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(reorder(_:)))
        longPress.minimumPressDuration = 0.4
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        dataSource = makeDataSource()
    }

    // MARK: - Showing content

    /// Replaces what the list shows. Called by SwiftUI on every update, so it stays cheap: it
    /// builds a snapshot of rows and lets the data source find the difference.
    func show(_ content: TodayListContent) {
        guard !isReordering else {
            contentWaitingForDrop = content
            return
        }
        self.content = content
        let rows = content.focus?.rows ?? []
        picks = Dictionary(rows.map { ($0.pick, $0) }, uniquingKeysWith: { first, _ in first })
        otherTasks = Dictionary(content.otherTasks.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        unfinishedDays = Dictionary(content.unfinishedDays.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        collectionView.isUserInteractionEnabled = !content.isSaving

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.heading, .focus])
        snapshot.appendItems([.heading], toSection: .heading)
        if let focus = content.focus {
            snapshot.appendItems(focus.rows.map { .pick($0.pick) }, toSection: .focus)
            snapshot.appendItems(focus.emptySlotNumbers.map { .emptySlot($0) }, toSection: .focus)
            if content.showsReviewTheDay { snapshot.appendItems([.reviewDay], toSection: .focus) }
        } else {
            snapshot.appendItems([.loading], toSection: .focus)
        }
        if content.needsConfirmation {
            snapshot.appendSections([.confirm])
            snapshot.appendItems([.confirm], toSection: .confirm)
        }
        if !content.unfinishedDays.isEmpty {
            snapshot.appendSections([.unfinishedDays])
            snapshot.appendItems(content.unfinishedDays.map { .unfinishedDay($0.persistentModelID) }, toSection: .unfinishedDays)
        }
        // A section with no rows would still draw its header, so Other tasks appears only with tasks.
        if !content.otherTasks.isEmpty {
            snapshot.appendSections([.otherTasks])
            snapshot.appendItems(content.otherTasks.map { .otherTask($0.persistentModelID) }, toSection: .otherTasks)
        }

        // A pick on screen that moved between open and done eases in place below. Every other
        // row keeps its identity when its task changes, so reconfiguring reruns its registration
        // to draw a new title or color.
        let toggled = Set(rows.filter { row in
            guard let wasDone = shownDone[row.pick], wasDone != row.isDone, row.task != nil else { return false }
            return pickCell(for: row.pick) != nil
        }.map(\.pick))
        let changedKind = Set(rows.filter { row in
            shownHasTask[row.pick].map { $0 != (row.task != nil) } ?? false
        }.map(\.pick))
        snapshot.reloadItems(changedKind.map { .pick($0) })
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { row in
            if case .pick(let pick) = row { return !toggled.contains(pick) && !changedKind.contains(pick) }
            return true
        })
        // The first snapshot appears at once. Later ones animate their inserts and deletes.
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        shownDone = Dictionary(rows.map { ($0.pick, $0.isDone) }, uniquingKeysWith: { first, _ in first })
        shownHasTask = Dictionary(rows.map { ($0.pick, $0.task != nil) }, uniquingKeysWith: { first, _ in first })
        easePicks(toggled)
        refreshHeaders()
    }

    /// Redraws each pick between open and done on the pick spring. Laying out the collection
    /// view inside the same animation eases the row's height, and the rows below move with it.
    private func easePicks(_ toggled: Set<DailyFocusPick>) {
        let changes = toggled.compactMap { pick -> (FocusPickCell, FocusPickCell.Model)? in
            guard let cell = pickCell(for: pick), let row = picks[pick], let model = Self.pickModel(row) else { return nil }
            return (cell, model)
        }
        guard !changes.isEmpty else { return }
        UIView.animate(
            withDuration: Self.pickSpring.duration, delay: 0,
            usingSpringWithDamping: Self.pickSpring.damping, initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            for (cell, model) in changes {
                cell.setDone(model)
                cell.contentView.layoutIfNeeded()
                cell.invalidateIntrinsicContentSize()
            }
            self.collectionView.layoutIfNeeded()
        }
    }

    private func pickCell(for pick: DailyFocusPick) -> FocusPickCell? {
        guard let indexPath = dataSource.indexPath(for: .pick(pick)) else { return nil }
        return collectionView.cellForItem(at: indexPath) as? FocusPickCell
    }

    private func refresh() {
        Task {
            await actions?.refresh()
            collectionView.refreshControl?.endRefreshing()
        }
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            let section = self?.dataSource?.sectionIdentifier(for: index)
            var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            list.backgroundColor = .clear
            list.headerMode = section == .focus || section == .otherTasks ? .supplementary : .none
            list.footerMode = section == .unfinishedDays ? .supplementary : .none
            list.leadingSwipeActionsConfigurationProvider = { [weak self] in self?.leadingSwipe(at: $0) }
            list.trailingSwipeActionsConfigurationProvider = { [weak self] in self?.trailingSwipe(at: $0) }
            let layoutSection = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            if section == .heading {
                layoutSection.contentInsets.top = 4
                layoutSection.contentInsets.bottom = 0
            }
            return layoutSection
        }
    }

    // MARK: - Cells

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Row> {
        // One registration per kind of row. Each one's second type is what it's filled from.
        let headingCell = UICollectionView.CellRegistration<UICollectionViewListCell, Date> { cell, _, day in
            cell.contentConfiguration = UIHostingConfiguration { TodayHeader(day: day, leadingInset: 0) }
                .margins(.horizontal, 0)
            cell.backgroundConfiguration = .clear()
        }
        let loadingCell = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration { ProgressView().frame(maxWidth: .infinity) }
            cell.backgroundConfiguration = .clear()
        }
        let pickCell = UICollectionView.CellRegistration<FocusPickCell, DailyFocusPick> { [weak self] cell, _, pick in
            guard let row = self?.picks[pick], let task = row.task, let model = Self.pickModel(row) else { return }
            cell.show(model)
            cell.onToggle = { [weak self] in self?.actions?.toggleCompletion(task) }
            cell.onMove = { [weak self] offset in self?.move(pick, by: offset) ?? false }
            Self.drawOnCard(cell)
        }
        let deletedPickCell = UICollectionView.CellRegistration<UICollectionViewListCell, DailyFocusPick> { [weak self] cell, _, pick in
            let number = self?.picks[pick]?.number ?? 0
            cell.contentConfiguration = UIHostingConfiguration {
                SlotRow(number: number, text: "Deleted") {
                    Button("Drop") { self?.actions?.removePick(pick) }
                        .buttonStyle(.borderless)
                }
            }
            .margins(.horizontal, 20)
            .margins(.vertical, 0)
            Self.drawOnCard(cell)
        }
        let emptySlotCell = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, number in
            cell.contentConfiguration = UIHostingConfiguration {
                SlotRow(number: number, text: "Pick a task") {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .margins(.horizontal, 20)
            .margins(.vertical, 0)
            Self.drawOnCard(cell)
            cell.accessibilityIdentifier = "daily-focus-add-pick"
        }
        let reviewDayCell = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                Label("Review the day", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Self.drawOnCard(cell)
        }
        let confirmCell = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { [weak self] cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                Button("Confirm") { self?.actions?.confirm() }
                    .buttonStyle(.ink)
                    .accessibilityIdentifier("daily-focus-confirm")
            }
            .margins(.all, 0)
            cell.backgroundConfiguration = .clear()
        }
        let unfinishedDayCell = UICollectionView.CellRegistration<UICollectionViewListCell, PersistentIdentifier> { [weak self] cell, _, id in
            let day = self?.unfinishedDays[id]?.day ?? .now
            cell.contentConfiguration = UIHostingConfiguration {
                Label("Replan \(day.formatted(.dateTime.weekday(.wide)))", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Self.drawOnCard(cell)
        }
        let otherTaskCell = UICollectionView.CellRegistration<UICollectionViewListCell, PersistentIdentifier> { [weak self] cell, _, id in
            guard let task = self?.otherTasks[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                OtherTaskRow(task: task) { self?.actions?.toggleCompletion(task) }
            }
            .margins(.horizontal, 20)
            .margins(.vertical, 0)
            Self.drawOnCard(cell)
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { [weak self] collectionView, indexPath, row in
            // The cell provider picks the registration that matches the row's kind.
            switch row {
            case .heading:
                collectionView.dequeueConfiguredReusableCell(using: headingCell, for: indexPath, item: self?.content.day ?? .now)
            case .loading:
                collectionView.dequeueConfiguredReusableCell(using: loadingCell, for: indexPath, item: row)
            case .pick(let pick):
                if self?.picks[pick]?.task == nil {
                    collectionView.dequeueConfiguredReusableCell(using: deletedPickCell, for: indexPath, item: pick)
                } else {
                    collectionView.dequeueConfiguredReusableCell(using: pickCell, for: indexPath, item: pick)
                }
            case .emptySlot(let number):
                collectionView.dequeueConfiguredReusableCell(using: emptySlotCell, for: indexPath, item: number)
            case .reviewDay:
                collectionView.dequeueConfiguredReusableCell(using: reviewDayCell, for: indexPath, item: row)
            case .confirm:
                collectionView.dequeueConfiguredReusableCell(using: confirmCell, for: indexPath, item: row)
            case .unfinishedDay(let id):
                collectionView.dequeueConfiguredReusableCell(using: unfinishedDayCell, for: indexPath, item: id)
            case .otherTask(let id):
                collectionView.dequeueConfiguredReusableCell(using: otherTaskCell, for: indexPath, item: id)
            }
        }

        // A header or footer is a supplementary view: it belongs to a section rather than to a row.
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            self?.fillHeader(header, at: indexPath)
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footer, _, _ in
            footer.contentConfiguration = UIHostingConfiguration {
                SectionNote("Choose what happens to each unfinished task.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionFooter {
                return collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
            }
            return collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }

        // Only picks move, open or done. The collection view asks before a drag starts.
        dataSource.reorderingHandlers.canReorderItem = { row in
            if case .pick = row { return true }
            return false
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            let before = transaction.initialSnapshot.itemIdentifiers(inSection: .focus)
            let after = transaction.finalSnapshot.itemIdentifiers(inSection: .focus)
            guard let move = Self.singleMove(from: before, to: after) else { return }
            self?.actions?.movePick(move.from, move.to)
        }
        return dataSource
    }

    /// Headers aren't rows, so reconfiguring skips them. The ones on screen are refilled in place.
    private func refreshHeaders() {
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard let header = collectionView.supplementaryView(forElementKind: kind, at: indexPath) as? UICollectionViewListCell else { continue }
            fillHeader(header, at: indexPath)
        }
    }

    private func fillHeader(_ header: UICollectionViewListCell, at indexPath: IndexPath) {
        guard let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
        switch section {
        case .focus:
            let heading = content.focusHeading
            let status = content.focus?.status ?? ""
            header.contentConfiguration = UIHostingConfiguration {
                HStack(alignment: .firstTextBaseline) {
                    Text(heading)
                        .font(.focusHeading)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(status)
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("daily-focus-progress")
                }
                .padding(.bottom, 4)
            }
        case .otherTasks:
            let count = content.otherTasks.count
            header.contentConfiguration = UIHostingConfiguration {
                SectionLabel(title: "Other tasks") { Text("\(count)") }
            }
        case .heading, .confirm, .unfinishedDays:
            header.contentConfiguration = nil
        }
    }

    /// What a pick cell draws for a row. Nil for a pick whose task is gone.
    private static func pickModel(_ row: DailyFocusList.Row) -> FocusPickCell.Model? {
        guard let task = row.task else { return nil }
        return FocusPickCell.Model(
            number: row.number,
            title: task.title,
            meta: focusMeta(for: task),
            isNext: row.isNext,
            isDone: row.isDone,
            ringColor: UIColor(task.priority?.color ?? Palette.low)
        )
    }

    /// The deadline and the project under an open pick's title. The deadline reads red when
    /// overdue and orange in its active window.
    private static func focusMeta(for task: TaskItem) -> NSAttributedString? {
        guard let meta = TaskRowDate.FocusMeta(for: task, project: task.project?.title, at: Date()) else { return nil }
        let muted = UIColor(Palette.muted)
        let line = NSMutableAttributedString()
        if let deadline = meta.deadline {
            let tone: UIColor = switch meta.tone {
            case .overdue: UIColor(Palette.urgent)
            case .activeWindow: UIColor(Palette.high)
            case .quiet: muted
            }
            line.append(NSAttributedString(string: deadline, attributes: [.foregroundColor: tone]))
        }
        if let project = meta.project {
            if line.length > 0 { line.append(NSAttributedString(string: " · ", attributes: [.foregroundColor: muted])) }
            line.append(NSAttributedString(string: project, attributes: [.foregroundColor: muted]))
        }
        return line
    }

    /// Draws a row on its group's card. A swiped row rounds its corners, so they show against
    /// the revealed action, and a pressed row darkens.
    private static func drawOnCard(_ cell: UICollectionViewListCell) {
        cell.configurationUpdateHandler = { cell, state in
            var background: UIBackgroundConfiguration
            if #available(iOS 18, *) {
                background = .listCell()
            } else {
                background = .listGroupedCell()
            }
            background.backgroundColor = UIColor(state.isHighlighted ? Palette.selection : Palette.card)
            if state.isSwiped { background.cornerRadius = PaperGroup.cornerRadius }
            cell.backgroundConfiguration = background
        }
    }

    // MARK: - Taps

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .pick(let pick): picks[pick]?.task != nil
        case .emptySlot, .reviewDay, .unfinishedDay, .otherTask: true
        case .heading, .loading, .confirm, nil: false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let actions, let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .pick(let pick):
            if let task = picks[pick]?.task { actions.select(task) }
        case .emptySlot:
            actions.addPick()
        case .reviewDay:
            actions.reviewDay()
        case .unfinishedDay(let id):
            if let focus = unfinishedDays[id] { actions.replan(focus) }
        case .otherTask(let id):
            if let task = otherTasks[id] { actions.select(task) }
        case .heading, .loading, .confirm:
            break
        }
    }

    // MARK: - Swipes

    private func task(at indexPath: IndexPath) -> TaskItem? {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .pick(let pick): picks[pick]?.task
        case .otherTask(let id): otherTasks[id]
        default: nil
        }
    }

    /// Swiping right completes an open task and reopens a finished one.
    private func leadingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let task = task(at: indexPath) else { return nil }
        let isDone = task.status == .done
        let toggle = UIContextualAction(style: .normal, title: isDone ? "Reopen" : "Complete") { [weak self] _, _, finish in
            self?.actions?.toggleCompletion(task)
            finish(true)
        }
        toggle.image = UIImage(systemName: isDone ? "arrow.uturn.backward" : "checkmark")
        toggle.backgroundColor = UIColor(Palette.done)
        return UISwipeActionsConfiguration(actions: [toggle])
    }

    /// Swiping left offers Reschedule, then Remove on a pick or Focus on a task in Other tasks.
    /// A pick whose task is gone offers only Drop.
    private func trailingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let row = dataSource.itemIdentifier(for: indexPath)
        if case .pick(let pick) = row, picks[pick]?.task == nil {
            let drop = UIContextualAction(style: .destructive, title: "Drop") { [weak self] _, _, finish in
                self?.actions?.removePick(pick)
                finish(true)
            }
            return UISwipeActionsConfiguration(actions: [drop])
        }
        guard let task = task(at: indexPath) else { return nil }
        let reschedule = UIContextualAction(style: .normal, title: "Reschedule") { [weak self] _, _, finish in
            self?.actions?.reschedule(task)
            finish(true)
        }
        reschedule.image = UIImage(systemName: "calendar")
        reschedule.backgroundColor = UIColor(Palette.highFill)
        switch row {
        case .pick(let pick):
            let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, finish in
                self?.actions?.removePick(pick)
                finish(true)
            }
            remove.image = UIImage(systemName: "minus.circle")
            return UISwipeActionsConfiguration(actions: [reschedule, remove])
        default:
            let focus = UIContextualAction(style: .normal, title: "Focus") { [weak self] _, _, finish in
                self?.actions?.focus(task)
                finish(true)
            }
            focus.image = UIImage(systemName: "scope")
            focus.backgroundColor = UIColor(Palette.inkControl)
            return UISwipeActionsConfiguration(actions: [reschedule, focus])
        }
    }

    // MARK: - Reordering

    /// A long press lifts a pick, and dragging moves it among the picks.
    @objc private func reorder(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: collectionView)
        switch gesture.state {
        case .began:
            guard (content.focus?.rows.count ?? 0) > 1,
                  let indexPath = collectionView.indexPathForItem(at: location),
                  case .pick = dataSource.itemIdentifier(for: indexPath)
            else { return }
            isReordering = collectionView.beginInteractiveMovementForItem(at: indexPath)
            if isReordering { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .changed:
            guard isReordering else { return }
            // The row follows the finger up and down only.
            collectionView.updateInteractiveMovementTargetPosition(CGPoint(x: collectionView.bounds.midX, y: location.y))
        case .ended:
            guard isReordering else { return }
            collectionView.endInteractiveMovement()
            finishReordering()
        default:
            guard isReordering else { return }
            collectionView.cancelInteractiveMovement()
            finishReordering()
        }
    }

    private func finishReordering() {
        isReordering = false
        if let waiting = contentWaitingForDrop {
            contentWaitingForDrop = nil
            show(waiting)
        }
    }

    /// VoiceOver's Move up and Move down. The new order saves as a drag's does.
    private func move(_ pick: DailyFocusPick, by offset: Int) -> Bool {
        let rows = content.focus?.rows ?? []
        guard let from = rows.firstIndex(where: { $0.pick == pick }), rows.indices.contains(from + offset) else { return false }
        actions?.movePick(from, from + offset)
        UIAccessibility.post(notification: .announcement, argument: "Pick \(from + offset + 1) of \(rows.count)")
        return true
    }

    /// A dragged pick stays among the picks, above the open slots.
    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveOfItemFromOriginalIndexPath originalIndexPath: IndexPath,
        atCurrentIndexPath currentIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        guard let focus = dataSource.index(for: .focus) else { return currentIndexPath }
        let last = max((content.focus?.rows.count ?? 1) - 1, 0)
        if proposedIndexPath.section < focus { return IndexPath(item: 0, section: focus) }
        if proposedIndexPath.section > focus { return IndexPath(item: last, section: focus) }
        return IndexPath(item: min(proposedIndexPath.item, last), section: focus)
    }

    /// The one row that moved between two orders that differ by a single move.
    static func singleMove<Item: Equatable>(from before: [Item], to after: [Item]) -> (from: Int, to: Int)? {
        guard before.count == after.count,
              let first = before.indices.first(where: { before[$0] != after[$0] }),
              let last = before.indices.last(where: { before[$0] != after[$0] })
        else { return nil }
        // Moving down shifts the rows between up by one, so the old row after `first` now sits at `first`.
        if first + 1 < before.count, after[first] == before[first + 1] {
            return (first, last)
        }
        return (last, first)
    }
}

// MARK: - Hosted rows

/// A numbered Daily Focus place with no open task: an empty slot or a deleted pick.
private struct SlotRow<Trailing: View>: View {
    let number: Int
    let text: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.focusNumber)
                .monospacedDigit()
                .foregroundStyle(Palette.muted.opacity(0.4))
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: 48)
    }
}

/// A task in Other tasks on one 40-point line: the date column, the title, and the ring.
private struct OtherTaskRow: View {
    let task: TaskItem
    let toggle: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var dateColumnWidth: CGFloat = 50

    var body: some View {
        let rowDate = TaskRowDate(for: task, at: Date())
        let isDone = task.status == .done
        let isMissed = Today.reason(for: task, at: Date()) == .missedScheduledDay
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let rowDate {
                    Text(rowDate.columnDay)
                        .font(.meta)
                    if let detail = rowDate.columnDetail {
                        Text(detail)
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
            .foregroundStyle(rowDate.map(color(for:)) ?? Palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: dateColumnWidth, alignment: .leading)
            .accessibilityLabel(rowDate?.text ?? "")

            Text(task.title)
                .lineLimit(1)
                .strikethrough(isDone, color: Palette.hairline)
                .foregroundStyle(isDone || isMissed ? Palette.muted : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing

            Button(action: toggle) {
                PriorityRing(color: task.priority?.color ?? Palette.low, isDone: isDone, diameter: 22)
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -11)
            .accessibilityLabel(isDone ? "Reopen" : "Complete")
        }
        .frame(minHeight: 40)
    }

    /// A subtask's parent, and a parent's subtask progress.
    private var trailing: some View {
        HStack(spacing: 8) {
            if task.isSubtask, let parentTitle = task.parent?.title {
                Label(parentTitle, systemImage: "arrow.turn.down.right")
                    .frame(maxWidth: 96, alignment: .trailing)
            }
            if task.hasSubtasks {
                let progress = task.subtaskProgress
                Label("\(progress.done)/\(progress.total)", systemImage: "checkmark")
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.meta)
        .foregroundStyle(Palette.muted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func color(for date: TaskRowDate) -> Color {
        guard date.kind == .deadline else { return Palette.muted }
        if task.isOverdue { return Palette.urgent }
        if task.isInActiveWindow { return Palette.high }
        return Palette.muted
    }
}
