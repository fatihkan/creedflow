import SwiftUI
import GRDB

struct DeployView: View {
    let appDatabase: AppDatabase?
    @Binding var selectedDeploymentId: UUID?
    @State private var deployments: [Deployment] = []
    @State private var projectNames: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var showDeploySheet = false
    @State private var showCleanupConfirm = false
    @State private var isLoading = true
    @State private var filterEnvironment: Deployment.Environment?
    @State private var filterStatus: Deployment.Status?

    private var filteredDeployments: [Deployment] {
        deployments.filter { d in
            if let env = filterEnvironment, d.environment != env { return false }
            if let status = filterStatus, d.status != status { return false }
            return true
        }
    }

    /// Deployments eligible for cleanup (terminal states: success, failed, rolled_back)
    private var cleanableCount: Int {
        deployments.filter { $0.status == .success || $0.status == .failed || $0.status == .rolledBack }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Deployments") {
                HStack(spacing: 8) {
                    Picker("Environment", selection: $filterEnvironment) {
                        Text("All Envs").tag(nil as Deployment.Environment?)
                        ForEach(Deployment.Environment.allCases, id: \.self) { env in
                            Text(env.rawValue.capitalized).tag(env as Deployment.Environment?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)

                    Picker("Status", selection: $filterStatus) {
                        Text("All Status").tag(nil as Deployment.Status?)
                        ForEach(Deployment.Status.allCases, id: \.self) { status in
                            Text(status.rawValue.capitalized).tag(status as Deployment.Status?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)

                    if cleanableCount > 0 {
                        Button {
                            showCleanupConfirm = true
                        } label: {
                            Label("Clean Up", systemImage: "trash")
                        }
                        .help("Remove \(cleanableCount) completed, failed, and rolled-back deployments")
                    }

                    Button {
                        showDeploySheet = true
                    } label: {
                        Label("New Deployment", systemImage: "plus")
                    }
                }
            }
            Divider()

            if isLoading && deployments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredDeployments.isEmpty && errorMessage == nil {
                ForgeEmptyState(
                    icon: "arrow.up.circle",
                    title: "No Deployments",
                    subtitle: "Deployments will appear here after review approval",
                    actionTitle: "New Deployment",
                    action: { showDeploySheet = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let errorMessage {
                            ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                        }

                        ForEach(filteredDeployments) { deployment in
                            deploymentCard(deployment)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedDeploymentId = deployment.id
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedDeploymentId == deployment.id ? Color.forgeAmber : .clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showDeploySheet) {
            DeployTriggerSheet(appDatabase: appDatabase)
        }
        .confirmationDialog(
            "Clean Up Deployments",
            isPresented: $showCleanupConfirm
        ) {
            Button("Remove Completed, Failed & Rolled-back (\(cleanableCount))", role: .destructive) {
                cleanUpDeployments()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all completed, failed, and rolled-back deployment records. Active and pending deployments will not be affected.")
        }
        .task {
            await observeDeployments()
        }
    }

    private func deploymentCard(_ deployment: Deployment) -> some View {
        HStack(spacing: 12) {
            // Environment indicator
            VStack(spacing: 2) {
                Image(systemName: environmentIcon(deployment.environment))
                    .font(.caption)
                Text(deployment.environment.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(environmentColor(deployment.environment))
            .frame(width: 50)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    // Project name
                    if let name = projectNames[deployment.projectId] {
                        Text(name)
                            .font(.system(.subheadline, weight: .semibold))
                    }

                    Text(deployment.version)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let method = deployment.deployMethod {
                        Text(method.capitalized)
                            .forgeBadge(color: method == "docker" ? .forgeInfo : .forgeNeutral)
                    }

                    if let port = deployment.port {
                        Text(":\(port)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(deployment.status.rawValue.capitalized)
                        .forgeBadge(color: deployStatusColor(deployment.status))
                }

                HStack(spacing: 8) {
                    if let hash = deployment.commitHash {
                        Text(String(hash.prefix(7)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .help(hash)
                    }

                    Spacer()

                    // Runtime controls
                    if deployment.status == .success {
                        if let port = deployment.port {
                            Button {
                                if let url = URL(string: "http://localhost:\(port)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label("Open", systemImage: "globe")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                        }

                        Button {
                            stopDeployment(deployment)
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.forgeDanger)
                    }

                    // Cancel for pending/in-progress deployments
                    if deployment.status == .pending || deployment.status == .inProgress {
                        Button {
                            cancelDeployment(deployment)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.forgeDanger)
                    }

                    Text(deployment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .forgeCard(cornerRadius: 8)
    }

    private func stopDeployment(_ deployment: Deployment) {
        guard let db = appDatabase else { return }
        Task {
            let service = LocalDeploymentService(dbQueue: db.dbQueue)
            try? await service.stop(deployment: deployment)
        }
    }

    private func cancelDeployment(_ deployment: Deployment) {
        guard let db = appDatabase else { return }
        // For in_progress deployments, stop any running process first
        if deployment.status == .inProgress {
            Task {
                let service = LocalDeploymentService(dbQueue: db.dbQueue)
                try? await service.stop(deployment: deployment)
            }
        } else {
            // Pending — just mark as failed in DB
            try? db.dbQueue.write { dbConn in
                guard var d = try Deployment.fetchOne(dbConn, id: deployment.id) else { return }
                d.status = .failed
                d.completedAt = Date()
                d.logs = (d.logs ?? "") + "\nCancelled by user"
                try d.update(dbConn)
            }
        }
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

    private func cleanUpDeployments() {
        guard let db = appDatabase else { return }
        let terminalStatuses: [Deployment.Status] = [.success, .failed, .rolledBack]
        try? db.dbQueue.write { dbConn in
            let idsToDelete = deployments
                .filter { terminalStatuses.contains($0.status) }
                .map(\.id)
            guard !idsToDelete.isEmpty else { return }
            try Deployment
                .filter(idsToDelete.contains(Column("id")))
                .deleteAll(dbConn)
        }
    }

    private func observeDeployments() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db -> ([Deployment], [UUID: String]) in
            let deps = try Deployment
                .order(Column("createdAt").desc)
                .fetchAll(db)
            // Fetch project names for all referenced project IDs
            let projectIds = Set(deps.map(\.projectId))
            var names: [UUID: String] = [:]
            if !projectIds.isEmpty {
                let projects = try Project
                    .filter(projectIds.contains(Column("id")))
                    .fetchAll(db)
                for project in projects {
                    names[project.id] = project.name
                }
            }
            return (deps, names)
        }
        do {
            for try await (deps, names) in observation.values(in: db.dbQueue) {
                deployments = deps
                projectNames = names
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Deploy Trigger Sheet

private struct DeployTriggerSheet: View {
    let appDatabase: AppDatabase?
    @Environment(\.dismiss) private var dismiss

    @State private var projects: [Project] = []
    @State private var selectedProjectId: UUID?
    @State private var environment: Deployment.Environment = .staging
    @State private var deployMethod: String = "auto"
    @State private var version = ""
    @State private var branch = "staging"
    @State private var portText = "3001"
    @State private var showProductionConfirm = false
    @State private var errorMessage: String?

    private var port: Int {
        Int(portText) ?? 3001
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button { self.errorMessage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(.red.opacity(0.1))
            }

            Form {
                Section("Project") {
                    Picker("Project", selection: $selectedProjectId) {
                        Text("Select a project").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }

                Section("Configuration") {
                    Picker("Environment", selection: $environment) {
                        ForEach(Deployment.Environment.allCases, id: \.self) { env in
                            Text(env.rawValue.capitalized).tag(env)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: environment) { _, newValue in
                        switch newValue {
                        case .development:
                            portText = "3002"
                            branch = "dev"
                        case .staging:
                            portText = "3001"
                            branch = "staging"
                        case .production:
                            portText = "3000"
                            branch = "main"
                        }
                    }

                    Picker("Deploy Method", selection: $deployMethod) {
                        Text("Auto-detect").tag("auto")
                        Label("Docker", systemImage: "shippingbox").tag("docker")
                        Label("Docker Compose", systemImage: "square.stack.3d.up").tag("docker-compose")
                        Label("Direct Process", systemImage: "terminal").tag("direct")
                    }

                    TextField("Version (e.g. v1.0.0)", text: $version)
                        .textFieldStyle(.roundedBorder)

                    TextField("Branch", text: $branch)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Port")
                        TextField("Port", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if environment == .production {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Button("Deploy") {
                    if environment == .production {
                        showProductionConfirm = true
                    } else {
                        triggerDeploy()
                    }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedProjectId == nil || version.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 420)
        .task {
            await loadProjects()
        }
        .confirmationDialog("Production Deployment", isPresented: $showProductionConfirm) {
            Button("Deploy to Production", role: .destructive) {
                triggerDeploy()
            }
        } message: {
            Text("You are deploying \(version) to PRODUCTION. This will affect live users. Are you sure?")
        }
    }

    private func loadProjects() async {
        guard let db = appDatabase else { return }
        projects = (try? await db.dbQueue.read { db in
            try Project.order(Column("name").asc).fetchAll(db)
        }) ?? []
    }

    private func triggerDeploy() {
        guard let db = appDatabase, let projectId = selectedProjectId else {
            errorMessage = "Database not available"
            return
        }
        do {
            try db.dbQueue.write { dbConn in
                // Create deployment record with port and method
                let method = deployMethod == "auto" ? nil : deployMethod
                let deployment = Deployment(
                    projectId: projectId,
                    environment: environment,
                    version: version,
                    commitHash: nil,
                    deployedBy: "user",
                    deployMethod: method,
                    port: port
                )
                try deployment.insert(dbConn)

                // Create a devops agent task for deployment
                let methodDesc = method ?? "auto-detect"
                let task = AgentTask(
                    projectId: projectId,
                    agentType: .devops,
                    title: "Deploy \(version) to \(environment.rawValue)",
                    description: "Deploy version \(version) from branch \(branch) to \(environment.rawValue) environment. Method: \(methodDesc). Port: \(port)",
                    priority: 10
                )
                try task.insert(dbConn)
            }
            dismiss()
        } catch {
            errorMessage = "Deploy failed: \(error.localizedDescription)"
        }
    }
}
