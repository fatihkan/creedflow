import SwiftUI

// MARK: - Color Palette

/// Creed color system — industrial command-center with warmth.
/// Uses `ShapeStyle where Self == Color` so colors work in `.foregroundStyle()`, `.fill()`, etc.
extension ShapeStyle where Self == Color {
    // Primary accent — forge amber
    static var forgeAmber: Color { Color(red: 0.91, green: 0.65, blue: 0.12) }
    static var forgeAmberLight: Color { Color(red: 0.96, green: 0.78, blue: 0.28) }
    static var forgeAmberDim: Color { Color(red: 0.72, green: 0.50, blue: 0.08) }

    // Status — forgeWarning is distinct bright yellow (not amber)
    static var forgeSuccess: Color { Color(red: 0.18, green: 0.75, blue: 0.48) }
    static var forgeDanger: Color { Color(red: 0.92, green: 0.28, blue: 0.30) }
    static var forgeWarning: Color { Color(red: 0.98, green: 0.78, blue: 0.20) }
    static var forgeInfo: Color { Color(red: 0.30, green: 0.55, blue: 0.96) }
    static var forgeNeutral: Color { Color(red: 0.50, green: 0.52, blue: 0.58) }

    // Selection
    static var forgeSelection: Color { Color(red: 0.91, green: 0.65, blue: 0.12).opacity(0.18) }

    // Surfaces
    static var forgeSurface: Color { Color(nsColor: .controlBackgroundColor) }
    static var forgeSurfaceElevated: Color { Color(nsColor: .underPageBackgroundColor) }

    // Terminal — adaptive for light/dark mode
    static var forgeTerminalBg: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
                : NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        })
    }
    static var forgeTerminalText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.72, green: 0.78, blue: 0.70, alpha: 1)
                : NSColor(red: 0.22, green: 0.26, blue: 0.20, alpha: 1)
        })
    }
    static var forgeTerminalCyan: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.40, green: 0.85, blue: 0.82, alpha: 1)
                : NSColor(red: 0.10, green: 0.55, blue: 0.52, alpha: 1)
        })
    }
    static var forgeTerminalRed: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.95, green: 0.42, blue: 0.38, alpha: 1)
                : NSColor(red: 0.80, green: 0.20, blue: 0.18, alpha: 1)
        })
    }
    static var forgeTerminalYellow: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.92, green: 0.80, blue: 0.40, alpha: 1)
                : NSColor(red: 0.65, green: 0.52, blue: 0.10, alpha: 1)
        })
    }

    // Agent type colors — agentCoder is darker blue (distinct from forgeInfo)
    static var agentAnalyzer: Color { Color(red: 0.62, green: 0.40, blue: 0.90) }
    static var agentCoder: Color { Color(red: 0.25, green: 0.48, blue: 0.88) }
    static var agentReviewer: Color { Color(red: 0.95, green: 0.55, blue: 0.15) }
    static var agentTester: Color { Color(red: 0.18, green: 0.75, blue: 0.48) }
    static var agentDevops: Color { Color(red: 0.35, green: 0.75, blue: 0.82) }
    static var agentMonitor: Color { Color(red: 0.88, green: 0.42, blue: 0.62) }
}

// MARK: - Typography Scale

extension Font {
    static let forgeTitle = Font.system(.title2, design: .default, weight: .bold)
    static let forgeHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let forgeBody = Font.system(.subheadline, design: .default)
    static let forgeCaption = Font.system(.caption, design: .default)
    static let forgeMono = Font.system(size: 11, design: .monospaced)
    static let forgeMonoSmall = Font.system(size: 10, design: .monospaced)
    static let forgeBadgeFont = Font.system(size: 10, weight: .semibold, design: .rounded)
    static let forgeMetricValue = Font.system(.title3, design: .rounded, weight: .bold)
    static let forgeMetricLabel = Font.system(size: 11)
}

// MARK: - Spacing Tokens

enum ForgeSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Agent Color Helper

