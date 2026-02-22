import SwiftUI
import GRDB

struct DeployView: View {
    let appDatabase: AppDatabase?
    @State private var deployments: [Deployment] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if deployments.isEmpty && errorMessage == nil {
                ForgeEmptyState(
                    icon: "arrow.up.circle",
                    title: "No Deployments",
                    subtitle: "Deployments will appear here after review approval"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let errorMessage {
                            ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                        }

                        ForEach(deployments) { deployment in
                            deploymentCard(deployment)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Deployments")
        .task {
            await observeDeployments()
        }
    }

    private func deploymentCard(_ deployment: Deployment) -> some View {
        HStack(spacing: 12) {
            // Environment indicator
            VStack(spacing: 2) {
                Image(systemName: deployment.environment == .production ? "globe" : "flask")
                    .font(.caption)
                Text(deployment.environment.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(deployment.environment == .production ? Color.forgeDanger : .forgeInfo)
            .frame(width: 50)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(deployment.version)
                        .font(.system(.subheadline, weight: .semibold))
                    Spacer()
                    Text(deployment.status.rawValue.capitalized)
                        .forgeBadge(color: deployStatusColor(deployment.status))
                }

                HStack(spacing: 8) {
                    if let hash = deployment.commitHash {
                        Text(String(hash.prefix(7)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(deployment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .forgeCard(cornerRadius: 8)
    }

    private func deployStatusColor(_ status: Deployment.Status) -> Color {
        switch status {
        case .pending: return .forgeNeutral
        case .inProgress: return .forgeInfo
        case .success: return .forgeSuccess
        case .failed: return .forgeDanger
        case .rolledBack: return .forgeWarning
        }
    }

    private func observeDeployments() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Deployment
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                deployments = value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
