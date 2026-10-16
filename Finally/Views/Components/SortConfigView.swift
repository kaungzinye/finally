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
                Group {
                    Section {
                        if sortStack.criteria.isEmpty {
                            Text("Tasks keep the order they came in.")
                                .font(.meta)
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(Array(sortStack.criteria.enumerated()), id: \.element.id) { index, criterion in
                                criterionRow(index: index, criterion: criterion)
                            }
                        }
                    } header: {
                        SectionLabel("Sort by")
                    }

                    if !availableFields.isEmpty {
                        Section {
                            ForEach(availableFields) { field in
                                Button {
                                    withAnimation {
                                        sortStack.criteria.append(SortCriterion(field: field))
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: field.icon)
                                            .foregroundStyle(Palette.muted)
                                            .frame(width: 20)
                                        Text(field.rawValue)
                                        Spacer()
                                        Image(systemName: "plus")
                                            .foregroundStyle(Palette.muted)
                                    }
                                    .foregroundStyle(Palette.ink)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            SectionLabel("Then by")
                        }
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .paperSheet()
    }

    private func criterionRow(index: Int, criterion: SortCriterion) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.meta.bold())
                .foregroundStyle(Palette.muted)
                .frame(width: 20)

            Image(systemName: criterion.field.icon)
                .foregroundStyle(Palette.muted)
                .frame(width: 20)

            Text(criterion.field.rawValue)
                .foregroundStyle(Palette.ink)

            Spacer()

            Button {
                sortStack.criteria[index].ascending.toggle()
            } label: {
                Image(systemName: criterion.ascending ? "arrow.up" : "arrow.down")
                    .font(.meta.bold())
                    .foregroundStyle(Palette.ink)
                    .frame(width: 30, height: 30)
                    .background(Palette.wash, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(criterion.ascending ? "Ascending" : "Descending")

            if index > 0 {
                Button {
                    sortStack.criteria.swapAt(index, index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move up")
            }

            Button {
                sortStack.criteria.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(criterion.field.rawValue)")
        }
    }
}
