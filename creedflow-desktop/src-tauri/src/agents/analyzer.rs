use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType, ProjectType};

pub struct AnalyzerAgent;

impl Agent for AnalyzerAgent {
    fn agent_type(&self) -> AgentType { AgentType::Analyzer }

    fn system_prompt(&self) -> &str {
        "You are a senior project strategist and planner. You analyze project descriptions and produce comprehensive, production-grade breakdowns including structure, planning, diagrams, and detailed implementation tasks appropriate to the project type. Output MUST be valid JSON matching the provided schema. No circular dependencies allowed in the task graph."
    }

    fn timeout_seconds(&self) -> i32 { 300 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::AnyBackend
    }

    fn max_budget_usd(&self) -> f64 { 2.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        let project_type = extract_project_type(&task.description);
        let clean_description = remove_project_type_tag(&task.description);
        let system_context = build_system_context(&project_type);
        let agent_types = allowed_agent_types(&project_type);
        let strategy = decomposition_strategy(&project_type);
        let rules = build_rules(&project_type, &agent_types);

        format!(
            "{system_context}\n\n\
             Analyze the following project and decompose it into features and actionable tasks.\n\n\
             Respond with ONLY a JSON object (no markdown, no explanation) in this schema:\n\n\
             {{\n\
               \"projectName\": \"string\",\n\
               \"techStack\": \"string\",\n\
               \"architecture\": \"string\",\n\
               \"dataModels\": [{{\"name\":\"\",\"type\":\"\",\"fields\":[{{\"name\":\"\",\"type\":\"\",\"constraints\":\"\"}}],\"relationships\":[\"\"]}}],\n\
               \"diagrams\": [{{\"title\":\"\",\"type\":\"erDiagram|flowchart|sequenceDiagram|classDiagram\",\"mermaid\":\"\"}}],\n\
               \"configFiles\": [{{\"path\":\"\",\"content\":\"\"}}],\n\
               \"features\": [\n\
                 {{\n\
                   \"name\": \"\",\n\
                   \"description\": \"\",\n\
                   \"priority\": 0,\n\
                   \"tasks\": [\n\
                     {{\n\
                       \"title\": \"\",\n\
                       \"description\": \"\",\n\
                       \"agentType\": \"{agent_types}\",\n\
                       \"priority\": 0,\n\
                       \"dependsOn\": [\"\"],\n\
                       \"acceptanceCriteria\": [\"\"],\n\
                       \"filesToCreate\": [\"\"],\n\
                       \"estimatedComplexity\": \"low|medium|high\",\n\
                       \"skillPersona\": \"\"\n\
                     }}\n\
                   ]\n\
                 }}\n\
               ]\n\
             }}\n\n\
             {rules}\n\n\
             {strategy}\n\n\
             Project: {title}\n\nDescription: {desc}",
            system_context = system_context,
            agent_types = agent_types,
            rules = rules,
            strategy = strategy,
            title = task.title,
            desc = clean_description,
        )
    }
}

// MARK: - Project Type Detection

fn extract_project_type(description: &str) -> ProjectType {
    // Look for [ProjectType: X] tag prepended by NewProjectSheet
    let re = regex::Regex::new(r"\[ProjectType:\s*(\w+)\]").ok();
    match re.and_then(|r| r.captures(description)) {
        Some(caps) => {
            let type_str = caps.get(1).map(|m| m.as_str()).unwrap_or("software");
            ProjectType::from_str(type_str)
        }
        None => ProjectType::Software,
    }
}

fn remove_project_type_tag(description: &str) -> String {
    let re = regex::Regex::new(r"\[ProjectType:\s*\w+\]\s*").ok();
    match re {
        Some(r) => r.replace(description, "").into_owned(),
        None => description.to_string(),
    }
}

// MARK: - System Context (Project-Type-Aware)

