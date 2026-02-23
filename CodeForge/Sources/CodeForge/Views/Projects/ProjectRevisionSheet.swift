import SwiftUI
import GRDB

struct ProjectRevisionSheet: View {
    let project: Project
    let features: [Feature]
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?
    @Environment(\.dismiss) private var dismiss
    @State private var newRequirements = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showPromptPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Features")
                        .font(.title3.bold())
                    Text("Add new requirements to \(project.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Form
            Form {
                // Existing features summary
                if !features.isEmpty {
                    Section("Existing Features") {
                        ForEach(features) { feature in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.forgeSuccess)
                                    .font(.caption)
                                Text(feature.name)
                                    .font(.subheadline)
                                Spacer()
                                Text(feature.status.rawValue)
                                    .forgeBadge(color: featureStatusColor(feature.status))
                            }
                        }
                    }
                }

                // New requirements
                Section {
                    HStack {
                        Text("New Requirements")
                        Spacer()
                        Button {
                            showPromptPicker = true
                        } label: {
                            Label("Use Prompt", systemImage: "text.book.closed")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    TextEditor(text: $newRequirements)
                        .frame(minHeight: 120)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Describe the new features you want to add. The analyzer will create only new tasks without duplicating existing ones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    ForgeErrorBanner(message: error, onDismiss: { errorMessage = nil })
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                }
                Button("Analyze New Features") {
                    Task { await submitRevision() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeAmber)
                .disabled(newRequirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 550, height: 560)
        .sheet(isPresented: $showPromptPicker) {
            PromptPickerSheet(appDatabase: appDatabase) { prompt in
                newRequirements = prompt.content
            }
        }
    }

    private func submitRevision() async {
        isSubmitting = true
        defer { isSubmitting = false }

        guard let db = appDatabase else {
            errorMessage = "Database not available"
            return
        }

        let existingFeatureNames = features.map { $0.name }.joined(separator: ", ")
        let revisionDescription = "[ProjectType: \(project.projectType.rawValue)] [REVISION] Existing features: \(existingFeatureNames). NEW REQUIREMENTS: \(newRequirements)"

        do {
            try await db.dbQueue.write { dbConn in
                var task = AgentTask(
                    projectId: project.id,
                    agentType: .analyzer,
                    title: "Revision: \(project.name)",
                    description: revisionDescription,
                    priority: 10
                )
                try task.insert(dbConn)
            }

            if let orchestrator, !orchestrator.isRunning {
                await orchestrator.start()
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func featureStatusColor(_ status: Feature.Status) -> Color {
        switch status {
        case .pending: return .forgeNeutral
        case .inProgress: return .forgeInfo
        case .completed: return .forgeSuccess
        case .failed: return .forgeDanger
        }
    }
}
