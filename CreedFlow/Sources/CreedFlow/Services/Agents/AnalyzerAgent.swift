import Foundation

/// Parses project descriptions into structured task lists with dependency graphs.
/// Produces detailed architecture analysis, data models, Mermaid diagrams,
/// and rich task descriptions with acceptance criteria.
/// Adapts decomposition strategy based on project type detected in the task description.
struct AnalyzerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.analyzer

    let systemPrompt = """
        You are a senior project strategist and planner. \
        You analyze project descriptions and produce comprehensive, production-grade \
        breakdowns including structure, planning, diagrams, \
        and detailed implementation tasks appropriate to the project type.

        You produce Mermaid diagrams for visual documentation.
        Output MUST be valid JSON matching the provided schema.
        No circular dependencies allowed in the task graph.
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 300 // 5 minutes — Gemini/Codex CLIs may retry on rate limits
    let streamOutput = true  // Show live progress in UI
    let mcpServers: [String]? = ["notebooklm"]
    let backendPreferences: BackendPreferences = .anyBackend

    func buildPrompt(for task: AgentTask) -> String {
        let projectType = extractProjectType(from: task.description)
        let cleanDescription = removeProjectTypeTag(from: task.description)

        if isRevision(cleanDescription) {
            return buildRevisionPrompt(cleanDescription, projectType: projectType)
        }

        let systemContext = buildSystemContext(for: projectType)
        let strategy = decompositionStrategy(for: projectType)
        let agentTypes = allowedAgentTypes(for: projectType)
        let modelGuidance = dataModelGuidance(for: projectType)
        let diagramGuidance = diagramGuidance(for: projectType)
        let rules = buildRules(for: projectType, agentTypes: agentTypes)

        return """
        \(systemContext)

        Analyze the following project description and create a COMPREHENSIVE breakdown.

        Respond with ONLY a JSON object (no markdown, no explanation) in this exact schema:

        {
          "projectName": "string",
          "techStack": "string — recommended technologies/tools with reasoning",
          "architecture": "string — multi-paragraph overview: structure, workflow, key decisions",
          "dataModels": [
            {
              "name": "EntityName",
              "type": "database_table | api_endpoint | interface | enum | content_type | asset_type",
              "fields": [
                {"name": "fieldName", "type": "dataType", "constraints": "description or constraint"}
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
          "configFiles": [
            {
              "path": "relative/path",
              "content": "full file content with newlines"
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
                  "description": "Multi-paragraph description: what to do, how to approach it, key deliverables, quality criteria",
                  "agentType": "\(agentTypes)",
                  "priority": 1-10,
                  "dependsOn": ["other task title"],
                  "acceptanceCriteria": ["criterion 1", "criterion 2", "criterion 3"],
                  "filesToCreate": ["path/to/deliverable.ext"],
                  "estimatedComplexity": "low | medium | high",
                  "skillPersona": "Specific expert role for this task"
                }
              ]
            }
          ]
        }

        \(rules)

        SKILL PERSONAS:
        - Every task MUST have a skillPersona describing the expert role for that specific task
        - Be specific and include domain expertise relevant to the task
        - NOT generic: "developer" or "writer"
        - Tailor to the task's responsibilities and domain

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
        let systemContext = buildSystemContext(for: projectType)
        let strategy = decompositionStrategy(for: projectType)
        let agentTypes = allowedAgentTypes(for: projectType)

        // Parse existing features and new requirements from the description
        let parts = description.components(separatedBy: "NEW REQUIREMENTS:")
        let existingContext = parts.first?.replacingOccurrences(of: "[REVISION]", with: "").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newRequirements = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : description

        return """
        \(systemContext)

        You are adding NEW features to an existing project. Do NOT duplicate any existing features.

        \(existingContext)

        IMPORTANT RULES:
        - Only create NEW features and tasks for the new requirements below
        - Do NOT recreate or duplicate any of the existing features listed above
        - New tasks may reference existing features as dependencies if needed
        - Include updated data models and diagrams if the new features require schema changes
        - Every task MUST have acceptanceCriteria, filesToCreate, and skillPersona

        Respond with ONLY a JSON object (no markdown, no explanation) in this schema:

        {
          "projectName": "string",
          "techStack": "string",
          "architecture": "string — describe how new features integrate with existing architecture",
          "dataModels": [{"name":"...","type":"...","fields":[{"name":"...","type":"...","constraints":"..."}],"relationships":["..."]}],
          "diagrams": [{"title":"...","type":"erDiagram|flowchart|sequenceDiagram|classDiagram","mermaid":"..."}],
          "configFiles": [{"path":".gitignore","content":"full file content"}],
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
                  "estimatedComplexity": "low|medium|high",
                  "skillPersona": "specific expert role for this task"
                }
              ]
            }
          ]
        }

        Up to 8 features, up to 6 tasks per feature.
        Priority 10 = highest. No circular dependencies.
        agentType MUST be one of: \(agentTypes)

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
        case .automation:
            return """
            Analyze the project thoroughly and use the most appropriate decomposition.
            Consider all aspects: planning, implementation, testing, review, and delivery.
            Each task should be self-contained with clear inputs and outputs.
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
        case .automation:
            return "Include data models if the project involves any data storage or structured content."
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
        case .automation:
            return """
            DIAGRAM REQUIREMENTS (Mermaid syntax):
            - Include at least one flowchart showing the main workflow
            - Add ER diagram if data models are defined
            """
        case .general:
            return """
            DIAGRAM REQUIREMENTS (Mermaid syntax):
            - Include at least one flowchart showing the main workflow
            - Add ER diagram if data models are defined
            """
        }
    }

    // MARK: - System Context (Project-Type-Aware)

    private func buildSystemContext(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return """
            SYSTEM CONTEXT: You are a senior software architect and project planner.
            You think deeply about system architecture (layers, services, data flow), \
            data modeling (entities, relationships, constraints), API design, \
            dependency ordering, edge cases, error handling, and security.
            """
        case .content:
            return """
            SYSTEM CONTEXT: You are a senior content strategist and editorial planner.
            You analyze content project descriptions and produce comprehensive content plans \
            including editorial calendar, content structure, audience analysis, and detailed \
            writing/publishing tasks. You think about tone, SEO, audience engagement, \
            content distribution, and editorial workflow.
            IMPORTANT: This is NOT a software project. Do NOT create coder, devops, or tester tasks. \
            Do NOT generate code files, config files, or infrastructure tasks.
            """
        case .image:
            return """
            SYSTEM CONTEXT: You are a senior creative director and visual design strategist.
            You analyze design/image project descriptions and produce comprehensive visual \
            production plans including mood boards, style guides, prompt engineering, \
            generation pipelines, and review workflows.
            IMPORTANT: This is NOT a software project. Do NOT create coder, devops, or tester tasks. \
            Do NOT generate code files, config files, or infrastructure tasks.
            """
        case .video:
            return """
            SYSTEM CONTEXT: You are a senior video production director and creative strategist.
            You analyze video project descriptions and produce comprehensive production plans \
            including scripts, storyboards, shot lists, audio planning, and post-production workflows.
            IMPORTANT: This is NOT a software project. Do NOT create coder, devops, or tester tasks. \
            Do NOT generate code files, config files, or infrastructure tasks.
            """
        case .automation:
            return """
            SYSTEM CONTEXT: You are a senior project strategist.
            Analyze the project type from the description and use the most appropriate agent types. \
            Choose agent types that match the actual work: contentWriter for writing, \
            imageGenerator/designer for visuals, videoEditor for video, coder for code, etc.
            """
        case .general:
            return """
            SYSTEM CONTEXT: You are a senior project strategist.
            Analyze the project type from the description and use the most appropriate agent types. \
            Choose agent types that match the actual work: contentWriter for writing, \
            imageGenerator/designer for visuals, videoEditor for video, coder for code, etc.
            """
        }
    }

    // MARK: - Rules (Project-Type-Aware)

    private func buildRules(for type: Project.ProjectType, agentTypes: String) -> String {
        let commonRules = """
        RULES:
        - Be thorough: up to 8 features, up to 6 tasks per feature
        - Every task MUST have 2-5 acceptanceCriteria (testable conditions)
        - Every task description must be detailed enough to implement without asking questions
        - Priority 10 = highest, 1 = lowest. No circular dependencies.
        - agentType MUST be one of: \(agentTypes)
        """

        switch type {
        case .software:
            return """
            \(commonRules)
            - Every task MUST have filesToCreate listing specific files/modules to create or modify
            - Data models: define ALL entities with ALL fields, types, and constraints
            - Diagrams: include at least an ER diagram for data models and a flowchart for the main user flow
            - Architecture: describe layers, patterns (MVC/MVVM/etc), API structure, auth strategy, error handling

            CONFIG FILES:
            - Generate project config files appropriate for the detected tech stack
            - MUST include: .gitignore (comprehensive for the detected tech stack)
            - Include when relevant: .editorconfig, .prettierrc, .eslintrc.json, tsconfig.json, docker-compose.yml, Dockerfile, Makefile, pyproject.toml, Package.swift, etc.
            - Each file must have complete, production-ready content
            - Use the "path" field for relative file paths (e.g. ".gitignore", ".editorconfig", "docker-compose.yml")
            """
        case .content:
            return """
            \(commonRules)
            - filesToCreate should list content documents (articles, outlines, briefs), NOT code files
            - Do NOT generate infrastructure, CI/CD, Docker, or code compilation tasks
            - Focus on: research, writing, editing, SEO optimization, publishing, content distribution
            - configFiles array should be empty or contain only editorial guidelines/style guides
            - Data models should describe content types (articles, newsletters, social posts), NOT database tables
            """
        case .image:
            return """
            \(commonRules)
            - filesToCreate should list image assets, design specs, mood boards, and style guides
            - Do NOT generate infrastructure, CI/CD, Docker, or code compilation tasks
            - Focus on: concept development, prompt engineering, image generation, design review, asset export
            - configFiles array should be empty or contain only design guidelines
            - Data models should describe asset types and generation parameters, NOT database tables
            """
        case .video:
            return """
            \(commonRules)
            - filesToCreate should list scripts, storyboards, video files, audio files, and export specs
            - Do NOT generate infrastructure, CI/CD, Docker, or code compilation tasks
            - Focus on: scripting, storyboarding, video generation, audio production, post-production, export
            - configFiles array should be empty or contain only production guidelines
            - Data models should describe production assets and workflow stages, NOT database tables
            """
        case .automation:
            return """
            \(commonRules)
            - Every task MUST have filesToCreate listing specific deliverables
            - Choose agent types that match the actual work described in the project
            - configFiles should only be included if the project involves software or configuration
            """
        case .general:
            return """
            \(commonRules)
            - Every task MUST have filesToCreate listing specific deliverables
            - Choose agent types that match the actual work described in the project
            - configFiles should only be included if the project involves software or configuration
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
        case .automation:
            return "coder|contentWriter|designer|imageGenerator|videoEditor|devops|tester|reviewer"
        case .general:
            return "coder|contentWriter|designer|imageGenerator|videoEditor|devops|tester|reviewer"
        }
    }
}
