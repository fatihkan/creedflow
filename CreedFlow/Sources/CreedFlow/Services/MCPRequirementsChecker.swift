import Foundation
import GRDB

// MARK: - Analysis Result

/// A detected capability that the project needs, with the MCP servers and agent that provide it.
struct DetectedCapability: Identifiable {
    let id: String               // unique key, e.g. "imageGeneration"
    let name: String             // e.g. "Image Generation"
    let icon: String             // SF Symbol
    let reason: String           // why this was detected
    let mcpServers: [String]     // MCP server IDs needed (at least one)
    let agentDisplayName: String // which agent handles this
    let isOptional: Bool         // true = nice-to-have, false = essential
}

struct MCPRequirementsChecker {

    /// Human-readable display names for MCP servers.
    static let displayNames: [String: String] = [
        "creedflow": "CreedFlow",
        "dalle": "DALL-E",
        "stability": "Stability AI",
        "replicate": "Replicate",
        "leonardo": "Leonardo.AI",
        "runway": "Runway",
        "elevenlabs": "ElevenLabs",
        "heygen": "HeyGen",
        "figma": "Figma",
        "notebooklm": "NotebookLM",
    ]

    // MARK: - Description-Aware Analysis

    /// Analyze project type + description to determine which capabilities are needed.
    /// Uses keyword matching — instant, no API call.
    static func analyzeRequirements(
        type: Project.ProjectType,
        description: String
    ) -> [DetectedCapability] {
        let desc = description.lowercased()
        var capabilities: [DetectedCapability] = []

        // Always-present: base orchestration
        capabilities.append(DetectedCapability(
            id: "orchestration",
            name: "Project Orchestration",
            icon: "hammer.fill",
            reason: "CreedFlow agents need project state access",
            mcpServers: ["creedflow"],
            agentDisplayName: "All Agents",
            isOptional: false
        ))

        // Image generation detection
        let imageKeywords = ["image", "photo", "illustration", "logo", "banner", "graphic",
                             "thumbnail", "icon", "artwork", "visual", "poster", "cover",
                             "infographic", "diagram", "mockup", "avatar", "picture",
                             "resim", "gorsel", "görsel", "kapak", "ikon", "afiş"]

        if type == .image || imageKeywords.contains(where: { desc.contains($0) }) {
            capabilities.append(DetectedCapability(
                id: "imageGeneration",
                name: "Image Generation",
                icon: "photo.fill",
                reason: type == .image
                    ? "Image project requires AI image generation"
                    : "Description mentions visual content that needs AI generation",
                mcpServers: ["dalle", "stability", "replicate", "leonardo"],
                agentDisplayName: "Image Generator",
                isOptional: type != .image
            ))
        }

        // Video generation detection
        let videoKeywords = ["video", "animation", "motion", "clip", "footage", "trailer",
                             "intro", "outro", "reel", "tutorial video", "explainer",
                             "video", "animasyon", "klip"]

        if type == .video || videoKeywords.contains(where: { desc.contains($0) }) {
            capabilities.append(DetectedCapability(
                id: "videoGeneration",
                name: "Video Generation",
                icon: "film.fill",
                reason: type == .video
                    ? "Video project requires AI video generation"
                    : "Description mentions video content",
                mcpServers: ["runway", "heygen", "replicate"],
                agentDisplayName: "Video Editor",
                isOptional: type != .video
            ))
        }

        // Audio / voice detection
        let audioKeywords = ["voice", "voiceover", "narration", "audio", "speech",
                             "podcast", "sound", "tts", "text-to-speech", "dubbing",
                             "ses", "seslendirme", "anlatım"]

        if audioKeywords.contains(where: { desc.contains($0) }) {
            capabilities.append(DetectedCapability(
                id: "audioGeneration",
                name: "Voice & Audio",
                icon: "waveform",
                reason: "Description mentions audio/voice content",
                mcpServers: ["elevenlabs"],
                agentDisplayName: "Video Editor",
                isOptional: true
            ))
        }

        // Design / Figma detection
        let designKeywords = ["design", "figma", "ui", "ux", "wireframe", "prototype",
                              "layout", "component", "design system", "tasarım"]

        if designKeywords.contains(where: { desc.contains($0) }) {
            capabilities.append(DetectedCapability(
                id: "design",
                name: "Design & Figma",
                icon: "paintbrush.fill",
                reason: "Description mentions design work",
                mcpServers: ["figma"],
                agentDisplayName: "Designer",
                isOptional: true
            ))
        }

        // NotebookLM — research, infographics, slide decks, podcasts
        let notebookKeywords = ["research", "araştır", "araştırma", "notebook",
                                "infographic", "slide", "sunum", "presentation",
                                "podcast", "summary", "özet", "rapor", "report"]

        let isContentOrImage = type == .content || type == .image
        let descMentionsNotebook = notebookKeywords.contains(where: { desc.contains($0) })

        if isContentOrImage || descMentionsNotebook {
            capabilities.append(DetectedCapability(
                id: "notebookLM",
                name: "NotebookLM",
                icon: "note.text",
                reason: isContentOrImage
                    ? "NotebookLM can create infographics, slide decks, and research for your content"
                    : "Description mentions research or presentation content",
                mcpServers: ["notebooklm"],
                agentDisplayName: "Content Writer",
                isOptional: !descMentionsNotebook
            ))
        }

        return capabilities
    }

    /// All unique MCP server IDs from the analysis.
    static func allRequiredServers(from capabilities: [DetectedCapability]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for cap in capabilities {
            for server in cap.mcpServers {
                if seen.insert(server).inserted {
                    result.append(server)
                }
            }
        }
        return result
    }

    // MARK: - Legacy (project-type-only, used by TaskBoardView banner)

    /// Simple project-type-based server list (backward compat).
    static func requiredServers(for type: Project.ProjectType) -> [String] {
        switch type {
        case .software, .content, .general, .automation:
            return ["creedflow"]
        case .image:
            return ["dalle", "stability", "replicate", "leonardo"]
        case .video:
            return ["runway", "elevenlabs", "heygen", "replicate"]
        }
    }

    static func requiresAtLeastOne(for type: Project.ProjectType) -> Bool {
        switch type {
        case .image, .video: return true
        default: return false
        }
    }
}
