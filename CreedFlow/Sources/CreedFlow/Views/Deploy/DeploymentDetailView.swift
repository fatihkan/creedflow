import SwiftUI
import GRDB

struct DeploymentDetailView: View {
    let deploymentId: UUID
    let appDatabase: AppDatabase?
    var onDismiss: (() -> Void)?

    @State private var deployment: Deployment?
    @State private var projectName: String?
    @State private var errorMessage: String?
    @State private var showLogs = true
    @State private var showCancelConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header (outside ScrollView)
            if let deployment {
                headerBar(deployment)
                Divider()
            }

            ScrollView {
                if let deployment {
                    VStack(alignment: .leading, spacing: 12) {
                        metadataGrid(deployment)
                        logsSection(deployment)
                        actionsSection(deployment)

                        if let errorMessage {
                            ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                        }
                    }
                    .padding(16)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: deploymentId) {
            await observeDeployment()
        }
        .confirmationDialog("Cancel Deployment", isPresented: $showCancelConfirm) {
            Button("Cancel Deployment", role: .destructive) {
                cancelDeployment()
            }
        } message: {
            Text("This will stop the running deployment. This cannot be undone.")
        }
    }

    // MARK: - Header

    private func headerBar(_ deployment: Deployment) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: environmentIcon(deployment.environment))
                Text(deployment.environment.rawValue.capitalized)
            }
            .forgeBadge(color: environmentColor(deployment.environment))

            Text(deployment.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                .forgeBadge(color: statusColor(deployment.status))

            Text(deployment.version)
                .font(.headline)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Close detail panel")
                .help("Close (Esc)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background)
    }

    // MARK: - Metadata Grid

    private func metadataGrid(_ deployment: Deployment) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            if let name = projectName {
                metadataItem(label: "Project", value: name, icon: "folder")
            }

            if let method = deployment.deployMethod {
                metadataItem(label: "Method", value: method.capitalized, icon: "shippingbox")
            }

            if let port = deployment.port {
                metadataItem(label: "Port", value: ":\(port)", icon: "network")
            }

            if let containerId = deployment.containerId {
                metadataItem(label: "Container", value: String(containerId.prefix(12)), icon: "cube")
            }

            if let processId = deployment.processId {
                metadataItem(label: "PID", value: "\(processId)", icon: "terminal")
            }

            if let hash = deployment.commitHash {
                metadataItem(label: "Commit", value: String(hash.prefix(7)), icon: "number")
            }

            metadataItem(label: "Deployed by", value: deployment.deployedBy, icon: "person")

            metadataItem(label: "Created", value: relativeDate(deployment.createdAt), icon: "clock")

            if let completedAt = deployment.completedAt {
                metadataItem(label: "Completed", value: relativeDate(completedAt), icon: "checkmark.circle")
            }

            if let completedAt = deployment.completedAt {
                let duration = completedAt.timeIntervalSince(deployment.createdAt)
                if duration > 0 {
                    metadataItem(label: "Duration", value: formatDuration(duration), icon: "timer")
                }
            }

            if deployment.autoFixAttempts > 0 {
                metadataItem(label: "Auto-fix", value: "\(deployment.autoFixAttempts) attempt(s)", icon: "wrench")
            }

            if let fixTaskId = deployment.fixTaskId {
                metadataItem(label: "Fix Task", value: String(fixTaskId.uuidString.prefix(8)), icon: "arrow.triangle.branch")
            }
        }
    }

    // MARK: - Logs

    private func logsSection(_ deployment: Deployment) -> some View {
        DisclosureGroup("Deployment Logs", isExpanded: $showLogs) {
            if let logs = deployment.logs, !logs.isEmpty {
                ScrollView {
                    Text(logs)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.forgeTerminalText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 150, maxHeight: 300)
                .background(Color.forgeTerminalBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("No logs available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .font(.subheadline.bold())
    }

    // MARK: - Actions

    private func actionsSection(_ deployment: Deployment) -> some View {
        HStack(spacing: 8) {
            if deployment.status == .success, let port = deployment.port {
                Button {
                    if let url = URL(string: "http://localhost:\(port)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeInfo)
            }

            if deployment.status == .success {
                Button(role: .destructive) {
                    stopDeployment(deployment)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }

            if deployment.status == .pending || deployment.status == .inProgress {
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Metadata Item

    private func metadataItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func environmentIcon(_ env: Deployment.Environment) -> String {
        switch env {
        case .development: return "hammer"
        case .staging: return "flask"
        case .production: return "globe"
        }
    }

    private func environmentColor(_ env: Deployment.Environment) -> Color {
        switch env {
        case .development: return .forgeNeutral
        case .staging: return .forgeInfo
        case .production: return .forgeDanger
        }
    }

    private func statusColor(_ status: Deployment.Status) -> Color {
        switch status {
        case .pending: return .forgeNeutral
        case .inProgress: return .forgeInfo
        case .success: return .forgeSuccess
        case .failed: return .forgeDanger
        case .rolledBack: return .forgeWarning
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes < 60 { return "\(minutes)m \(secs)s" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    // MARK: - Actions

    private func stopDeployment(_ deployment: Deployment) {
        guard let db = appDatabase else { return }
        Task {
            let service = LocalDeploymentService(dbQueue: db.dbQueue)
            try? await service.stop(deployment: deployment)
        }
    }

    private func cancelDeployment() {
        guard let db = appDatabase, let deployment else { return }
        if deployment.status == .inProgress {
            Task {
                let service = LocalDeploymentService(dbQueue: db.dbQueue)
                try? await service.stop(deployment: deployment)
            }
        } else {
            try? db.dbQueue.write { dbConn in
                guard var d = try Deployment.fetchOne(dbConn, id: deployment.id) else { return }
                d.status = .failed
                d.completedAt = Date()
                d.logs = (d.logs ?? "") + "\nCancelled by user"
                try d.update(dbConn)
            }
        }
    }

    // MARK: - Observation

    private func observeDeployment() async {
        guard let db = appDatabase else { return }
        let did = deploymentId
        let observation = ValueObservation.tracking { db -> (Deployment?, String?) in
            let deployment = try Deployment.fetchOne(db, id: did)
            var name: String?
            if let projectId = deployment?.projectId {
                name = try Project.fetchOne(db, id: projectId)?.name
            }
            return (deployment, name)
        }
        do {
            for try await (d, name) in observation.values(in: db.dbQueue) {
                deployment = d
                projectName = name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
