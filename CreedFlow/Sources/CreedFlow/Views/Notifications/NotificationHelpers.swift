import SwiftUI

// MARK: - Severity Display Helpers

extension AppNotification.Severity {
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

// MARK: - Category Display Helpers

extension AppNotification.Category {
    var displayName: String {
        switch self {
        case .backendHealth: return "Backend"
        case .mcpHealth: return "MCP"
        case .rateLimit: return "Rate Limit"
        case .task: return "Task"
        case .deploy: return "Deploy"
        case .budget: return "Budget"
        case .system: return "System"
        }
    }

    var badgeColor: Color {
        switch self {
        case .backendHealth: return .purple
        case .mcpHealth: return .teal
        case .rateLimit: return .orange
        case .task: return .blue
        case .deploy: return .green
        case .budget: return .yellow
        case .system: return .gray
        }
    }
}

// MARK: - Health Status Display Helpers

extension HealthEvent.HealthStatus {
    var indicatorColor: Color {
        switch self {
        case .healthy: return .green
        case .degraded: return .yellow
        case .unhealthy: return .red
        case .unknown: return .gray
        }
    }
}
