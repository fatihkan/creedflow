import Foundation

/// Predefined MCP server templates for quick setup
struct MCPServerTemplate: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let icon: String
    let command: String
    let defaultArgs: [String]
    let requiredInputs: [RequiredInput]
    let defaultEnv: [String: String]

    struct RequiredInput: Identifiable {
        let id: String
        let label: String
        let placeholder: String
        let type: InputType
        let envKey: String?       // Value goes into environment vars
        let argTemplate: String?  // Value replaces this placeholder in args
        let isCommand: Bool       // Value replaces the command itself

        enum InputType {
            case path
            case secret
            case text
        }

        init(
            id: String,
            label: String,
            placeholder: String,
            type: InputType,
            envKey: String? = nil,
            argTemplate: String? = nil,
            isCommand: Bool = false
        ) {
            self.id = id
            self.label = label
            self.placeholder = placeholder
            self.type = type
            self.envKey = envKey
            self.argTemplate = argTemplate
            self.isCommand = isCommand
        }
    }

    /// Build an MCPServerConfig from template + user-provided input values
    func buildConfig(inputs: [String: String]) -> MCPServerConfig {
        var finalCommand = command
        var args = defaultArgs
        var env = defaultEnv

        for input in requiredInputs {
            guard let value = inputs[input.id], !value.isEmpty else { continue }
            if input.isCommand {
                finalCommand = value
            }
            if let envKey = input.envKey {
                env[envKey] = value
            }
            if let template = input.argTemplate {
                args = args.map { $0 == template ? value : $0 }
            }
        }

        return MCPServerConfig(
            name: id,
            command: finalCommand,
            arguments: args,
            environmentVars: env
        )
    }

    // MARK: - Preset Templates

    static let all: [MCPServerTemplate] = [
        filesystem, github, promptsChat, creedFlow,
        dalle, figma, stability, elevenlabs, runway
    ]

    static let filesystem = MCPServerTemplate(
        id: "filesystem",
        displayName: "Filesystem",
        description: "Read/write access to local files",
        icon: "folder.fill",
        command: "npx",
        defaultArgs: ["-y", "@modelcontextprotocol/server-filesystem", "{root_path}"],
        requiredInputs: [
            RequiredInput(
                id: "root_path",
                label: "Root Path",
                placeholder: "/path/to/directory",
                type: .path,
                argTemplate: "{root_path}"
            )
        ],
        defaultEnv: [:]
    )

    static let github = MCPServerTemplate(
        id: "github",
        displayName: "GitHub",
        description: "GitHub API access for repos, issues, PRs",
        icon: "arrow.triangle.branch",
        command: "npx",
        defaultArgs: ["-y", "@modelcontextprotocol/server-github"],
        requiredInputs: [
            RequiredInput(
                id: "github_token",
                label: "Personal Access Token",
                placeholder: "ghp_...",
                type: .secret,
                envKey: "GITHUB_PERSONAL_ACCESS_TOKEN"
            )
        ],
        defaultEnv: [:]
    )

    static let promptsChat = MCPServerTemplate(
        id: "prompts-chat",
        displayName: "Prompts.chat",
        description: "Community prompt library via MCP",
        icon: "text.bubble.fill",
        command: "npx",
        defaultArgs: ["-y", "@anthropic/prompts-chat-mcp"],
        requiredInputs: [],
        defaultEnv: [:]
    )

    static let creedFlow = MCPServerTemplate(
        id: "creedflow",
        displayName: "CreedFlow",
        description: "CreedFlow project state access for agents",
        icon: "hammer.fill",
        command: "CreedFlowMCPServer",
        defaultArgs: [],
        requiredInputs: [
            RequiredInput(
                id: "binary_path",
                label: "Binary Path",
                placeholder: "/path/to/CreedFlowMCPServer",
                type: .path,
                isCommand: true
            )
        ],
        defaultEnv: [:]
    )

    static let dalle = MCPServerTemplate(
        id: "dalle",
        displayName: "DALL-E",
        description: "OpenAI image generation via DALL-E",
        icon: "photo.fill",
        command: "npx",
        defaultArgs: ["-y", "@modelcontextprotocol/server-openai"],
        requiredInputs: [
            RequiredInput(
                id: "openai_api_key",
                label: "OpenAI API Key",
                placeholder: "sk-...",
                type: .secret,
                envKey: "OPENAI_API_KEY"
            )
        ],
        defaultEnv: [:]
    )

    static let figma = MCPServerTemplate(
        id: "figma",
        displayName: "Figma",
        description: "Figma design file access and inspection",
        icon: "paintbrush.fill",
        command: "npx",
        defaultArgs: ["-y", "@anthropic/figma-mcp"],
        requiredInputs: [
            RequiredInput(
                id: "figma_access_token",
                label: "Figma Access Token",
                placeholder: "figd_...",
                type: .secret,
                envKey: "FIGMA_ACCESS_TOKEN"
            )
        ],
        defaultEnv: [:]
    )

    static let stability = MCPServerTemplate(
        id: "stability",
        displayName: "Stability AI",
        description: "Stability AI image generation (Stable Diffusion)",
        icon: "wand.and.stars",
        command: "npx",
        defaultArgs: ["-y", "@stability-ai/mcp-server"],
        requiredInputs: [
            RequiredInput(
                id: "stability_api_key",
                label: "Stability API Key",
                placeholder: "sk-...",
                type: .secret,
                envKey: "STABILITY_API_KEY"
            )
        ],
        defaultEnv: [:]
    )

    static let elevenlabs = MCPServerTemplate(
        id: "elevenlabs",
        displayName: "ElevenLabs",
        description: "ElevenLabs AI voice and audio generation",
        icon: "waveform",
        command: "npx",
        defaultArgs: ["-y", "@elevenlabs/mcp-server"],
        requiredInputs: [
            RequiredInput(
                id: "elevenlabs_api_key",
                label: "ElevenLabs API Key",
                placeholder: "xi_...",
                type: .secret,
                envKey: "ELEVENLABS_API_KEY"
            )
        ],
        defaultEnv: [:]
    )

    static let runway = MCPServerTemplate(
        id: "runway",
        displayName: "Runway",
        description: "Runway AI video generation and editing",
        icon: "film.fill",
        command: "npx",
        defaultArgs: ["-y", "@runway/mcp-server"],
        requiredInputs: [
            RequiredInput(
                id: "runway_api_key",
                label: "Runway API Key",
                placeholder: "rw_...",
                type: .secret,
                envKey: "RUNWAY_API_KEY"
            )
        ],
        defaultEnv: [:]
    )
}
