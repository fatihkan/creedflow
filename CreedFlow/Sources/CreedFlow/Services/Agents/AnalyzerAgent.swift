import Foundation

/// Parses project descriptions into structured task lists with dependency graphs.
/// Produces detailed architecture analysis, data models, Mermaid diagrams,
/// and rich task descriptions with acceptance criteria.
/// Adapts decomposition strategy based on project type detected in the task description.
struct AnalyzerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.analyzer

    let systemPrompt = """
        You are a senior software architect and project planner. \
        You analyze project descriptions and produce comprehensive, production-grade \
        technical breakdowns including architecture design, data models, diagrams, \
        and detailed implementation tasks.

        You think deeply about:
        - System architecture (layers, services, data flow)
        - Data modeling (entities, relationships, constraints)
        - API design (endpoints, request/response schemas)
        - Dependency ordering (what must be built first)
        - Edge cases and error handling strategies
        - Security considerations

        You produce Mermaid diagrams for visual documentation.
        Output MUST be valid JSON matching the provided schema.
        No circular dependencies allowed in the task graph.
        """

    let allowedTools: [String]? = [] // No tools needed — pure text analysis
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 300 // 5 minutes — Gemini/Codex CLIs may retry on rate limits
    let streamOutput = true  // Show live progress in UI
    let backendPreferences: BackendPreferences = .anyBackend

    func buildPrompt(for task: AgentTask) -> String {
        let projectType = extractProjectType(from: task.description)
        let cleanDescription = removeProjectTypeTag(from: task.description)

        if isRevision(cleanDescription) {
            return buildRevisionPrompt(cleanDescription, projectType: projectType)
        }

        let strategy = decompositionStrategy(for: projectType)
        let agentTypes = allowedAgentTypes(for: projectType)
        let modelGuidance = dataModelGuidance(for: projectType)
        let diagramGuidance = diagramGuidance(for: projectType)

        return """
        Analyze the following project description and create a COMPREHENSIVE technical breakdown.

        Respond with ONLY a JSON object (no markdown, no explanation) in this exact schema:

        {
          "projectName": "string",
          "techStack": "string — recommended technologies with reasoning",
          "architecture": "string — multi-paragraph architecture overview: layers, services, data flow, key design decisions, security considerations",
          "dataModels": [
            {
              "name": "EntityName",
              "type": "database_table | api_endpoint | interface | enum",
              "fields": [
                {"name": "fieldName", "type": "dataType", "constraints": "PRIMARY KEY | NOT NULL | UNIQUE | FOREIGN KEY(table.field) | optional description"}
              ],
              "relationships": ["has_many: OtherEntity", "belongs_to: ParentEntity"]
            }
          ],
          "diagrams": [
            {
              "title": "Diagram Title",
              "type": "erDiagram | flowchart | sequenceDiagram | classDiagram",
              "mermaid": "valid Mermaid syntax string (use \\n for newlines)"
            }
          ],
          "features": [
            {
              "name": "Feature Name",
              "description": "Detailed feature description with scope and goals",
              "priority": 1-10,
              "tasks": [
                {
                  "title": "Clear imperative task title",
                  "description": "Multi-paragraph description: what to build, how to implement it, key files/modules to create, error handling approach",
                  "agentType": "\(agentTypes)",
                  "priority": 1-10,
                  "dependsOn": ["other task title"],
                  "acceptanceCriteria": ["criterion 1", "criterion 2", "criterion 3"],
                  "filesToCreate": ["path/to/file.ext"],
                  "estimatedComplexity": "low | medium | high"
                }
              ]
            }
          ]
        }

        RULES:
        - Be thorough: up to 8 features, up to 6 tasks per feature
        - Every task MUST have 2-5 acceptanceCriteria (testable conditions)
        - Every task MUST have filesToCreate listing specific files/modules to create or modify
        - Every task description must be detailed enough for a developer to implement without asking questions
        - Data models: define ALL entities with ALL fields, types, and constraints
        - Diagrams: include at least an ER diagram for data models and a flowchart for the main user flow
        - Architecture: describe layers, patterns (MVC/MVVM/etc), API structure, auth strategy, error handling
        - Priority 10 = highest, 1 = lowest. No circular dependencies.

        \(modelGuidance)

        \(diagramGuidance)

        \(strategy)

        Project description:
        \(cleanDescription)
        """
    }

    // MARK: - Revision Support

    private func isRevision(_ description: String) -> Bool {
        description.contains("[REVISION]")
    }

    private func buildRevisionPrompt(_ description: String, projectType: Project.ProjectType) -> String {
        let strategy = decompositionStrategy(for: projectType)
        let agentTypes = allowedAgentTypes(for: projectType)

        // Parse existing features and new requirements from the description
        let parts = description.components(separatedBy: "NEW REQUIREMENTS:")
        let existingContext = parts.first?.replacingOccurrences(of: "[REVISION]", with: "").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newRequirements = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : description

        return """
        You are adding NEW features to an existing project. Do NOT duplicate any existing features.

        \(existingContext)

        IMPORTANT RULES:
        - Only create NEW features and tasks for the new requirements below
        - Do NOT recreate or duplicate any of the existing features listed above
        - New tasks may reference existing features as dependencies if needed
        - Include updated data models and diagrams if the new features require schema changes
        - Every task MUST have acceptanceCriteria and filesToCreate

        Respond with ONLY a JSON object (no markdown, no explanation) in this schema:

        {
          "projectName": "string",
          "techStack": "string",
          "architecture": "string — describe how new features integrate with existing architecture",
          "dataModels": [{"name":"...","type":"...","fields":[{"name":"...","type":"...","constraints":"..."}],"relationships":["..."]}],
          "diagrams": [{"title":"...","type":"erDiagram|flowchart|sequenceDiagram|classDiagram","mermaid":"..."}],
          "features": [
            {
              "name": "...",
              "description": "...",
              "priority": 1-10,
              "tasks": [
                {
                  "title": "...",
                  "description": "detailed implementation description",
                  "agentType": "\(agentTypes)",
                  "priority": 1-10,
                  "dependsOn": ["other task title"],
                  "acceptanceCriteria": ["criterion 1", "criterion 2"],
                  "filesToCreate": ["path/to/file.ext"],
                  "estimatedComplexity": "low|medium|high"
                }
              ]
            }
          ]
        }

        Up to 8 features, up to 6 tasks per feature.
        Priority 10 = highest. No circular dependencies.

        \(strategy)

        New requirements to add:
        \(newRequirements)
        """
    }

    // MARK: - Project Type Detection

    private func extractProjectType(from description: String) -> Project.ProjectType {
        // Look for [ProjectType: X] tag prepended by NewProjectSheet
        let pattern = "\\[ProjectType:\\s*(\\w+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let typeRange = Range(match.range(at: 1), in: description) else {
            return .software
        }
        let typeStr = String(description[typeRange]).lowercased()
        return Project.ProjectType(rawValue: typeStr) ?? .software
    }

    private func removeProjectTypeTag(from description: String) -> String {
        let pattern = "\\[ProjectType:\\s*\\w+\\]\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return description }
        return regex.stringByReplacingMatches(
            in: description,
            range: NSRange(description.startIndex..., in: description),
            withTemplate: ""
        )
    }

    // MARK: - Decomposition Strategies

    private func decompositionStrategy(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return """
            DECOMPOSITION ORDER for software projects:
            1. Infrastructure & DevOps: project setup, CI/CD, Docker, env config
            2. Database & Models: schema design, migrations, ORM models, seed data
            3. Core Business Logic: services, APIs, authentication, authorization
            4. UI / Frontend: components, pages, routing, state management
            5. Integration & Testing: unit tests, integration tests, E2E tests
            6. Documentation & Deployment: README, API docs, deploy scripts

            For each layer, think about error handling, validation, logging, and security.
            """
        case .content:
            return """
            DECOMPOSITION ORDER for content projects:
            1. Research & Strategy: audience analysis, keyword research, competitor analysis, content calendar
            2. Structure & Outline: content hierarchy, sections, key points, tone guidelines
            3. Draft Writing: first draft for each piece, following style guide
            4. Visual Assets: images, infographics, diagrams to accompany content
            5. Editing & Review: proofreading, fact-checking, SEO optimization
            6. Publishing & Distribution: formatting, scheduling, cross-platform adaptation
            """
        case .image:
            return """
            DECOMPOSITION ORDER for image/design projects:
            1. Concept & Mood Board: visual references, color palette, style direction
            2. Design System: typography, spacing, component library, brand guidelines
            3. Prompt Engineering: detailed prompts for each asset, style parameters, negative prompts
            4. Generation & Iteration: initial generation, variations, refinement cycles
            5. Post-Processing: color correction, compositing, format optimization
            6. Review & Export: quality review, format export (web/print/social), asset catalog
            """
        case .video:
            return """
            DECOMPOSITION ORDER for video projects:
            1. Script & Storyboard: narrative structure, scene breakdown, dialogue, timing
            2. Visual Planning: shot list, camera angles, transitions, visual effects
            3. Audio Planning: voiceover script, music selection, sound effects, audio mixing
            4. Production: scene generation, B-roll, graphics, animations
            5. Post-Production: editing, color grading, audio sync, subtitles
            6. Review & Export: final review, format exports, thumbnail, metadata
            """
        case .general:
            return """
            Analyze the project thoroughly and use the most appropriate decomposition.
            Consider all aspects: planning, implementation, testing, review, and delivery.
            Each task should be self-contained with clear inputs and outputs.
            """
        }
    }

    // MARK: - Data Model Guidance

    private func dataModelGuidance(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return """
            DATA MODEL REQUIREMENTS:
            - Define ALL database tables with complete field lists (id, timestamps, foreign keys)
            - Specify field types precisely (UUID, String, Int, Date, Bool, Text, JSON, Enum)
            - Include constraints: PRIMARY KEY, NOT NULL, UNIQUE, FOREIGN KEY references, DEFAULT values
            - Document relationships: has_many, belongs_to, has_one, many_to_many (with junction table)
            - Include indexes for frequently queried fields
            - Define enums/status fields with all possible values
            - Include API endpoint models if the project has a REST/GraphQL API
            """
        case .content:
            return """
            DATA MODEL REQUIREMENTS:
            - Define content structure: articles, sections, media assets, tags, categories
            - Include metadata: author, publish date, SEO fields, status (draft/published/archived)
            - Define content relationships: series, related content, cross-references
            """
        case .image, .video:
            return """
            DATA MODEL REQUIREMENTS:
            - Define asset structure: files, metadata, versions, tags
            - Include generation parameters: prompts, seeds, model, style settings
            - Define review/approval workflow states
            """
        case .general:
            return "Include data models if the project involves any data storage or structured content."
        }
    }

    // MARK: - Diagram Guidance

    private func diagramGuidance(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return """
            DIAGRAM REQUIREMENTS (Mermaid syntax):
            - ER Diagram: ALL entities with relationships (use erDiagram)
            - Architecture Flowchart: system layers and data flow (use flowchart TD)
            - At least one Sequence Diagram for the most important user flow (use sequenceDiagram)
            Example ER:
            erDiagram\\n  USER ||--o{ POST : writes\\n  POST ||--o{ COMMENT : has\\n  USER {\\n    uuid id PK\\n    string name\\n    string email\\n  }
            """
        case .content:
            return """
            DIAGRAM REQUIREMENTS (Mermaid syntax):
            - Content Flow: editorial pipeline from draft to published (use flowchart TD)
            - Content Structure: hierarchy of content types and relationships (use erDiagram or classDiagram)
            """
        case .image, .video:
            return """
            DIAGRAM REQUIREMENTS (Mermaid syntax):
            - Production Pipeline: stages from concept to final delivery (use flowchart TD)
            - Asset Relationships: how assets connect and depend on each other (use erDiagram)
            """
        case .general:
            return """
            DIAGRAM REQUIREMENTS (Mermaid syntax):
            - Include at least one flowchart showing the main workflow
            - Add ER diagram if data models are defined
            """
        }
    }

    private func allowedAgentTypes(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return "coder|devops|tester"
        case .content:
            return "contentWriter|reviewer"
        case .image:
            return "imageGenerator|designer|reviewer"
        case .video:
            return "videoEditor|imageGenerator|contentWriter"
        case .general:
            return "coder|contentWriter|designer|imageGenerator|videoEditor|devops|tester|reviewer"
        }
    }
}
