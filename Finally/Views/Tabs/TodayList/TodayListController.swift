import SwiftData
import UIKit

/// Owns the collection view that draws Today: the Daily Focus picks, then Other tasks.
///
/// Three UIKit pieces work together here:
/// - The **layout** decides where every row goes. A list layout stacks rows full width in
///   rounded groups, the same look as SwiftUI's inset grouped `List`.
/// - The **data source** decides which rows exist. It takes a snapshot, a list of sections and
///   the row IDs in each, and animates the difference from the snapshot before it.
/// - The **cell registration** decides what one row looks like. The collection view reuses cells
///   as they scroll off screen, so the registration fills a recycled cell for a given row ID.
final class TodayListController: UIViewController {
    enum Section {
        case focus
        case otherTasks
    }

    /// A row is identified by its task's ID, never by the task itself. The data source compares
    /// IDs between snapshots to work out what was inserted, deleted, or moved.
    typealias RowID = PersistentIdentifier

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, RowID>!
    /// The tasks behind the current snapshot, looked up by ID when a cell is filled.
    private var tasks: [RowID: TaskItem] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: Self.makeLayout())
        // The collection view fills the controller's view and follows its size.
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
        dataSource = makeDataSource()
    }

    /// Replaces what the list shows. Called by SwiftUI on every update, so it stays cheap: it
    /// builds a snapshot of IDs and lets the data source find the difference.
    func show(picks: [TaskItem], otherTasks: [TaskItem]) {
        tasks = Dictionary((picks + otherTasks).map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })

        var snapshot = NSDiffableDataSourceSnapshot<Section, RowID>()
        snapshot.appendSections([.focus, .otherTasks])
        snapshot.appendItems(picks.map(\.persistentModelID), toSection: .focus)
        snapshot.appendItems(otherTasks.map(\.persistentModelID), toSection: .otherTasks)
        // The first snapshot appears at once. Later ones animate their inserts and deletes.
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        list.backgroundColor = UIColor(Palette.paper)
        return UICollectionViewCompositionalLayout.list(using: list)
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, RowID> {
        let taskCell = UICollectionView.CellRegistration<UICollectionViewListCell, RowID> { [weak self] cell, _, id in
            var content = cell.defaultContentConfiguration()
            content.text = self?.tasks[id]?.title
            content.textProperties.color = UIColor(Palette.ink)
            cell.contentConfiguration = content
            cell.backgroundConfiguration = Self.cardBackground()
        }
        return UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: taskCell, for: indexPath, item: id)
        }
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
