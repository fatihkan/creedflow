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
    @State private var searchText: String = ""
    @State private var selectedCommit: GitCommit?

    private let gitService = GitService()

    var body: some View {
        HStack(spacing: 0) {
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
                } else if searchFilteredGraphData.rows.isEmpty {
                    ForgeEmptyState(
                        icon: "arrow.triangle.branch",
                        title: searchText.isEmpty ? "No Git History" : "No Matching Commits",
                        subtitle: searchText.isEmpty ? "This project has no git commits yet" : "No commits match \"\(searchText)\""
                    )
                } else {
                    GitGraphContentView(
                        graphData: searchFilteredGraphData,
                        maxColumns: graphData.maxColumns,
                        selectedCommitId: selectedCommit?.id,
                        onSelectCommit: { commit in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCommit = selectedCommit?.id == commit.id ? nil : commit
                            }
                        }
                    )
                }
            }

            // Commit detail panel
            if let commit = selectedCommit {
                Divider()
                GitCommitDetailView(
                    commit: commit,
                    onDismiss: { withAnimation(.easeInOut(duration: 0.15)) { selectedCommit = nil } }
                )
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .task {
            await observeProjects()
        }
        .onChange(of: selectedProjectId) { _, _ in
            selectedCommit = nil
            Task { await loadGraph() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ForgeToolbar(title: "Git History") {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Search commits...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .frame(width: 180)

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
            .accessibilityLabel("Refresh git history")
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

    private var searchFilteredGraphData: GitGraphData {
        let branchFiltered = filteredGraphData
        guard !searchText.isEmpty else { return branchFiltered }

        let query = searchText.lowercased()
        let filtered = branchFiltered.rows.filter { row in
            row.commit.message.lowercased().contains(query)
            || row.commit.id.lowercased().contains(query)
            || row.commit.shortHash.lowercased().contains(query)
            || row.commit.author.lowercased().contains(query)
        }

        return GitGraphData(
            rows: filtered,
            currentBranch: branchFiltered.currentBranch,
            maxColumns: branchFiltered.maxColumns,
            allBranches: branchFiltered.allBranches
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