fn build_system_context(project_type: &ProjectType) -> &'static str {
    match project_type {
        ProjectType::Software => {
            "SYSTEM CONTEXT: You are a senior software architect and project planner. \
             You think deeply about system architecture (layers, services, data flow), \
             data modeling (entities, relationships, constraints), API design, \
             dependency ordering, edge cases, error handling, and security."
        }
        ProjectType::Content => {
            "SYSTEM CONTEXT: You are a senior content strategist and editorial planner. \
             You analyze content project descriptions and produce comprehensive content plans \
             including editorial calendar, content structure, audience analysis, and detailed \
             writing/publishing tasks. You think about tone, SEO, audience engagement, \
             content distribution, and editorial workflow.\n\
             IMPORTANT: This is NOT a software project. Do NOT create coder, devops, or tester tasks. \
             Do NOT generate code files, config files, or infrastructure tasks."
        }
        ProjectType::Image => {
            "SYSTEM CONTEXT: You are a senior creative director and visual design strategist. \
             You analyze design/image project descriptions and produce comprehensive visual \
             production plans including mood boards, style guides, prompt engineering, \
             generation pipelines, and review workflows.\n\
             IMPORTANT: This is NOT a software project. Do NOT create coder, devops, or tester tasks. \
             Do NOT generate code files, config files, or infrastructure tasks."
        }
        ProjectType::Video => {
            "SYSTEM CONTEXT: You are a senior video production director and creative strategist. \
             You analyze video project descriptions and produce comprehensive production plans \
             including scripts, storyboards, shot lists, audio planning, and post-production workflows.\n\
             IMPORTANT: This is NOT a software project. Do NOT create coder, devops, or tester tasks. \
             Do NOT generate code files, config files, or infrastructure tasks."
        }
        ProjectType::General => {
            "SYSTEM CONTEXT: You are a senior project strategist. \
             Analyze the project type from the description and use the most appropriate agent types. \
             Choose agent types that match the actual work: contentWriter for writing, \
             imageGenerator/designer for visuals, videoEditor for video, coder for code, etc."
        }
    }
}

// MARK: - Allowed Agent Types

fn allowed_agent_types(project_type: &ProjectType) -> &'static str {
    match project_type {
        ProjectType::Software => "coder|devops|tester",
        ProjectType::Content => "contentWriter|reviewer",
        ProjectType::Image => "imageGenerator|designer|reviewer",
        ProjectType::Video => "videoEditor|imageGenerator|contentWriter",
        ProjectType::General => "coder|contentWriter|designer|imageGenerator|videoEditor|devops|tester|reviewer",
    }
}

// MARK: - Decomposition Strategy

fn decomposition_strategy(project_type: &ProjectType) -> &'static str {
    match project_type {
        ProjectType::Software => {
            "DECOMPOSITION ORDER for software projects:\n\
             1. Infrastructure & DevOps: project setup, CI/CD, Docker, env config\n\
             2. Database & Models: schema design, migrations, ORM models, seed data\n\
             3. Core Business Logic: services, APIs, authentication, authorization\n\
             4. UI / Frontend: components, pages, routing, state management\n\
             5. Integration & Testing: unit tests, integration tests, E2E tests\n\
             6. Documentation & Deployment: README, API docs, deploy scripts\n\n\
             For each layer, think about error handling, validation, logging, and security."
        }
        ProjectType::Content => {
            "DECOMPOSITION ORDER for content projects:\n\
             1. Research & Strategy: audience analysis, keyword research, competitor analysis, content calendar\n\
             2. Structure & Outline: content hierarchy, sections, key points, tone guidelines\n\
             3. Draft Writing: first draft for each piece, following style guide\n\
             4. Visual Assets: images, infographics, diagrams to accompany content\n\
             5. Editing & Review: proofreading, fact-checking, SEO optimization\n\
             6. Publishing & Distribution: formatting, scheduling, cross-platform adaptation"
        }
        ProjectType::Image => {
            "DECOMPOSITION ORDER for image/design projects:\n\
             1. Concept & Mood Board: visual references, color palette, style direction\n\
             2. Design System: typography, spacing, component library, brand guidelines\n\
             3. Prompt Engineering: detailed prompts for each asset, style parameters, negative prompts\n\
             4. Generation & Iteration: initial generation, variations, refinement cycles\n\
             5. Post-Processing: color correction, compositing, format optimization\n\
             6. Review & Export: quality review, format export (web/print/social), asset catalog"
        }
        ProjectType::Video => {
            "DECOMPOSITION ORDER for video projects:\n\
             1. Script & Storyboard: narrative structure, scene breakdown, dialogue, timing\n\
             2. Visual Planning: shot list, camera angles, transitions, visual effects\n\
             3. Audio Planning: voiceover script, music selection, sound effects, audio mixing\n\
             4. Production: scene generation, B-roll, graphics, animations\n\
             5. Post-Production: editing, color grading, audio sync, subtitles\n\
             6. Review & Export: final review, format exports, thumbnail, metadata"
        }
        ProjectType::General => {
            "Analyze the project thoroughly and use the most appropriate decomposition.\n\
             Consider all aspects: planning, implementation, testing, review, and delivery.\n\
             Each task should be self-contained with clear inputs and outputs."
        }
    }
}

