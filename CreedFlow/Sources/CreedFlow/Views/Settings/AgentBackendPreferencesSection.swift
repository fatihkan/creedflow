import SwiftUI

/// Settings section that lets users customize which CLI backends each agent prefers.
///
/// Displayed inside the "AI CLIs" tab of SettingsView. Each agent row shows its
/// current backend order as colored chips. Expanding a row lets users reorder,
/// add, or remove backends. `requiresClaudeFeatures` agents show an MCP warning
/// if Claude is removed from their list.
struct AgentBackendPreferencesSection: View {
    @State private var store = AgentBackendPreferencesStore()
    @State private var expandedAgent: AgentTask.AgentType?
    @State private var editedPrefs: [AgentTask.AgentType: [CLIBackendType]] = [:]

    private let agents = AgentTask.AgentType.allCases

    var body: some View {
        Section {
            Text("Customize which CLI backend each agent prefers. The first available backend in the list is used.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(agents, id: \.self) { agentType in
                agentRow(agentType)
            }

            if agents.contains(where: { store.isCustomized(for: $0) }) {
                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        store.resetAll()
                        editedPrefs.removeAll()
                        expandedAgent = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Agent Preferences")
        }
    }

    // MARK: - Agent Row

    @ViewBuilder
    private func agentRow(_ agentType: AgentTask.AgentType) -> some View {
        let isExpanded = expandedAgent == agentType
        let currentPrefs = currentBackends(for: agentType)
        let hardcoded = AgentBackendPreferencesStore.defaults[agentType] ?? .default
        let isCustom = store.isCustomized(for: agentType)

        VStack(alignment: .leading, spacing: 6) {
            // Collapsed header
            HStack(spacing: 8) {
                Image(systemName: agentType.icon)
                    .font(.caption)
                    .foregroundStyle(agentType.themeColor)
                    .frame(width: 18)

                Text(agentType.displayName)
                    .font(.subheadline.weight(.medium))

                if hardcoded.requiresClaudeFeatures {
                    Text("MCP")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }

                Spacer()

                // Backend summary chips
                HStack(spacing: 3) {
                    ForEach(currentPrefs, id: \.self) { backend in
                        Text(backend.displayName)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(backend.backendColor.opacity(0.12))
                            .foregroundStyle(backend.backendColor)
                            .clipShape(Capsule())
                    }
                }

                if isCustom {
                    Button {
                        store.resetToDefault(for: agentType)
                        editedPrefs.removeValue(forKey: agentType)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        // Save and collapse
                        if let edited = editedPrefs[agentType] {
                            store.setPreferred(edited, for: agentType)
                        }
                        expandedAgent = nil
                    } else {
                        // Expand — load current prefs into edit buffer
                        editedPrefs[agentType] = currentPrefs
                        expandedAgent = agentType
                    }
                }
            }

            // Expanded editor
            if isExpanded {
                expandedEditor(agentType, hardcoded: hardcoded)
            }
        }
    }

    // MARK: - Expanded Editor

    @ViewBuilder
    private func expandedEditor(_ agentType: AgentTask.AgentType, hardcoded: BackendPreferences) -> some View {
        let backends = editedPrefs[agentType] ?? currentBackends(for: agentType)
        let available = CLIBackendType.allCases.filter { !backends.contains($0) }

        VStack(alignment: .leading, spacing: 8) {
            // Warning if Claude removed from MCP agent
            if hardcoded.requiresClaudeFeatures && !backends.contains(.claude) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("This agent uses MCP tools that require Claude. Tasks may fail without it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Current order — draggable chips
            Text("Preference order (first available is used):")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(Array(backends.enumerated()), id: \.element) { index, backend in
                    HStack(spacing: 4) {
                        Text("\(index + 1).")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(backend.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(backend.backendColor.opacity(0.12))
                    .foregroundStyle(backend.backendColor)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(backend.backendColor.opacity(0.2), lineWidth: 0.5)
                    }
                    .contextMenu {
                        if index > 0 {
                            Button("Move Up") { moveBackend(agentType, at: index, direction: -1) }
                        }
                        if index < backends.count - 1 {
                            Button("Move Down") { moveBackend(agentType, at: index, direction: 1) }
                        }
                        if backends.count > 1 {
                            Divider()
                            Button("Remove", role: .destructive) { removeBackend(agentType, at: index) }
                        }
                    }
                }
            }

            // Move buttons row
            HStack(spacing: 4) {
                ForEach(Array(backends.enumerated()), id: \.element) { index, _ in
                    HStack(spacing: 2) {
                        Button {
                            moveBackend(agentType, at: index, direction: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)

                        Button {
                            moveBackend(agentType, at: index, direction: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .disabled(index == backends.count - 1)

                        if backends.count > 1 {
                            Button {
                                removeBackend(agentType, at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: chipWidth(for: backends[index]), alignment: .center)
                }
            }

            // Add backends
            if !available.isEmpty {
                HStack(spacing: 4) {
                    Text("Add:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ForEach(available, id: \.self) { backend in
                        Button {
                            addBackend(agentType, backend: backend)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                Text(backend.displayName)
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(backend.backendColor.opacity(0.06))
                            .foregroundStyle(backend.backendColor.opacity(0.7))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(backend.backendColor.opacity(0.15), lineWidth: 0.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.leading, 26)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func currentBackends(for agentType: AgentTask.AgentType) -> [CLIBackendType] {
        store.preferences(for: agentType).preferred
    }

    private func moveBackend(_ agentType: AgentTask.AgentType, at index: Int, direction: Int) {
        var backends = editedPrefs[agentType] ?? currentBackends(for: agentType)
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < backends.count else { return }
        backends.swapAt(index, newIndex)
        editedPrefs[agentType] = backends
        store.setPreferred(backends, for: agentType)
    }

    private func removeBackend(_ agentType: AgentTask.AgentType, at index: Int) {
        var backends = editedPrefs[agentType] ?? currentBackends(for: agentType)
        guard backends.count > 1 else { return }
        backends.remove(at: index)
        editedPrefs[agentType] = backends
        store.setPreferred(backends, for: agentType)
    }

    private func addBackend(_ agentType: AgentTask.AgentType, backend: CLIBackendType) {
        var backends = editedPrefs[agentType] ?? currentBackends(for: agentType)
        backends.append(backend)
        editedPrefs[agentType] = backends
        store.setPreferred(backends, for: agentType)
    }

    private func chipWidth(for backend: CLIBackendType) -> CGFloat {
        // Approximate width based on display name length + padding
        CGFloat(backend.displayName.count) * 7 + 28
    }
}