extension AgentTask.AgentType {
    var themeColor: Color {
        switch self {
        case .analyzer: return .agentAnalyzer
        case .coder: return .agentCoder
        case .reviewer: return .agentReviewer
        case .tester: return .agentTester
        case .devops: return .agentDevops
        case .monitor: return .agentMonitor
        case .contentWriter: return .blue
        case .designer: return .pink
        case .imageGenerator: return .indigo
        case .videoEditor: return .teal
        }
    }

    var icon: String {
        switch self {
        case .analyzer: return "magnifyingglass"
        case .coder: return "chevron.left.forwardslash.chevron.right"
        case .reviewer: return "checkmark.shield"
        case .tester: return "testtube.2"
        case .devops: return "server.rack"
        case .monitor: return "waveform.path.ecg"
        case .contentWriter: return "doc.text"
        case .designer: return "paintbrush"
        case .imageGenerator: return "photo"
        case .videoEditor: return "film"
        }
    }
}

// MARK: - Status Color Helper

extension AgentTask.Status {
    var themeColor: Color {
        switch self {
        case .queued: return .forgeNeutral
        case .inProgress: return .forgeInfo
        case .passed: return .forgeSuccess
        case .failed: return .forgeDanger
        case .needsRevision: return .forgeWarning
        case .cancelled: return .forgeNeutral
        }
    }

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .inProgress: return "In Progress"
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .needsRevision: return "Needs Revision"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Project Status Helper

extension Project.Status {
    var themeColor: Color {
        switch self {
        case .planning: return .forgeNeutral
        case .analyzing: return .forgeInfo
        case .inProgress: return .forgeInfo
        case .reviewing: return .forgeWarning
        case .deploying: return .forgeAmber
        case .completed: return .forgeSuccess
        case .failed: return .forgeDanger
        case .paused: return .forgeNeutral
        }
    }

    var displayName: String {
        switch self {
        case .planning: return "Planning"
        case .analyzing: return "Analyzing"
        case .inProgress: return "In Progress"
        case .reviewing: return "Reviewing"
        case .deploying: return "Deploying"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .paused: return "Paused"
        }
    }
}

// MARK: - View Modifiers

/// Card surface with subtle border and shadow
struct ForgeCardModifier: ViewModifier {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isSelected ? Color.forgeAmber.opacity(0.6) : Color.primary.opacity(0.06),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

/// Metric/stat card with icon accent stripe
struct ForgeMetricCardModifier: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor)
                    .frame(width: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
    }
}

/// Badge pill with tinted background
struct ForgeBadgeModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

extension View {
    func forgeCard(selected: Bool = false, cornerRadius: CGFloat = 8) -> some View {
        modifier(ForgeCardModifier(isSelected: selected, cornerRadius: cornerRadius))
    }

    func forgeMetricCard(accent: Color = .forgeAmber) -> some View {
        modifier(ForgeMetricCardModifier(accentColor: accent))
    }

    func forgeBadge(color: Color) -> some View {
        modifier(ForgeBadgeModifier(color: color))
    }
}

// MARK: - Reusable Components

/// Inline error banner
struct ForgeErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.forgeDanger)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.forgeDanger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.forgeDanger.opacity(0.2), lineWidth: 0.5)
        }
    }
}

/// Empty state placeholder matching the forge aesthetic
struct ForgeEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color.forgeNeutral.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.caption, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeAmber)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let label: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.forgeMetricValue)
                Text(label)
                    .font(.forgeMetricLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .forgeMetricCard(accent: accent)
    }
}

/// Persistent top bar for content views — ensures consistent layout height across all sections
struct ForgeToolbar<Actions: View>: View {
    let title: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            actions()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.background)
    }
}

extension ForgeToolbar where Actions == EmptyView {
    init(title: String) {
        self.title = title
        self.actions = { EmptyView() }
    }
}

/// Duration formatter
struct ForgeDuration {
    static func format(ms: Int64) -> String {
        let totalSeconds = Double(ms) / 1000.0
        if totalSeconds < 60 {
            return String(format: "%.1fs", totalSeconds)
        } else if totalSeconds < 3600 {
            let minutes = Int(totalSeconds) / 60
            let seconds = Int(totalSeconds) % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(totalSeconds) / 3600
            let minutes = (Int(totalSeconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}
