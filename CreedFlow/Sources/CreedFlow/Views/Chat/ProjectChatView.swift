import SwiftUI
import GRDB

/// Left-side chat panel for project planning conversations with AI.
struct ProjectChatView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?
    var onDismiss: (() -> Void)?

    @State private var chatService: ProjectChatService?
    @State private var inputText = ""
    @State private var project: Project?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(Color.forgeSurface)
        .task {
            await setup()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.forgeAmber)

            Text(project?.name ?? "Chat")
                .font(.system(.subheadline, weight: .semibold))
                .lineLimit(1)

            if let backend = chatService?.activeBackend {
                Text(backend.displayName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(backend.backendColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(backend.backendColor.opacity(0.12), in: Capsule())
            }

            Spacer()

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageList: some View {
        if let service = chatService {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if service.messages.isEmpty && !service.isStreaming {
                            welcomeCard
                                .padding(.top, 40)
                        }

                        ForEach(service.messages) { message in
                            ChatMessageView(
                                message: message,
                                chatService: service
                            )
                            .id(message.id)
                        }

                        if service.isStreaming {
                            StreamingMessageView(
                                content: service.streamingContent,
                                backend: service.activeBackend
                            )
                            .id("streaming")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: service.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: service.streamingContent) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        } else {
            Spacer()
            ProgressView()
            Spacer()
        }

        if let error = chatService?.error {
            ForgeErrorBanner(message: error, onDismiss: { chatService?.error = nil })
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Welcome

    private var welcomeCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.forgeAmber)

            Text("Plan your project with AI")
                .font(.system(.headline, weight: .semibold))

            Text("Discuss features, architecture, and tasks before the agents start working.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                suggestionButton("Analyze this project and suggest features")
                suggestionButton("What architecture would you recommend?")
                suggestionButton("Create a task breakdown for this project")
            }
        }
        .padding(20)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .foregroundStyle(.forgeAmber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.forgeAmber.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.forgeAmber.opacity(0.15), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $inputText)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 36, maxHeight: 120)
                .padding(6)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    sendMessage()
                }

            if chatService?.isStreaming == true {
                Button {
                    chatService?.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.forgeDanger)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.forgeNeutral : Color.forgeAmber)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func setup() async {
        guard let db = appDatabase, let orchestrator else { return }

        project = try? await db.dbQueue.read { dbConn in
            try Project.fetchOne(dbConn, id: projectId)
        }

        let service = ProjectChatService(
            dbQueue: db.dbQueue,
            backendRouter: orchestrator.backendRouter
        )
        service.bind(to: projectId)
        chatService = service
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        guard let service = chatService else { return }
        Task {
            await service.send(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if chatService?.isStreaming == true {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        } else if let lastId = chatService?.messages.last?.id {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}
