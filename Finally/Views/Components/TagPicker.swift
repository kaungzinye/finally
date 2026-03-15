import SwiftUI
import SwiftData

struct TagPicker: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]

    @State private var query = ""

    private var availableTags: [String] {
        let allTags = tasks.flatMap(\.tags)
        return Array(Set(allTags)).sorted()
    }

    private var filteredTags: [String] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return availableTags
        }
        let lowercasedQuery = query.lowercased()
        return availableTags.filter { $0.lowercased().contains(lowercasedQuery) }
    }

    private var canCreateNewTag: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return !availableTags.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search or create tag", text: $query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }

                if canCreateNewTag {
                    Section {
                        Button {
                            let trimmed = query.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            if !selectedTags.contains(trimmed) {
                                selectedTags.append(trimmed)
                            }
                            query = ""
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Create tag \"\(query.trimmingCharacters(in: .whitespaces))\"")
                            }
                        }
                    }
                }

                Section("Available Tags") {
                    ForEach(filteredTags, id: \.self) { tag in
                        Button {
                            if selectedTags.contains(tag) {
                                selectedTags.removeAll { $0 == tag }
                            } else {
                                selectedTags.append(tag)
                            }
                        } label: {
                            HStack {
                                Text(tag)
                                Spacer()
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Start with an empty query so all tags show
                query = ""
            }
        }
        .presentationDetents([.medium, .large])
    }
}
