use crate::db::models::Project;
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_projects(state: State<'_, AppState>) -> Result<Vec<Project>, String> {
    let db = state.db.lock().await;
    Project::all(&db.conn).map_err(|e| e.to_string())
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
