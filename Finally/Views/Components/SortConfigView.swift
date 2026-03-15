import SwiftUI

struct SortConfigView: View {
    @Binding var sortStack: SortStack
    @Environment(\.dismiss) private var dismiss

    private var availableFields: [SortField] {
        let usedFields = Set(sortStack.criteria.map(\.field))
        return SortField.allCases.filter { !usedFields.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Sort Order") {
                    if sortStack.criteria.isEmpty {
                        Text("No sort criteria — tasks shown in default order")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(Array(sortStack.criteria.enumerated()), id: \.element.id) { index, criterion in
                            HStack(spacing: 12) {
                                // Position number
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                Image(systemName: criterion.field.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                Text(criterion.field.rawValue)

                                Spacer()

                                // Asc/Desc toggle
                                Button {
                                    sortStack.criteria[index].ascending.toggle()
                                } label: {
                                    Image(systemName: criterion.ascending ? "arrow.up" : "arrow.down")
                                        .font(.caption.bold())
                                        .foregroundStyle(.blue)
                                        .padding(6)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)

                                // Move up
                                if index > 0 {
                                    Button {
                                        sortStack.criteria.swapAt(index, index - 1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Remove
                                Button {
                                    sortStack.criteria.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !availableFields.isEmpty {
                    Section("Add Sort") {
                        ForEach(availableFields) { field in
                            Button {
                                withAnimation {
                                    sortStack.criteria.append(SortCriterion(field: field))
                                }
                            } label: {
                                HStack {
                                    Image(systemName: field.icon)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    Text(field.rawValue)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
