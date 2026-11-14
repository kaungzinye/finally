import SwiftData
import UIKit

/// Owns the collection view that draws Today: the Daily Focus picks, then Other tasks.
///
/// Three UIKit pieces work together here:
/// - The **layout** decides where every row goes. A list layout stacks rows full width in
///   rounded groups, the same look as SwiftUI's inset grouped `List`.
/// - The **data source** decides which rows exist. It takes a snapshot, a list of sections and
///   the row IDs in each, and animates the difference from the snapshot before it.
/// - A **cell registration** decides what one kind of row looks like. The collection view reuses
///   cells as they scroll off screen, so a registration fills a recycled cell for a given row.
final class TodayListController: UIViewController {
    enum Section {
        case focus
        case otherTasks
    }

    /// One row on Today. Each case carries only what identifies the row, so the data source can
    /// tell a changed row from a new one. The content behind it lives in the lookups below.
    enum Row: Hashable {
        /// A Daily Focus pick, open, done, or with its task deleted.
        case pick(DailyFocusPick)
        /// An open place in Daily Focus, by its number.
        case emptySlot(Int)
        /// A task in Other tasks.
        case otherTask(PersistentIdentifier)
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

    /// The content behind the current snapshot, read when a cell or header is filled.
    private var content = TodayListContent(focusHeading: "", focus: nil, otherTasks: [])
    private var picks: [DailyFocusPick: DailyFocusList.Row] = [:]
    private var otherTasks: [PersistentIdentifier: TaskItem] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: Self.makeLayout())
        // The collection view fills the controller's view and follows its size.
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
        dataSource = makeDataSource()
    }

    /// Replaces what the list shows. Called by SwiftUI on every update, so it stays cheap: it
    /// builds a snapshot of rows and lets the data source find the difference.
    func show(_ content: TodayListContent) {
        self.content = content
        picks = Dictionary((content.focus?.rows ?? []).map { ($0.pick, $0) }, uniquingKeysWith: { first, _ in first })
        otherTasks = Dictionary(content.otherTasks.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.focus])
        if let focus = content.focus {
            snapshot.appendItems(focus.rows.map { .pick($0.pick) }, toSection: .focus)
            snapshot.appendItems(focus.emptySlotNumbers.map { .emptySlot($0) }, toSection: .focus)
        }
        // A section with no rows would still draw its header, so Other tasks appears only with tasks.
        if !content.otherTasks.isEmpty {
            snapshot.appendSections([.otherTasks])
            snapshot.appendItems(content.otherTasks.map { .otherTask($0.persistentModelID) }, toSection: .otherTasks)
        }
        // A row keeps its identity when its task changes, so the snapshot alone can't see a new
        // title or a finished pick. Reconfiguring reruns the cell registrations for the rows on
        // screen, and leaves rows off screen for when they scroll in.
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        // The first snapshot appears at once. Later ones animate their inserts and deletes.
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        refreshHeaders()
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
        var content = UIListContentConfiguration.groupedHeader()
        switch section {
        case .focus:
            content.text = self.content.focusHeading
            content.secondaryText = self.content.focus?.status
        case .otherTasks:
            content.text = "Other tasks"
            content.secondaryText = "\(self.content.otherTasks.count)"
        }
        content.prefersSideBySideTextAndSecondaryText = true
        content.textProperties.color = UIColor(Palette.ink)
        content.secondaryTextProperties.color = UIColor(Palette.muted)
        header.contentConfiguration = content
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        list.backgroundColor = UIColor(Palette.paper)
        // Each section asks for a header view, which the header registration fills.
        list.headerMode = .supplementary
        return UICollectionViewCompositionalLayout.list(using: list)
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Row> {
        // One registration per kind of row. Each one's second type is what it's filled from.
        let pickCell = UICollectionView.CellRegistration<UICollectionViewListCell, DailyFocusPick> { [weak self] cell, _, pick in
            guard let row = self?.picks[pick] else { return }
            cell.contentConfiguration = Self.pickContent(row, in: cell)
            cell.backgroundConfiguration = Self.cardBackground()
        }
        let emptySlotCell = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, number in
            var content = cell.defaultContentConfiguration()
            content.attributedText = Self.numbered(number, "Pick a task", numberColor: UIColor(Palette.muted).withAlphaComponent(0.4), textColor: UIColor(Palette.muted))
            cell.contentConfiguration = content
            cell.backgroundConfiguration = Self.cardBackground()
        }
        let otherTaskCell = UICollectionView.CellRegistration<UICollectionViewListCell, PersistentIdentifier> { [weak self] cell, _, id in
            guard let task = self?.otherTasks[id] else { return }
            var content = UIListContentConfiguration.valueCell()
            content.text = task.title
            content.textProperties.color = UIColor(Palette.ink)
            content.secondaryText = TaskRowDate(for: task, at: Date())?.text
            content.secondaryTextProperties.color = UIColor(Palette.muted)
            cell.contentConfiguration = content
            cell.backgroundConfiguration = Self.cardBackground()
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, row in
            // The cell provider picks the registration that matches the row's kind.
            switch row {
            case .pick(let pick):
                collectionView.dequeueConfiguredReusableCell(using: pickCell, for: indexPath, item: pick)
            case .emptySlot(let number):
                collectionView.dequeueConfiguredReusableCell(using: emptySlotCell, for: indexPath, item: number)
            case .otherTask(let id):
                collectionView.dequeueConfiguredReusableCell(using: otherTaskCell, for: indexPath, item: id)
            }
        }

        // A header is a supplementary view: it belongs to a section rather than to a row.
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            self?.fillHeader(header, at: indexPath)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return dataSource
    }

    /// A pick reads "1  Title" over its deadline and project. The first open pick's number is
    /// orange, and a finished pick is muted and struck through.
    private static func pickContent(_ row: DailyFocusList.Row, in cell: UICollectionViewListCell) -> UIListContentConfiguration {
        var content = cell.defaultContentConfiguration()
        let numberColor = row.isNext ? UIColor(Palette.high) : UIColor(Palette.muted)
        guard let task = row.task else {
            content.attributedText = numbered(row.number, "Deleted", numberColor: numberColor, textColor: UIColor(Palette.muted))
            return content
        }
        let titleColor = row.isDone ? UIColor(Palette.muted) : UIColor(Palette.ink)
        content.attributedText = numbered(row.number, task.title, numberColor: numberColor, textColor: titleColor, struck: row.isDone)
        if !row.isDone {
            content.secondaryText = TaskRowDate.FocusMeta(for: task, project: task.project?.title, at: Date())?.text
            content.secondaryTextProperties.color = UIColor(Palette.muted)
        }
        return content
    }

    private static func numbered(_ number: Int, _ text: String, numberColor: UIColor, textColor: UIColor, struck: Bool = false) -> NSAttributedString {
        let line = NSMutableAttributedString(string: "\(number)   ", attributes: [
            .foregroundColor: numberColor,
            .font: UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .heavy),
        ])
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: textColor, .font: UIFont.preferredFont(forTextStyle: .body)]
        if struck { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        line.append(NSAttributedString(string: text, attributes: attributes))
        return line
    }

    private static func cardBackground() -> UIBackgroundConfiguration {
        var background: UIBackgroundConfiguration
        if #available(iOS 18, *) {
            background = .listCell()
        } else {
            background = .listGroupedCell()
        }
        background.backgroundColor = UIColor(Palette.card)
        return background
    }
}
