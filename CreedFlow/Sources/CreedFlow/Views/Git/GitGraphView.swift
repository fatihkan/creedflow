import SwiftUI
import GRDB

struct GitGraphView: View {
    let appDatabase: AppDatabase?

    @State private var projects: [Project] = []
    @State private var selectedProjectId: UUID?
    @State private var graphData: GitGraphData = .empty
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedBranch: String = "All"

    private let gitService = GitService()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if selectedProjectId == nil {
                ForgeEmptyState(
                    icon: "arrow.triangle.branch",
                    title: "Git History",
                    subtitle: "Select a project to view its git history"
                )
            } else if isLoading {
                ProgressView("Loading git history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ForgeEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Git Error",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await loadGraph() }
                }
            } else if graphData.rows.isEmpty {
                ForgeEmptyState(
                    icon: "arrow.triangle.branch",
                    title: "No Git History",
                    subtitle: "This project has no git commits yet"
                )
            } else {
                GitGraphContentView(
                    graphData: filteredGraphData,
                    maxColumns: graphData.maxColumns
                )
            }
        }
        .task {
            await observeProjects()
        }
        .onChange(of: selectedProjectId) { _, _ in
            Task { await loadGraph() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ForgeToolbar(title: "Git History") {
            Picker("Project", selection: $selectedProjectId) {
                Text("Select Project").tag(UUID?.none)
                ForEach(projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
            .frame(maxWidth: 200)

            if !graphData.allBranches.isEmpty {
                Picker("Branch", selection: $selectedBranch) {
                    Text("All").tag("All")
                    Divider()
                    ForEach(graphData.allBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            Button {
                Task { await loadGraph() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(selectedProjectId == nil)
        }
    }

    // MARK: - Filtered Data

    private var filteredGraphData: GitGraphData {
        guard selectedBranch != "All" else { return graphData }

        let filtered = graphData.rows.filter { row in
            row.commit.decorations.contains(where: { $0.name == selectedBranch })
        }

        if filtered.isEmpty { return graphData }

        return GitGraphData(
            rows: filtered,
            currentBranch: graphData.currentBranch,
            maxColumns: graphData.maxColumns,
            allBranches: graphData.allBranches
        )
    }

    // MARK: - Data Loading

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Project.order(Column("name")).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                projects = value
            }
        } catch { /* observation error */ }
    }

    private func loadGraph() async {
        guard let projectId = selectedProjectId else {
            graphData = .empty
            return
        }

        isLoading = true
        errorMessage = nil
        selectedBranch = "All"

        guard let db = appDatabase else {
            errorMessage = "Database not available"
            isLoading = false
            return
        }

        do {
            let project = try await db.dbQueue.read { dbConn in
                try Project.fetchOne(dbConn, key: projectId)
            }

            guard let project, !project.directoryPath.isEmpty else {
                errorMessage = "Project has no directory configured"
                isLoading = false
                return
            }

            let logOutput = try await gitService.structuredLog(count: 200, in: project.directoryPath)
            let commits = GitLogParser.parseLog(logOutput)
            let layoutData = GitGraphLayoutEngine.layout(commits: commits)
            graphData = layoutData
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
