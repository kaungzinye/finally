import SwiftUI

struct SchemaErrorView: View {
    let issues: [ValidationResult.Issue]
    var onRetry: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Schema Issues Found", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("Your Notion database is missing some required properties. Please add them in Notion and try again.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Required Changes") {
                    ForEach(issues, id: \.propertyName) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(issue.propertyName)
                                    .fontWeight(.semibold)
                                Text("(\(issue.expectedType))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(issue.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Button {
                        onRetry()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Re-validate")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Setup Required")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
