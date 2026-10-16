import SwiftUI

struct PriorityPicker: View {
    @Binding var selection: TaskPriority?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CheckRow(isSelected: selection == nil, action: { choose(nil) }) {
                        PriorityRing(color: Palette.low, isDone: false)
                        Text("No priority")
                    }

                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        CheckRow(isSelected: selection == priority, action: { choose(priority) }) {
                            PriorityRing(color: priority.color, isDone: false)
                            Text(priority.rawValue)
                        }
                    }
                }
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Priority")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .paperSheet()
    }

    private func choose(_ priority: TaskPriority?) {
        selection = priority
        dismiss()
    }
}
