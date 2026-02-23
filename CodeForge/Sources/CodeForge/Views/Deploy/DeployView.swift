import SwiftUI
import GRDB

struct DeployView: View {
    let appDatabase: AppDatabase?
    @State private var deployments: [Deployment] = []
    @State private var errorMessage: String?
    @State private var showDeploySheet = false
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
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showDeploySheet) {
            DeployTriggerSheet(appDatabase: appDatabase)
        }
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
    @State private var version = ""
    @State private var branch = "main"
    @State private var showProductionConfirm = false

    var body: some View {
        VStack(spacing: 0) {
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

                    TextField("Version (e.g. v1.0.0)", text: $version)
                        .textFieldStyle(.roundedBorder)

                    TextField("Branch", text: $branch)
                        .textFieldStyle(.roundedBorder)
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
        .frame(width: 420, height: 340)
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
        guard let db = appDatabase, let projectId = selectedProjectId else { return }
        try? db.dbQueue.write { dbConn in
            // Create deployment record
            var deployment = Deployment(
                projectId: projectId,
                environment: environment,
                version: version,
                commitHash: nil,
                deployedBy: "user"
            )
            try deployment.insert(dbConn)

            // Create a devops agent task for deployment
            var task = AgentTask(
                projectId: projectId,
                agentType: .devops,
                title: "Deploy \(version) to \(environment.rawValue)",
                description: "Deploy version \(version) from branch \(branch) to \(environment.rawValue) environment.",
                priority: 10
            )
            try task.insert(dbConn)
        }
        dismiss()
    }
}
