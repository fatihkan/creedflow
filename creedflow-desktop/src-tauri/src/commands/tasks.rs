use crate::db::models::{AgentTask, PromptUsageRecord, TaskComment, TaskDependency};
use crate::state::AppState;
use rusqlite::params;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_tasks(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<Vec<AgentTask>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT * FROM agentTask WHERE projectId = ?1 AND archivedAt IS NULL ORDER BY priority DESC, createdAt ASC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([&project_id], |row| AgentTask::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_task(state: State<'_, AppState>, id: String) -> Result<AgentTask, String> {
    let db = state.db.lock().await;
    AgentTask::get(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_task(
    state: State<'_, AppState>,
    project_id: String,
    title: String,
    description: String,
    agent_type: String,
    priority: Option<i32>,
) -> Result<AgentTask, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let task = AgentTask {
        id: Uuid::new_v4().to_string(),
        project_id,
        feature_id: None,
        agent_type,
        title,
        description,
        priority: priority.unwrap_or(0),
        status: "queued".to_string(),
        result: None,
        error_message: None,
        retry_count: 0,
        max_retries: 3,
        session_id: None,
        branch_name: None,
        pr_number: None,
        cost_usd: None,
        duration_ms: None,
        created_at: now.clone(),
        updated_at: now,
        started_at: None,
        completed_at: None,
        backend: None,
        prompt_chain_id: None,
        revision_prompt: None,
        skill_persona: None,
        archived_at: None,
    };
    let db = state.db.lock().await;
    AgentTask::insert(&db.conn, &task).map_err(|e| e.to_string())?;
    Ok(task)
}

#[tauri::command]
pub async fn update_task_status(
    state: State<'_, AppState>,
    id: String,
    status: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AgentTask::update_status(&db.conn, &id, &status).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_task_dependencies(
    state: State<'_, AppState>,
    task_id: String,
) -> Result<Vec<TaskDependency>, String> {
    let db = state.db.lock().await;
    TaskDependency::for_task(&db.conn, &task_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn archive_tasks(
    state: State<'_, AppState>,
    ids: Vec<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    for id in &ids {
        db.conn.execute(
            "UPDATE agentTask SET archivedAt = ?2, updatedAt = datetime('now')
             WHERE id = ?1 AND status IN ('passed', 'failed', 'cancelled')",
            params![id, now],
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn restore_tasks(
    state: State<'_, AppState>,
    ids: Vec<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    for id in &ids {
        db.conn.execute(
            "UPDATE agentTask SET archivedAt = NULL, updatedAt = datetime('now') WHERE id = ?1",
            params![id],
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn permanently_delete_tasks(
    state: State<'_, AppState>,
    ids: Vec<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    for id in &ids {
        // CASCADE handles taskDependency, review, agentLog
        db.conn.execute("DELETE FROM agentTask WHERE id = ?1", params![id])
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn list_archived_tasks(
    state: State<'_, AppState>,
    project_id: Option<String>,
) -> Result<Vec<AgentTask>, String> {
    let db = state.db.lock().await;
    if let Some(pid) = project_id {
        let mut stmt = db.conn.prepare(
            "SELECT * FROM agentTask WHERE archivedAt IS NOT NULL AND projectId = ?1 ORDER BY archivedAt DESC"
        ).map_err(|e| e.to_string())?;
        let rows = stmt.query_map([&pid], |row| AgentTask::from_row(row))
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
    } else {
        let mut stmt = db.conn.prepare(
            "SELECT * FROM agentTask WHERE archivedAt IS NOT NULL ORDER BY archivedAt DESC"
        ).map_err(|e| e.to_string())?;
        let rows = stmt.query_map([], |row| AgentTask::from_row(row))
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
    }
}

#[tauri::command]
pub async fn duplicate_task(
    state: State<'_, AppState>,
    id: String,
) -> Result<AgentTask, String> {
    let db = state.db.lock().await;
    let source = AgentTask::get(&db.conn, &id).map_err(|e| e.to_string())?;
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let task = AgentTask {
        id: Uuid::new_v4().to_string(),
        project_id: source.project_id,
        feature_id: source.feature_id,
        agent_type: source.agent_type,
        title: format!("Copy of {}", source.title),
        description: source.description,
        priority: source.priority,
        status: "queued".to_string(),
        result: None,
        error_message: None,
        retry_count: 0,
        max_retries: source.max_retries,
        session_id: None,
        branch_name: None,
        pr_number: None,
        cost_usd: None,
        duration_ms: None,
        created_at: now.clone(),
        updated_at: now,
        started_at: None,
        completed_at: None,
        backend: None,
        prompt_chain_id: source.prompt_chain_id,
        revision_prompt: None,
        skill_persona: source.skill_persona,
        archived_at: None,
    };
    AgentTask::insert(&db.conn, &task).map_err(|e| e.to_string())?;
    Ok(task)
}

#[tauri::command]
pub async fn retry_task_with_revision(
    state: State<'_, AppState>,
    id: String,
    revision_prompt: Option<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE agentTask SET status = 'queued', retryCount = retryCount + 1,
         revisionPrompt = ?2, updatedAt = datetime('now') WHERE id = ?1",
        params![id, revision_prompt],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

// ─── Batch Operations ───────────────────────────────────────────────────────

#[tauri::command]
pub async fn batch_retry_tasks(
    state: State<'_, AppState>,
    ids: Vec<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    for id in &ids {
        db.conn.execute(
            "UPDATE agentTask SET status = 'queued', retryCount = retryCount + 1, updatedAt = datetime('now')
             WHERE id = ?1 AND status IN ('failed', 'needs_revision', 'cancelled')",
            params![id],
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn batch_cancel_tasks(
    state: State<'_, AppState>,
    ids: Vec<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    for id in &ids {
        db.conn.execute(
            "UPDATE agentTask SET status = 'cancelled', updatedAt = datetime('now')
             WHERE id = ?1 AND status = 'queued'",
            params![id],
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

// ─── Task Comments ──────────────────────────────────────────────────────────

#[tauri::command]
pub async fn add_task_comment(
    state: State<'_, AppState>,
    task_id: String,
    content: String,
    author: Option<String>,
) -> Result<TaskComment, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let comment = TaskComment {
        id: Uuid::new_v4().to_string(),
        task_id,
        content,
        author: author.unwrap_or_else(|| "user".to_string()),
        created_at: now,
    };
    let db = state.db.lock().await;
    TaskComment::insert(&db.conn, &comment).map_err(|e| e.to_string())?;
    Ok(comment)
}

#[tauri::command]
pub async fn list_task_comments(
    state: State<'_, AppState>,
    task_id: String,
) -> Result<Vec<TaskComment>, String> {
    let db = state.db.lock().await;
    TaskComment::all_for_task(&db.conn, &task_id).map_err(|e| e.to_string())
}

// ─── Task Prompt History ────────────────────────────────────────────────────

#[tauri::command]
pub async fn get_task_prompt_history(
    state: State<'_, AppState>,
    task_id: String,
) -> Result<Vec<PromptUsageRecord>, String> {
    let db = state.db.lock().await;
    PromptUsageRecord::for_task(&db.conn, &task_id).map_err(|e| e.to_string())
}
