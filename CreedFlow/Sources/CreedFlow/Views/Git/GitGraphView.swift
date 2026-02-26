import SwiftUI
import GRDB

struct GitGraphView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?

    @State private var graphData: GitGraphData = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedBranch: String = "All"

    private let gitService = GitService()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if isLoading {
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
        .task(id: projectId) {
            await loadGraph()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ForgeToolbar(title: "Git History") {
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
        }
    }

    // MARK: - Filtered Data

    private var filteredGraphData: GitGraphData {
        guard selectedBranch != "All" else { return graphData }

        // Filter to show only commits that have the selected branch decoration
        // or are ancestors visible in the graph
        let filtered = graphData.rows.filter { row in
            row.commit.decorations.contains(where: { $0.name == selectedBranch })
        }

        // If filter yields nothing, show all (branch may be on older commits)
        if filtered.isEmpty { return graphData }

        return GitGraphData(
            rows: filtered,
            currentBranch: graphData.currentBranch,
            maxColumns: graphData.maxColumns,
            allBranches: graphData.allBranches
        )
    }

    // MARK: - Data Loading

    private func loadGraph() async {
        isLoading = true
        errorMessage = nil

        guard let db = appDatabase else {
            errorMessage = "Database not available"
            isLoading = false
            return
        }

        // Fetch project directory path
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
