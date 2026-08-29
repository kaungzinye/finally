import SwiftUI
import SwiftData

struct SearchFilterView: View {
    @Query(sort: \TaskItem.deadline) private var allTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @State private var searchText = ""

    private var filteredTasks: [TaskItem] {
        guard !searchText.isEmpty else { return [] }
        return allTasks.filter { task in
            task.belongs(to: sessions.selectedProviderWorkspace) &&
                task.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredTasks, id: \.externalTaskID) { task in
                    TaskRowView(task: task)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search tasks...")
            .overlay {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Search Tasks",
                        systemImage: "magnifyingglass",
                        description: Text("Type to search by task name")
                    )
                } else if filteredTasks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }
}
