import SwiftUI
import SwiftData

struct SearchFilterView: View {
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }, sort: \TaskItem.deadline)
    private var allTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var selectedTask: TaskItem?

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
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
                }
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Search")
            .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search tasks")
            .onAppear { isSearching = true }
            .overlay {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Search tasks",
                        systemImage: "magnifyingglass",
                        description: Text("Type part of a task's name.")
                    )
                } else if filteredTasks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.fraction(0.8)])
            }
        }
        .paperSheet()
    }
}
