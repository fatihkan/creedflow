import SwiftUI

/// Shows the AI response as it streams in, with a typing indicator.
struct StreamingMessageView: View {
    let content: String
    let backend: CLIBackendType?

    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            Circle()
                .fill(Color.forgeAmber.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.forgeAmber)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AI")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.forgeAmber)

                    if let backend {
                        Text(backend.displayName)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(backend.backendColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(backend.backendColor.opacity(0.12), in: Capsule())
                    }

                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }

                if content.isEmpty {
                    // Typing dots
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.forgeAmber.opacity(i <= dotCount ? 0.8 : 0.2))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .onReceive(timer) { _ in
                        dotCount = (dotCount + 1) % 3
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(content)
                        .font(.system(.body))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
