import Foundation
import AppKit
import GRDB

// MARK: - Asset Pipeline Handler

extension Orchestrator {

    // MARK: - Creative Agent Completion

    /// Handle completion for creative agents (designer, imageGenerator, videoEditor).
    /// Parses JSON output for asset references, saves them, and queues a review task.
    func handleCreativeCompletion(task: AgentTask, result: AgentResult, assetType: GeneratedAsset.AssetType) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else {
            try? await taskQueue.fail(task, error: "Project not found for creative task")
            return
        }

        do {
            try await extractAndSaveAssets(output: result.output, task: task, project: project, defaultAssetType: assetType)
            await queueCreativeReview(for: task)
        } catch {
            try? await logError(taskId: task.id, agent: task.agentType,
                               message: "Creative completion error: \(error.localizedDescription)")
            try? await taskQueue.fail(task, error: error.localizedDescription)
        }
    }

    /// Handle content writer completion — parse output with 3-tier strategy, save assets, generate format variants, queue publisher.
    func handleContentWriterCompletion(task: AgentTask, result: AgentResult) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else {
            try? await taskQueue.fail(task, error: "Project not found for content writer task")
            return
        }

        do {
            let parsed = parseContentWriterOutput(rawOutput: result.output, task: task)
            let isRevision = task.retryCount > 0 || task.revisionPrompt != nil

            for asset in parsed.assets {
                let logicalName = asset.name.contains(".") ? asset.name : "\(asset.name).md"

                let (parentId, version) = await resolveVersionInfo(
                    logicalName: logicalName, project: project, task: task, isRevision: isRevision
                )

                var savedAsset = try await assetService.saveTextAsset(
                    content: asset.content,
                    fileName: logicalName,
                    project: project,
                    task: task,
                    assetType: .document,
                    mimeType: "text/markdown",
                    parentAssetId: parentId,
                    version: version
                )

                // Save metadata if available
                if let metadata = parsed.metadata {
                    let metadataJSON = try? JSONSerialization.data(withJSONObject: metadata)
                    let metadataStr = metadataJSON.flatMap { String(data: $0, encoding: .utf8) }
                    if metadataStr != nil {
                        try await dbQueue.write { db in
                            savedAsset.metadata = metadataStr
                            savedAsset.updatedAt = Date()
                            try savedAsset.update(db)
                        }
                    }
                }
            }

            await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

            // Scan for image placeholders and queue ImageGenerator tasks
            for asset in parsed.assets {
                await scanAndQueueImages(content: asset.content, task: task, project: project)
            }

            // Generate format variants (.txt, .html, .pdf, .docx) from saved .md assets
            await generateFormatVariants(task: task, project: project)

            // If publishing channels are configured, queue a publisher task
            let hasChannels = try await publishingService.enabledChannels().isEmpty == false
            if hasChannels {
                try await dbQueue.write { db in
                    let publishTask = AgentTask(
                        projectId: task.projectId,
                        featureId: task.featureId,
                        agentType: .publisher,
                        title: "Publish: \(task.title)",
                        description: "Select publishing channels and schedule publication for: \(task.title)",
                        priority: task.priority
                    )
                    try publishTask.insert(db)

                    let dep = TaskDependency(taskId: publishTask.id, dependsOnTaskId: task.id)
                    try dep.insert(db)
                }
            }

            try? await logInfo(taskId: task.id, agent: .contentWriter,
                              message: "Saved \(parsed.assets.count) document(s) via \(parsed.parseMethod) parsing")
        } catch {
            try? await logError(taskId: task.id, agent: .contentWriter,
                               message: "Content writer completion error: \(error.localizedDescription)")
        }
    }

    // MARK: - Content Writer Parsing

    /// Result of parsing ContentWriter output.
    struct ContentWriterParsedOutput {
        struct DocumentAsset {
            let name: String
            let content: String
        }
        let assets: [DocumentAsset]
        let metadata: [String: Any]?
        let parseMethod: String  // "json", "yaml", "raw"
    }

    /// Parse ContentWriter output with 3-tier fallback: JSON -> YAML front matter -> raw markdown.
    func parseContentWriterOutput(rawOutput: String?, task: AgentTask) -> ContentWriterParsedOutput {
        guard let output = rawOutput, !output.isEmpty else {
            return ContentWriterParsedOutput(assets: [], metadata: nil, parseMethod: "empty")
        }

        let cleaned = stripCLIBanners(stripANSI(output))

        // Tier 1: Try JSON {"assets": [...]} format
        if let data = extractJSON(from: cleaned) {
            struct AssetOutput: Decodable {
                let assets: [AssetItem]?
                struct AssetItem: Decodable {
                    let type: String?
                    let name: String?
                    let content: String?
                }
            }
            if let parsed = try? JSONDecoder().decode(AssetOutput.self, from: data),
               let items = parsed.assets, !items.isEmpty {
                let documents = items.compactMap { item -> ContentWriterParsedOutput.DocumentAsset? in
                    guard let content = item.content, !content.isEmpty else { return nil }
                    let name = item.name ?? "\(sanitize(task.title)).md"
                    return ContentWriterParsedOutput.DocumentAsset(name: name, content: content)
                }
                if !documents.isEmpty {
                    return ContentWriterParsedOutput(assets: documents, metadata: nil, parseMethod: "json")
                }
            }
        }

        // Tier 2: Try YAML front matter (---\n...\n---\ncontent)
        if let yamlResult = parseYAMLFrontMatter(cleaned, task: task) {
            return yamlResult
        }

        // Tier 3: Raw markdown fallback — wrap entire output as a single document asset
        let content = extractContentFromRawOutput(cleaned)
        let name = "\(sanitize(task.title)).md"
        let asset = ContentWriterParsedOutput.DocumentAsset(name: name, content: content)
        return ContentWriterParsedOutput(assets: [asset], metadata: nil, parseMethod: "raw")
    }

    /// Parse YAML front matter from content. Returns nil if no front matter found.
    func parseYAMLFrontMatter(_ text: String, task: AgentTask) -> ContentWriterParsedOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        // Find closing ---
        let afterFirst = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let rest = String(trimmed[afterFirst...]).trimmingCharacters(in: .newlines)
        guard let closingRange = rest.range(of: "\n---") else { return nil }

        let yamlBlock = String(rest[rest.startIndex..<closingRange.lowerBound])
        let markdownBody = String(rest[closingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !markdownBody.isEmpty else { return nil }

        // Parse simple YAML key-value pairs
        var metadata: [String: Any] = [:]
        var name: String?
        for line in yamlBlock.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            // Parse arrays like ["tag1", "tag2"]
            if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = String(value.dropFirst().dropLast())
                let items = inner.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                metadata[key] = items
            } else {
                metadata[key] = value
            }

            if key == "name" {
                name = value
            } else if key == "title" && name == nil {
                name = sanitize(value) + ".md"
            }
        }

        let fileName = name ?? "\(sanitize(task.title)).md"

        // Count words
        let wordCount = markdownBody.split(whereSeparator: { $0.isWhitespace }).count
        metadata["wordCount"] = wordCount
        metadata["author"] = metadata["author"] ?? "CreedFlow"

        let asset = ContentWriterParsedOutput.DocumentAsset(name: fileName, content: markdownBody)
        return ContentWriterParsedOutput(assets: [asset], metadata: metadata, parseMethod: "yaml")
    }

    /// Scan content for creedflow:image:slug placeholders and queue ImageGenerator tasks.
    func scanAndQueueImages(content: String, task: AgentTask, project: Project) async {
        let pattern = "!\\[([^\\]]*)\\]\\(creedflow:image:([a-z0-9-]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        guard !matches.isEmpty else { return }

        for match in matches {
            guard let descRange = Range(match.range(at: 1), in: content),
                  let slugRange = Range(match.range(at: 2), in: content) else { continue }

            let description = String(content[descRange])
            let slug = String(content[slugRange])

            do {
                try await dbQueue.write { db in
                    let imageTask = AgentTask(
                        projectId: task.projectId,
                        featureId: task.featureId,
                        agentType: .imageGenerator,
                        title: "Generate image: \(slug)",
                        description: "Generate an image for content placeholder. Description: \(description). Slug: \(slug). Parent content task: \(task.id)",
                        priority: task.priority
                    )
                    try imageTask.insert(db)

                    let dep = TaskDependency(taskId: imageTask.id, dependsOnTaskId: task.id)
                    try dep.insert(db)
                }
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to queue image task for slug '\(slug)': \(error.localizedDescription)")
            }
        }

        try? await logInfo(taskId: task.id, agent: .contentWriter,
                          message: "Queued \(matches.count) image generation task(s)")
    }

    /// Generate .txt, .html, .pdf, .docx format variants from .md document assets.
    func generateFormatVariants(task: AgentTask, project: Project) async {
        let mdAssets: [GeneratedAsset] = (try? await dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("taskId") == task.id)
                .filter(Column("assetType") == GeneratedAsset.AssetType.document.rawValue)
                .filter(Column("mimeType") == "text/markdown")
                .fetchAll(db)
        }) ?? []

        guard !mdAssets.isEmpty else { return }

        var variantCount = 0
        for mdAsset in mdAssets {
            let baseName = (mdAsset.name as NSString).deletingPathExtension
            let title = baseName.replacingOccurrences(of: "-", with: " ").capitalized

            // .txt — plaintext
            do {
                let exported = try await contentExporter.export(filePath: mdAsset.filePath, title: title, format: .plaintext)
                let fileName = "\(baseName).txt"
                _ = try await assetService.saveTextAsset(
                    content: exported.body,
                    fileName: fileName,
                    project: project,
                    task: task,
                    assetType: .document,
                    mimeType: "text/plain"
                )
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .txt variant: \(error.localizedDescription)")
            }

            // .html — styled HTML
            do {
                let exported = try await contentExporter.export(filePath: mdAsset.filePath, title: title, format: .html)
                let fileName = "\(baseName).html"
                _ = try await assetService.saveTextAsset(
                    content: exported.body,
                    fileName: fileName,
                    project: project,
                    task: task,
                    assetType: .document,
                    mimeType: "text/html"
                )
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .html variant: \(error.localizedDescription)")
            }

            // .pdf — rendered PDF via HTML
            do {
                let exported = try await contentExporter.export(filePath: mdAsset.filePath, title: title, format: .pdf)
                let pdfData = try await renderHTMLToPDF(html: exported.body, title: title)
                let fileName = "\(baseName).pdf"
                let dir = assetsDirectory(for: project)
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let pdfPath = (dir as NSString).appendingPathComponent(fileName)
                try pdfData.write(to: URL(fileURLWithPath: pdfPath))

                var pdfAsset = GeneratedAsset(
                    projectId: project.id,
                    taskId: task.id,
                    agentType: task.agentType,
                    assetType: .document,
                    name: fileName,
                    filePath: pdfPath,
                    mimeType: "application/pdf",
                    fileSize: Int64(pdfData.count)
                )
                try await dbQueue.write { db in
                    try pdfAsset.insert(db)
                }
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .pdf variant: \(error.localizedDescription)")
            }

            // .docx — Office Open XML
            do {
                let docxData = try await contentExporter.exportDOCX(filePath: mdAsset.filePath, title: title)
                let fileName = "\(baseName).docx"
                let dir = assetsDirectory(for: project)
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let docxPath = (dir as NSString).appendingPathComponent(fileName)
                try docxData.write(to: URL(fileURLWithPath: docxPath))

                var docxAsset = GeneratedAsset(
                    projectId: project.id,
                    taskId: task.id,
                    agentType: task.agentType,
                    assetType: .document,
                    name: fileName,
                    filePath: docxPath,
                    mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    fileSize: Int64(docxData.count)
                )
                try await dbQueue.write { db in
                    try docxAsset.insert(db)
                }
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .docx variant: \(error.localizedDescription)")
            }
        }

        if variantCount > 0 {
            await generateThumbnailsForTask(taskId: task.id, projectName: project.name)
            try? await logInfo(taskId: task.id, agent: .contentWriter,
                              message: "Generated \(variantCount) format variant(s) from \(mdAssets.count) document(s)")
        }
    }

    /// Render HTML string to PDF data using NSAttributedString.
    func renderHTMLToPDF(html: String, title: String) async throws -> Data {
        try await MainActor.run {
            guard let htmlData = html.data(using: .utf8),
                  let attrString = NSAttributedString(
                      html: htmlData,
                      options: [.documentType: NSAttributedString.DocumentType.html,
                                .characterEncoding: String.Encoding.utf8.rawValue],
                      documentAttributes: nil
                  ) else {
                throw NSError(domain: "ContentExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse HTML"])
            }

            let printInfo = NSPrintInfo()
            printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter
            printInfo.topMargin = 72
            printInfo.bottomMargin = 72
            printInfo.leftMargin = 72
            printInfo.rightMargin = 72
            printInfo.isVerticallyCentered = false

            let textStorage = NSTextStorage(attributedString: attrString)
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)

            let printableWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
            let printableHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
            let textContainer = NSTextContainer(size: NSSize(width: printableWidth, height: printableHeight))
            layoutManager.addTextContainer(textContainer)

            // Force layout
            layoutManager.ensureLayout(for: textContainer)

            let pdfData = NSMutableData()
            let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
            var mediaBox = CGRect(x: 0, y: 0, width: printInfo.paperSize.width, height: printInfo.paperSize.height)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                throw NSError(domain: "ContentExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
            }

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)

            // Calculate pages
            let totalHeight = usedRect.height
            var pageOriginY: CGFloat = 0

            while pageOriginY < totalHeight {
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: printInfo.leftMargin, y: printInfo.paperSize.height - printInfo.topMargin)
                context.scaleBy(x: 1, y: -1)
                context.translateBy(x: 0, y: -pageOriginY) // Removed extra negation

                let visibleRange = layoutManager.glyphRange(
                    forBoundingRect: CGRect(x: 0, y: pageOriginY, width: printableWidth, height: printableHeight),
                    in: textContainer
                )

                let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
                NSGraphicsContext.current = nsGraphicsContext
                layoutManager.drawGlyphs(forGlyphRange: visibleRange, at: CGPoint(x: 0, y: -pageOriginY))
                NSGraphicsContext.current = nil

                context.restoreGState()
                context.endPDFPage()
                pageOriginY += printableHeight
            }

            context.closePDF()
            return pdfData as Data
        }
    }

    func assetsDirectory(for project: Project) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/CreedFlow/projects/\(project.name)/assets"
    }

    /// Handle publisher agent completion — parse publication plan and create records.
    func handlePublisherCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .publisher, message: "Publisher returned no output")
            try? await taskQueue.fail(task, error: "Publisher returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logInfo(taskId: task.id, agent: .publisher, message: "No structured publication plan in output")
            try? await taskQueue.fail(task, error: "Could not extract publication plan from output")
            return
        }

        struct PublisherOutput: Decodable {
            let publications: [PubItem]?

            struct PubItem: Decodable {
                let assetId: String?
                let channelId: String?
                let format: String?
                let title: String?
                let tags: [String]?
                let isDraft: Bool?
            }
        }

        do {
            let parsed = try JSONDecoder().decode(PublisherOutput.self, from: data)
            guard let items = parsed.publications, !items.isEmpty else {
                try? await logInfo(taskId: task.id, agent: .publisher, message: "No publications planned")
                return
            }

            for item in items {
                guard let assetIdStr = item.assetId, let assetId = UUID(uuidString: assetIdStr),
                      let channelIdStr = item.channelId, let channelId = UUID(uuidString: channelIdStr) else {
                    continue
                }

                let format = item.format.flatMap { Publication.ExportFormat(rawValue: $0) } ?? .markdown
                let options = PublishOptions(
                    title: item.title ?? task.title,
                    tags: item.tags ?? [],
                    isDraft: item.isDraft ?? false
                )

                _ = try? await publishingService.publish(
                    assetId: assetId,
                    channelId: channelId,
                    format: format,
                    options: options
                )
            }

            try? await logInfo(taskId: task.id, agent: .publisher,
                              message: "Processed \(items.count) publication(s)")
        } catch {
            try? await logError(taskId: task.id, agent: .publisher,
                               message: "Failed to parse publisher output: \(error.localizedDescription)")
        }
    }

    /// Parse agent output for asset references and save them via AssetStorageService.
    /// Supports JSON format: {"assets": [{"type": "...", "name": "...", "url"?: "...", "filePath"?: "...", "content"?: "..."}]}
    /// Falls back to saving raw output as a text file.
    /// Automatically links to previous versions when the task has been retried (retryCount > 0).
    func extractAndSaveAssets(
        output: String?,
        task: AgentTask,
        project: Project,
        defaultAssetType: GeneratedAsset.AssetType
    ) async throws {
        guard let output, !output.isEmpty else {
            try? await logInfo(taskId: task.id, agent: task.agentType, message: "No output to save")
            return
        }

        let isRevision = task.retryCount > 0 || task.revisionPrompt != nil

        // Try parsing structured JSON output
        if let data = extractJSON(from: output) {
            struct AssetOutput: Decodable {
                let assets: [AssetItem]?

                struct AssetItem: Decodable {
                    let type: String?
                    let name: String?
                    let url: String?
                    let filePath: String?
                    let content: String?
                }
            }

            if let parsed = try? JSONDecoder().decode(AssetOutput.self, from: data),
               let items = parsed.assets, !items.isEmpty {
                for (index, item) in items.enumerated() {
                    let assetType = item.type.flatMap { GeneratedAsset.AssetType(rawValue: $0) } ?? defaultAssetType
                    let name = item.name ?? "\(task.agentType.rawValue)-\(index + 1)"
                    let logicalName = name.contains(".") ? name : "\(name).\(extensionForAssetType(assetType))"

                    // Resolve version chain
                    let (parentId, version) = await resolveVersionInfo(
                        logicalName: logicalName, project: project, task: task, isRevision: isRevision
                    )

                    if let urlStr = item.url, let url = URL(string: urlStr) {
                        _ = try await assetService.downloadAndSaveAsset(
                            url: url,
                            fileName: logicalName,
                            project: project,
                            task: task,
                            assetType: assetType,
                            parentAssetId: parentId,
                            version: version
                        )
                    } else if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
                        _ = try await assetService.recordExistingAsset(
                            filePath: path,
                            project: project,
                            task: task,
                            assetType: assetType,
                            parentAssetId: parentId,
                            version: version
                        )
                    } else if let content = item.content {
                        _ = try await assetService.saveTextAsset(
                            content: content,
                            fileName: logicalName,
                            project: project,
                            task: task,
                            assetType: assetType,
                            parentAssetId: parentId,
                            version: version
                        )
                    }
                }

                // Generate thumbnails for saved assets
                await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

                let versionNote = isRevision ? " (revision)" : ""
                try? await logInfo(taskId: task.id, agent: task.agentType,
                                  message: "Saved \(items.count) asset(s)\(versionNote)")
                return
            }
        }

        // Fallback: try to extract meaningful content from raw output
        let sanitizedTitle = sanitize(task.title)
        let fallbackContent = extractContentFromRawOutput(output)
        let ext = extensionForAssetType(defaultAssetType)
        let fileName = sanitizedTitle.isEmpty
            ? "\(task.agentType.rawValue)-\(task.id.uuidString.prefix(8)).\(ext)"
            : "\(sanitizedTitle).\(ext)"

        let (parentId, version) = await resolveVersionInfo(
            logicalName: fileName, project: project, task: task, isRevision: isRevision
        )

        _ = try await assetService.saveTextAsset(
            content: fallbackContent,
            fileName: fileName,
            project: project,
            task: task,
            assetType: defaultAssetType,
            parentAssetId: parentId,
            version: version
        )
        // Generate thumbnail for the fallback asset
        await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

        try? await logInfo(taskId: task.id, agent: task.agentType,
                          message: "Saved output as \(fileName) v\(version) (fallback)")
    }

    /// Resolve parentAssetId and version for a new asset being saved.
    /// When the task is a revision, look for a previous version by the same logical name.
    func resolveVersionInfo(
        logicalName: String,
        project: Project,
        task: AgentTask,
        isRevision: Bool
    ) async -> (parentId: UUID?, version: Int) {
        guard isRevision else { return (nil, 1) }

        // First check: same task produced an earlier version with the same name
        if let previous = try? await assetService.latestAsset(forTaskId: task.id, name: logicalName) {
            return (previous.id, previous.version + 1)
        }

        // Second check: same project+agent produced an asset with this name in a previous task
        if let previous = try? await assetService.previousAssets(
            forProjectId: project.id, agentType: task.agentType, name: logicalName
        ) {
            return (previous.id, previous.version + 1)
        }

        return (nil, 1)
    }

    /// Generate thumbnails for all assets belonging to a task.
    func generateThumbnailsForTask(taskId: UUID, projectName: String) async {
        let assets = try? await dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("taskId") == taskId)
                .filter(Column("thumbnailPath") == nil)
                .fetchAll(db)
        }
        guard let assets else { return }

        for asset in assets {
            if let thumbPath = await thumbnailService.generateThumbnail(for: asset, projectName: projectName) {
                try? await dbQueue.write { db in
                    var updated = asset
                    updated.thumbnailPath = thumbPath
                    updated.checksum = AssetVersioningService.computeChecksum(filePath: asset.filePath)
                    updated.updatedAt = Date()
                    try updated.update(db)
                }
            }
        }
    }

    /// Queue a reviewer task for creative output (same pattern as coder -> reviewer).
    func queueCreativeReview(for task: AgentTask) async {
        do {
            try await dbQueue.write { db in
                let reviewTask = AgentTask(
                    projectId: task.projectId,
                    featureId: task.featureId,
                    agentType: .reviewer,
                    title: "Review: \(task.title)",
                    description: "Review the creative output from \(task.agentType.rawValue) task: \(task.title)",
                    priority: task.priority + 1
                )
                try reviewTask.insert(db)

                // Add dependency: review depends on creative task
                let dep = TaskDependency(taskId: reviewTask.id, dependsOnTaskId: task.id)
                try dep.insert(db)

                // Link assets to review task
                try GeneratedAsset
                    .filter(Column("taskId") == task.id)
                    .updateAll(db,
                        Column("reviewTaskId").set(to: reviewTask.id),
                        Column("updatedAt").set(to: Date())
                    )
            }
        } catch {
            try? await logError(taskId: task.id, agent: task.agentType,
                               message: "Failed to queue creative review: \(error.localizedDescription)")
        }
    }

    func extensionForAssetType(_ type: GeneratedAsset.AssetType) -> String {
        switch type {
        case .image: return "png"
        case .video: return "mp4"
        case .audio: return "mp3"
        case .design: return "json"
        case .document: return "md"
        }
    }

    /// Try to extract clean content from raw agent output that failed JSON parsing.
    /// Strips markdown fences, JSON fragments, and system noise to find the actual content.
    func extractContentFromRawOutput(_ output: String) -> String {
        var text = output

        // Strip markdown code fences that may wrap the content
        let fencePattern = "```(?:json|markdown|md)?\\s*\\n([\\s\\S]*?)\\n```"
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let contentRange = Range(match.range(at: 1), in: text) {
            text = String(text[contentRange])
        }

        // If the output looks like a partial JSON with a "content" field, extract it
        let contentFieldPattern = "\"content\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        if let regex = try? NSRegularExpression(pattern: contentFieldPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let valueRange = Range(match.range(at: 1), in: text) {
            let extracted = String(text[valueRange])
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\"", with: "\"")
            if extracted.count > 100 { // Only use if substantial content was extracted
                return extracted
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sanitize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(30)
            .description
    }
}
