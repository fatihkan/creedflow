import SwiftUI
import GRDB

struct DeployView: View {
    let appDatabase: AppDatabase?
    @State private var deployments: [Deployment] = []

    var body: some View {
        List {
            if deployments.isEmpty {
                ContentUnavailableView(
                    "No Deployments",
                    systemImage: "arrow.up.circle",
                    description: Text("Deployments will appear here after review approval")
                )
            } else {
                ForEach(deployments) { deployment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(deployment.version)
                                .font(.headline)
                            Spacer()
                            StatusBadge(status: deployment.status.rawValue)
                        }

                        HStack {
                            Text(deployment.environment.rawValue.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                            if let hash = deployment.commitHash {
                                Text(String(hash.prefix(7)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(deployment.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Deployments")
        .task { await loadDeployments() }
    }

    private func loadDeployments() async {
        guard let db = appDatabase else { return }
        do {
            deployments = try await db.dbQueue.read { db in
                try Deployment
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {}
    }
}
