use crate::db::models::{AgentTask, AgentTimeStat, Feature, Project, ProjectTemplate, ProjectTimeStats, Review, TemplateFeature, TemplateTask};
use crate::state::AppState;
use rusqlite::params;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_projects(
    state: State<'_, AppState>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<Project>, String> {
    let db = state.db.lock().await;
    let lim = limit.unwrap_or(50);
    let off = offset.unwrap_or(0);
    let mut stmt = db.conn.prepare(
        "SELECT * FROM project ORDER BY name LIMIT ?1 OFFSET ?2"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map(params![lim, off], |row| Project::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_project(state: State<'_, AppState>, id: String) -> Result<Project, String> {
    let db = state.db.lock().await;
    Project::get(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_project(
    state: State<'_, AppState>,
    name: String,
    description: String,
    tech_stack: String,
    project_type: String,
    directory_path: Option<String>,
) -> Result<Project, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();

    // If directory_path is provided, this is an import — verify directory exists
    let dir_path = if let Some(ref path) = directory_path {
        if !std::path::Path::new(path).is_dir() {
            return Err(format!("Directory not found: {}", path));
        }
        path.clone()
    } else {
        // Create a new project directory
        let projects_dir = dirs::home_dir()
            .unwrap_or_default()
            .join("CreedFlow")
            .join("projects")
            .join(&name);
        std::fs::create_dir_all(&projects_dir)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
        projects_dir.to_string_lossy().to_string()
    };

    let project = Project {
        id: Uuid::new_v4().to_string(),
        name,
        description,
        tech_stack,
        status: "planning".to_string(),
        directory_path: dir_path,
        project_type,
        telegram_chat_id: None,
        staging_pr_number: None,
        completed_at: None,
        created_at: now.clone(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    Project::insert(&db.conn, &project).map_err(|e| e.to_string())?;
    Ok(project)
}

#[tauri::command]
pub async fn update_project(
    state: State<'_, AppState>,
    project: Project,
) -> Result<Project, String> {
    let db = state.db.lock().await;
    Project::update(&db.conn, &project).map_err(|e| e.to_string())?;
    Ok(project)
}

#[tauri::command]
pub async fn delete_project(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    Project::delete(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_project_time_stats(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<ProjectTimeStats, String> {
    let db = state.db.lock().await;
    let project = Project::get(&db.conn, &project_id).map_err(|e| e.to_string())?;

    // Calculate elapsed time
    let created = chrono::NaiveDateTime::parse_from_str(&project.created_at, "%Y-%m-%d %H:%M:%S")
        .unwrap_or_default();
    let end = if let Some(ref completed) = project.completed_at {
        chrono::NaiveDateTime::parse_from_str(completed, "%Y-%m-%d %H:%M:%S")
            .unwrap_or_else(|_| chrono::Utc::now().naive_utc())
    } else {
        chrono::Utc::now().naive_utc()
    };
    let elapsed_ms = (end - created).num_milliseconds();

    // Sum task durations
    let total_work_ms: i64 = db.conn.query_row(
        "SELECT COALESCE(SUM(durationMs), 0) FROM agentTask WHERE projectId = ?1 AND archivedAt IS NULL",
        [&project_id],
        |row| row.get(0),
    ).unwrap_or(0);

    let idle_ms = (elapsed_ms - total_work_ms).max(0);

    // Per-agent breakdown
    let mut stmt = db.conn.prepare(
        "SELECT agentType, COALESCE(SUM(durationMs), 0) as totalMs, COUNT(*) as taskCount
         FROM agentTask WHERE projectId = ?1 AND archivedAt IS NULL
         GROUP BY agentType ORDER BY totalMs DESC"
    ).map_err(|e| e.to_string())?;

    let breakdown = stmt.query_map(params![project_id], |row| {
        Ok(AgentTimeStat {
            agent_type: row.get("agentType")?,
            total_ms: row.get("totalMs")?,
            task_count: row.get("taskCount")?,
        })
    }).map_err(|e| e.to_string())?
    .collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())?;

    Ok(ProjectTimeStats {
        elapsed_ms,
        total_work_ms,
        idle_ms,
        agent_breakdown: breakdown,
    })
}

/// Export project documentation (architecture, diagrams, summary) to a single markdown file.
/// Useful for importing into NotebookLM or other documentation tools.
#[tauri::command]
pub async fn export_project_docs(
    state: State<'_, AppState>,
    id: String,
    output_path: String,
) -> Result<String, String> {
    let db = state.db.lock().await;
    let project = Project::get(&db.conn, &id).map_err(|e| e.to_string())?;

    let project_dir = std::path::Path::new(&project.directory_path);
    let docs_dir = project_dir.join("docs");

    let mut content = String::new();

    // Project header
    content.push_str(&format!("# {} — Project Documentation\n\n", project.name));
    content.push_str(&format!("**Description:** {}\n\n", project.description));
    content.push_str(&format!("**Tech Stack:** {}\n\n", project.tech_stack));
    content.push_str(&format!("**Type:** {}\n\n", project.project_type));
    content.push_str(&format!("**Status:** {}\n\n", project.status));
    content.push_str("---\n\n");

    // Include ARCHITECTURE.md if it exists
    let arch_path = docs_dir.join("ARCHITECTURE.md");
    if arch_path.exists() {
        if let Ok(arch_content) = std::fs::read_to_string(&arch_path) {
            content.push_str("## Architecture\n\n");
            content.push_str(&arch_content);
            content.push_str("\n\n---\n\n");
        }
    }

    // Include any Mermaid diagrams from docs/diagrams/
    let diagrams_dir = docs_dir.join("diagrams");
    if diagrams_dir.is_dir() {
        if let Ok(entries) = std::fs::read_dir(&diagrams_dir) {
            let mut diagram_files: Vec<_> = entries.filter_map(|e| e.ok()).collect();
            diagram_files.sort_by_key(|e| e.file_name());

            if !diagram_files.is_empty() {
                content.push_str("## Diagrams\n\n");
                for entry in diagram_files {
                    let path = entry.path();
                    if path.extension().map_or(false, |ext| ext == "mmd" || ext == "md") {
                        let name = path.file_stem().unwrap_or_default().to_string_lossy();
                        if let Ok(diagram_content) = std::fs::read_to_string(&path) {
                            content.push_str(&format!("### {}\n\n", name));
                            if path.extension().map_or(false, |ext| ext == "mmd") {
                                content.push_str("```mermaid\n");
                                content.push_str(&diagram_content);
                                content.push_str("\n```\n\n");
                            } else {
                                content.push_str(&diagram_content);
                                content.push_str("\n\n");
                            }
                        }
                    }
                }
                content.push_str("---\n\n");
            }
        }
    }

    // Include README.md from project root if it exists
    let readme_path = project_dir.join("README.md");
    if readme_path.exists() {
        if let Ok(readme_content) = std::fs::read_to_string(&readme_path) {
            content.push_str("## README\n\n");
            content.push_str(&readme_content);
            content.push_str("\n\n");
        }
    }

    // Write output
    std::fs::write(&output_path, &content)
        .map_err(|e| format!("Failed to write export: {}", e))?;

    Ok(output_path)
}

/// Export a project as a ZIP archive containing project files, tasks JSON, and reviews JSON.
#[tauri::command]
pub async fn export_project_zip(
    state: State<'_, AppState>,
    project_id: String,
    output_path: String,
) -> Result<String, String> {
    let db = state.db.lock().await;
    let project = Project::get(&db.conn, &project_id).map_err(|e| e.to_string())?;

    // Fetch tasks and reviews
    let tasks = AgentTask::all_for_project(&db.conn, &project_id).map_err(|e| e.to_string())?;
    let task_ids: Vec<&str> = tasks.iter().map(|t| t.id.as_str()).collect();
    let reviews = Review::all(&db.conn).map_err(|e| e.to_string())?;
    let project_reviews: Vec<&Review> = reviews.iter()
        .filter(|r| task_ids.contains(&r.task_id.as_str()))
        .collect();

    // Create temp directory
    let temp_dir = std::env::temp_dir().join(format!("creedflow-export-{}", Uuid::new_v4()));
    std::fs::create_dir_all(&temp_dir).map_err(|e| format!("Failed to create temp dir: {}", e))?;
    let export_dir = temp_dir.join(&project.name);
    std::fs::create_dir_all(&export_dir).map_err(|e| e.to_string())?;

    // Copy project directory contents (skip hidden files)
    let project_dir = std::path::Path::new(&project.directory_path);
    if project_dir.is_dir() {
        if let Ok(entries) = std::fs::read_dir(project_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                if name.to_string_lossy().starts_with('.') { continue; }
                let dest = export_dir.join(&name);
                if entry.path().is_dir() {
                    let _ = copy_dir_recursive(&entry.path(), &dest);
                } else {
                    let _ = std::fs::copy(entry.path(), dest);
                }
            }
        }
    }

    // Write tasks.json and reviews.json
    let tasks_json = serde_json::to_string_pretty(&tasks).unwrap_or_default();
    std::fs::write(export_dir.join("tasks.json"), &tasks_json).map_err(|e| e.to_string())?;
    let reviews_json = serde_json::to_string_pretty(&project_reviews).unwrap_or_default();
    std::fs::write(export_dir.join("reviews.json"), &reviews_json).map_err(|e| e.to_string())?;

    // Create ZIP using system zip command
    let status = std::process::Command::new("zip")
        .args(["-r", &output_path, &project.name])
        .current_dir(&temp_dir)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map_err(|e| format!("Failed to run zip: {}", e))?;

    // Cleanup
    let _ = std::fs::remove_dir_all(&temp_dir);

    if !status.success() {
        return Err("ZIP creation failed".to_string());
    }

    Ok(output_path)
}

#[tauri::command]
pub async fn list_project_templates() -> Result<Vec<ProjectTemplate>, String> {
    Ok(built_in_templates())
}

#[tauri::command]
pub async fn create_project_from_template(
    state: State<'_, AppState>,
    template_id: String,
    name: String,
    description: Option<String>,
    tech_stack: Option<String>,
    directory_path: Option<String>,
) -> Result<Project, String> {
    let templates = built_in_templates();
    let template = templates.iter().find(|t| t.id == template_id)
        .ok_or_else(|| format!("Template not found: {}", template_id))?;

    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let project_id = Uuid::new_v4().to_string();

    let dir_path = if let Some(ref path) = directory_path {
        path.clone()
    } else {
        let projects_dir = dirs::home_dir()
            .unwrap_or_default()
            .join("CreedFlow")
            .join("projects")
            .join(&name);
        std::fs::create_dir_all(&projects_dir)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
        projects_dir.to_string_lossy().to_string()
    };

    let project = Project {
        id: project_id.clone(),
        name,
        description: description.unwrap_or_else(|| template.description.clone()),
        tech_stack: tech_stack.unwrap_or_else(|| template.tech_stack.clone()),
        status: "planning".to_string(),
        directory_path: dir_path,
        project_type: template.project_type.clone(),
        telegram_chat_id: None,
        staging_pr_number: None,
        completed_at: None,
        created_at: now.clone(),
        updated_at: now.clone(),
    };

    let db = state.db.lock().await;
    Project::insert(&db.conn, &project).map_err(|e| e.to_string())?;

    // Create features and tasks from template
    for feature_tmpl in &template.features {
        let feature_id = Uuid::new_v4().to_string();
        db.conn.execute(
            "INSERT INTO feature (id, projectId, name, description, priority, status, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, 0, 'pending', ?5, ?5)",
            params![feature_id, project_id, feature_tmpl.name, feature_tmpl.description, now],
        ).map_err(|e| e.to_string())?;

        for task_tmpl in &feature_tmpl.tasks {
            let task_id = Uuid::new_v4().to_string();
            db.conn.execute(
                "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'queued', 0, 3, ?8, ?8)",
                params![task_id, project_id, feature_id, task_tmpl.agent_type, task_tmpl.title, task_tmpl.description, task_tmpl.priority, now],
            ).map_err(|e| e.to_string())?;
        }
    }

    Ok(project)
}

fn built_in_templates() -> Vec<ProjectTemplate> {
    vec![
        ProjectTemplate {
            id: "web-app".to_string(),
            name: "Web App".to_string(),
            description: "Full-stack web application with authentication, CRUD operations, and deployment".to_string(),
            icon: "globe".to_string(),
            tech_stack: "React, Node.js, PostgreSQL".to_string(),
            project_type: "software".to_string(),
            features: vec![
                TemplateFeature { name: "Authentication".to_string(), description: "User registration, login, and session management".to_string(), tasks: vec![
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement auth API endpoints".to_string(), description: "Create signup, login, logout, and password reset endpoints".to_string(), priority: 9 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Build auth UI components".to_string(), description: "Create login, register, and forgot password forms".to_string(), priority: 8 },
                    TemplateTask { agent_type: "tester".to_string(), title: "Test authentication flow".to_string(), description: "Write integration tests for auth endpoints and UI".to_string(), priority: 7 },
                ]},
                TemplateFeature { name: "CRUD Operations".to_string(), description: "Core data management".to_string(), tasks: vec![
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement data API endpoints".to_string(), description: "Create REST endpoints for CRUD operations".to_string(), priority: 8 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Build data management UI".to_string(), description: "Create list, detail, and form views".to_string(), priority: 7 },
                ]},
                TemplateFeature { name: "Deployment".to_string(), description: "Docker-based deployment".to_string(), tasks: vec![
                    TemplateTask { agent_type: "devops".to_string(), title: "Set up Docker configuration".to_string(), description: "Create Dockerfile and docker-compose.yml".to_string(), priority: 5 },
                ]},
            ],
        },
        ProjectTemplate {
            id: "mobile-app".to_string(),
            name: "Mobile App".to_string(),
            description: "Cross-platform mobile application with native UI and API integration".to_string(),
            icon: "smartphone".to_string(),
            tech_stack: "React Native, TypeScript".to_string(),
            project_type: "software".to_string(),
            features: vec![
                TemplateFeature { name: "App UI".to_string(), description: "Core screens and navigation".to_string(), tasks: vec![
                    TemplateTask { agent_type: "designer".to_string(), title: "Design app screens".to_string(), description: "Create design specs for main screens".to_string(), priority: 9 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement navigation and screens".to_string(), description: "Build tab and stack navigation".to_string(), priority: 8 },
                ]},
                TemplateFeature { name: "API Integration".to_string(), description: "Backend connectivity".to_string(), tasks: vec![
                    TemplateTask { agent_type: "coder".to_string(), title: "Set up API client".to_string(), description: "Configure HTTP client and error handling".to_string(), priority: 8 },
                ]},
            ],
        },
        ProjectTemplate {
            id: "rest-api".to_string(),
            name: "REST API".to_string(),
            description: "Backend API service with authentication, database, and documentation".to_string(),
            icon: "server".to_string(),
            tech_stack: "Node.js, Express, PostgreSQL".to_string(),
            project_type: "software".to_string(),
            features: vec![
                TemplateFeature { name: "API Endpoints".to_string(), description: "RESTful API design and implementation".to_string(), tasks: vec![
                    TemplateTask { agent_type: "analyzer".to_string(), title: "Design API schema".to_string(), description: "Define data models and endpoint structure".to_string(), priority: 10 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement API endpoints".to_string(), description: "Build all REST endpoints".to_string(), priority: 9 },
                ]},
                TemplateFeature { name: "Testing & Docs".to_string(), description: "API tests and documentation".to_string(), tasks: vec![
                    TemplateTask { agent_type: "tester".to_string(), title: "Write API tests".to_string(), description: "Create integration tests for all endpoints".to_string(), priority: 7 },
                    TemplateTask { agent_type: "contentWriter".to_string(), title: "Generate API documentation".to_string(), description: "Create OpenAPI/Swagger docs".to_string(), priority: 5 },
                ]},
            ],
        },
        ProjectTemplate {
            id: "landing-page".to_string(),
            name: "Landing Page".to_string(),
            description: "Marketing landing page with responsive design and SEO optimization".to_string(),
            icon: "file-text".to_string(),
            tech_stack: "HTML, CSS, JavaScript".to_string(),
            project_type: "software".to_string(),
            features: vec![
                TemplateFeature { name: "Design & Layout".to_string(), description: "Visual design and responsive layout".to_string(), tasks: vec![
                    TemplateTask { agent_type: "designer".to_string(), title: "Design landing page layout".to_string(), description: "Create hero, features, and CTA sections".to_string(), priority: 9 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement responsive layout".to_string(), description: "Build mobile-first responsive design".to_string(), priority: 8 },
                ]},
                TemplateFeature { name: "Content & SEO".to_string(), description: "Copywriting and search optimization".to_string(), tasks: vec![
                    TemplateTask { agent_type: "contentWriter".to_string(), title: "Write landing page copy".to_string(), description: "Create headlines, descriptions, and CTAs".to_string(), priority: 8 },
                ]},
            ],
        },
        ProjectTemplate {
            id: "blog-cms".to_string(),
            name: "Blog / CMS".to_string(),
            description: "Content management system with blog and multi-channel publishing".to_string(),
            icon: "newspaper".to_string(),
            tech_stack: "Next.js, MDX, Tailwind CSS".to_string(),
            project_type: "software".to_string(),
            features: vec![
                TemplateFeature { name: "Content System".to_string(), description: "Blog post management".to_string(), tasks: vec![
                    TemplateTask { agent_type: "coder".to_string(), title: "Build blog engine".to_string(), description: "Create MDX-based blog with categories and search".to_string(), priority: 9 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement admin interface".to_string(), description: "Create post editor and media library".to_string(), priority: 8 },
                ]},
                TemplateFeature { name: "Design".to_string(), description: "Blog theme and components".to_string(), tasks: vec![
                    TemplateTask { agent_type: "designer".to_string(), title: "Design blog theme".to_string(), description: "Create layout and typography designs".to_string(), priority: 8 },
                ]},
            ],
        },
        ProjectTemplate {
            id: "cli-tool".to_string(),
            name: "CLI Tool".to_string(),
            description: "Command-line tool with argument parsing, subcommands, and documentation".to_string(),
            icon: "terminal".to_string(),
            tech_stack: "Python, Click".to_string(),
            project_type: "software".to_string(),
            features: vec![
                TemplateFeature { name: "Core Logic".to_string(), description: "Main functionality and commands".to_string(), tasks: vec![
                    TemplateTask { agent_type: "analyzer".to_string(), title: "Design CLI architecture".to_string(), description: "Define command structure and arguments".to_string(), priority: 10 },
                    TemplateTask { agent_type: "coder".to_string(), title: "Implement core commands".to_string(), description: "Build main CLI commands with argument parsing".to_string(), priority: 9 },
                ]},
                TemplateFeature { name: "Testing & Docs".to_string(), description: "Tests and documentation".to_string(), tasks: vec![
                    TemplateTask { agent_type: "tester".to_string(), title: "Write CLI tests".to_string(), description: "Create tests for all commands".to_string(), priority: 7 },
                    TemplateTask { agent_type: "contentWriter".to_string(), title: "Write CLI documentation".to_string(), description: "Create README and usage examples".to_string(), priority: 5 },
                ]},
            ],
        },
    ]
}

fn copy_dir_recursive(src: &std::path::Path, dst: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let dest = dst.join(entry.file_name());
        if entry.path().is_dir() {
            copy_dir_recursive(&entry.path(), &dest)?;
        } else {
            std::fs::copy(entry.path(), dest)?;
        }
    }
    Ok(())
}
