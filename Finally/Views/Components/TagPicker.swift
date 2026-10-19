import SwiftUI
import SwiftData

struct TagPicker: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [UserSession]

    @State private var query = ""

    private var availableTags: [String] {
        let allTags = tasks.scoped(to: sessions.selectedProviderWorkspace).flatMap(\.tags)
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
                Group {
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Palette.muted)
                            TextField("Find or add a tag", text: $query)
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
                                Label("Add \"\(query.trimmingCharacters(in: .whitespaces))\"", systemImage: "plus")
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }

                    Section {
                        ForEach(filteredTags, id: \.self) { tag in
                            CheckRow(isSelected: selectedTags.contains(tag), action: { toggle(tag) }) {
                                Text(tag)
                            }
                        }
                    } header: {
                        if !filteredTags.isEmpty {
                            SectionLabel("Your tags")
                        }
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .paperSheet()
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.removeAll { $0 == tag }
        } else {
            selectedTags.append(tag)
        }
    }
}