// MARK: - Rules (Project-Type-Aware)

fn build_rules(project_type: &ProjectType, agent_types: &str) -> String {
    let common = format!(
        "RULES:\n\
         - Be thorough: up to 8 features, up to 6 tasks per feature\n\
         - Every task MUST have 2-5 acceptanceCriteria (testable conditions)\n\
         - Every task description must be detailed enough to implement without asking questions\n\
         - Priority 10 = highest, 1 = lowest. No circular dependencies.\n\
         - agentType MUST be one of: {}",
        agent_types
    );

    let specific = match project_type {
        ProjectType::Software => {
            "- Every task MUST have filesToCreate listing specific files/modules to create or modify\n\
             - Data models: define ALL entities with ALL fields, types, and constraints\n\
             - Diagrams: include at least an ER diagram for data models and a flowchart for the main user flow\n\
             - Architecture: describe layers, patterns (MVC/MVVM/etc), API structure, auth strategy, error handling\n\n\
             CONFIG FILES:\n\
             - Generate project config files appropriate for the detected tech stack\n\
             - MUST include: .gitignore (comprehensive for the detected tech stack)\n\
             - Include when relevant: .editorconfig, .prettierrc, tsconfig.json, docker-compose.yml, Dockerfile, etc.\n\
             - Each file must have complete, production-ready content"
        }
        ProjectType::Content => {
            "- filesToCreate should list content documents (articles, outlines, briefs), NOT code files\n\
             - Do NOT generate infrastructure, CI/CD, Docker, or code compilation tasks\n\
             - Focus on: research, writing, editing, SEO optimization, publishing, content distribution\n\
             - configFiles array should be empty or contain only editorial guidelines/style guides\n\
             - Data models should describe content types (articles, newsletters, social posts), NOT database tables"
        }
        ProjectType::Image => {
            "- filesToCreate should list image assets, design specs, mood boards, and style guides\n\
             - Do NOT generate infrastructure, CI/CD, Docker, or code compilation tasks\n\
             - Focus on: concept development, prompt engineering, image generation, design review, asset export\n\
             - configFiles array should be empty or contain only design guidelines\n\
             - Data models should describe asset types and generation parameters, NOT database tables"
        }
        ProjectType::Video => {
            "- filesToCreate should list scripts, storyboards, video files, audio files, and export specs\n\
             - Do NOT generate infrastructure, CI/CD, Docker, or code compilation tasks\n\
             - Focus on: scripting, storyboarding, video generation, audio production, post-production, export\n\
             - configFiles array should be empty or contain only production guidelines\n\
             - Data models should describe production assets and workflow stages, NOT database tables"
        }
        ProjectType::General => {
            "- Every task MUST have filesToCreate listing specific deliverables\n\
             - Choose agent types that match the actual work described in the project\n\
             - configFiles should only be included if the project involves software or configuration"
        }
    };

    format!("{}\n{}", common, specific)
}
