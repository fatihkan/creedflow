use crate::db::models::Prompt;
use crate::state::AppState;
use rusqlite::params;
use tauri::State;
use uuid::Uuid;

impl Prompt {
    pub fn all(conn: &rusqlite::Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM prompt ORDER BY updatedAt DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            title: row.get("title")?,
            content: row.get("content")?,
            source: row.get("source")?,
            category: row.get("category")?,
            contributor: row.get("contributor")?,
            is_built_in: row.get::<_, i32>("isBuiltIn")? != 0,
            is_favorite: row.get::<_, i32>("isFavorite")? != 0,
            version: row.get("version")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }
}

#[tauri::command]
pub async fn list_prompts(state: State<'_, AppState>) -> Result<Vec<Prompt>, String> {
    let db = state.db.lock().await;
    Prompt::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_prompt(
    state: State<'_, AppState>,
    title: String,
    content: String,
    category: String,
) -> Result<Prompt, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let id = Uuid::new_v4().to_string();

    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO prompt (id, title, content, source, category, createdAt, updatedAt)
         VALUES (?1, ?2, ?3, 'user', ?4, ?5, ?6)",
        params![id, title, content, category, now, now],
    ).map_err(|e| e.to_string())?;

    db.conn.query_row(
        "SELECT * FROM prompt WHERE id = ?1",
        [&id],
        |row| Prompt::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_prompt(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("DELETE FROM prompt WHERE id = ?1", [&id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn toggle_favorite(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE prompt SET isFavorite = CASE WHEN isFavorite = 0 THEN 1 ELSE 0 END WHERE id = ?1",
        [&id],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

// ─── Prompt Chains ──────────────────────────────────────────────────────────

use crate::db::models::{PromptChain, PromptChainStep};

impl PromptChain {
    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            name: row.get("name")?,
            description: row.get("description")?,
            category: row.get("category")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }
}

impl PromptChainStep {
    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            chain_id: row.get("chainId")?,
            prompt_id: row.get("promptId")?,
            step_order: row.get("stepOrder")?,
            transition_note: row.get("transitionNote")?,
        })
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptChainWithSteps {
    #[serde(flatten)]
    pub chain: PromptChain,
    pub steps: Vec<PromptChainStep>,
    pub step_count: usize,
}

#[tauri::command]
pub async fn list_prompt_chains(state: State<'_, AppState>) -> Result<Vec<PromptChainWithSteps>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT * FROM promptChain ORDER BY updatedAt DESC"
    ).map_err(|e| e.to_string())?;
    let chains: Vec<PromptChain> = stmt.query_map([], |row| PromptChain::from_row(row))
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    let mut result = Vec::new();
    for chain in chains {
        let mut step_stmt = db.conn.prepare(
            "SELECT * FROM promptChainStep WHERE chainId = ?1 ORDER BY stepOrder"
        ).map_err(|e| e.to_string())?;
        let steps: Vec<PromptChainStep> = step_stmt.query_map([&chain.id], |row| PromptChainStep::from_row(row))
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        let step_count = steps.len();
        result.push(PromptChainWithSteps { chain, steps, step_count });
    }
    Ok(result)
}

#[tauri::command]
pub async fn get_prompt_chain(state: State<'_, AppState>, id: String) -> Result<PromptChainWithSteps, String> {
    let db = state.db.lock().await;
    let chain = db.conn.query_row(
        "SELECT * FROM promptChain WHERE id = ?1",
        [&id],
        |row| PromptChain::from_row(row),
    ).map_err(|e| format!("Chain not found: {}", e))?;

    let mut step_stmt = db.conn.prepare(
        "SELECT * FROM promptChainStep WHERE chainId = ?1 ORDER BY stepOrder"
    ).map_err(|e| e.to_string())?;
    let steps: Vec<PromptChainStep> = step_stmt.query_map([&id], |row| PromptChainStep::from_row(row))
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    let step_count = steps.len();
    Ok(PromptChainWithSteps { chain, steps, step_count })
}

#[tauri::command]
pub async fn create_prompt_chain(
    state: State<'_, AppState>,
    name: String,
    description: String,
    category: String,
) -> Result<PromptChain, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let id = Uuid::new_v4().to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO promptChain (id, name, description, category, createdAt, updatedAt) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![id, name, description, category, now, now],
    ).map_err(|e| e.to_string())?;
    db.conn.query_row(
        "SELECT * FROM promptChain WHERE id = ?1",
        [&id],
        |row| PromptChain::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_prompt_chain(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("DELETE FROM promptChain WHERE id = ?1", [&id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn add_chain_step(
    state: State<'_, AppState>,
    chain_id: String,
    prompt_id: String,
    step_order: i32,
    transition_note: Option<String>,
) -> Result<PromptChainStep, String> {
    let id = Uuid::new_v4().to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO promptChainStep (id, chainId, promptId, stepOrder, transitionNote) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![id, chain_id, prompt_id, step_order, transition_note],
    ).map_err(|e| e.to_string())?;
    db.conn.execute(
        "UPDATE promptChain SET updatedAt = datetime('now') WHERE id = ?1",
        [&chain_id],
    ).map_err(|_| "".to_string()).ok();
    db.conn.query_row(
        "SELECT * FROM promptChainStep WHERE id = ?1",
        [&id],
        |row| PromptChainStep::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn remove_chain_step(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("DELETE FROM promptChainStep WHERE id = ?1", [&id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn reorder_chain_steps(
    state: State<'_, AppState>,
    steps: Vec<(String, i32)>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    for (step_id, new_order) in &steps {
        db.conn.execute(
            "UPDATE promptChainStep SET stepOrder = ?1 WHERE id = ?2",
            params![new_order, step_id],
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn update_chain_step(
    state: State<'_, AppState>,
    id: String,
    transition_note: Option<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE promptChainStep SET transitionNote = ?1 WHERE id = ?2",
        params![transition_note, id],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn update_prompt_chain(
    state: State<'_, AppState>,
    id: String,
    name: String,
    description: String,
    category: String,
) -> Result<PromptChain, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE promptChain SET name = ?1, description = ?2, category = ?3, updatedAt = ?4 WHERE id = ?5",
        params![name, description, category, now, id],
    ).map_err(|e| e.to_string())?;
    db.conn.query_row(
        "SELECT * FROM promptChain WHERE id = ?1",
        [&id],
        |row| PromptChain::from_row(row),
    ).map_err(|e| e.to_string())
}

// ─── Prompt Effectiveness ───────────────────────────────────────────────────

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptEffectivenessStats {
    pub prompt_id: String,
    pub prompt_title: String,
    pub total_uses: i64,
    pub success_count: i64,
    pub fail_count: i64,
    pub avg_review_score: Option<f64>,
    pub success_rate: f64,
}

#[tauri::command]
pub async fn get_prompt_effectiveness(state: State<'_, AppState>) -> Result<Vec<PromptEffectivenessStats>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT p.id, p.title,
                COUNT(pu.id) as totalUses,
                SUM(CASE WHEN pu.outcome = 'pass' THEN 1 ELSE 0 END) as successCount,
                SUM(CASE WHEN pu.outcome = 'fail' THEN 1 ELSE 0 END) as failCount,
                AVG(pu.reviewScore) as avgScore
         FROM prompt p
         LEFT JOIN promptUsage pu ON pu.promptId = p.id
         GROUP BY p.id
         HAVING totalUses > 0
         ORDER BY totalUses DESC"
    ).map_err(|e| e.to_string())?;

    let rows = stmt.query_map([], |row| {
        let total: i64 = row.get("totalUses")?;
        let success: i64 = row.get("successCount")?;
        Ok(PromptEffectivenessStats {
            prompt_id: row.get("id")?,
            prompt_title: row.get("title")?,
            total_uses: total,
            success_count: success,
            fail_count: row.get("failCount")?,
            avg_review_score: row.get("avgScore")?,
            success_rate: if total > 0 { success as f64 / total as f64 * 100.0 } else { 0.0 },
        })
    }).map_err(|e| e.to_string())?;

    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

// ─── Prompt Import/Export ──────────────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptExport {
    pub version: String,
    pub exported_at: String,
    pub prompts: Vec<Prompt>,
}

#[tauri::command]
pub async fn export_prompts(
    state: State<'_, AppState>,
    prompt_ids: Vec<String>,
    file_path: String,
) -> Result<String, String> {
    let db = state.db.lock().await;
    let mut prompts = Vec::new();
    for id in &prompt_ids {
        let prompt = db.conn.query_row(
            "SELECT * FROM prompt WHERE id = ?1",
            [id],
            |row| Prompt::from_row(row),
        ).map_err(|e| format!("Prompt not found: {}", e))?;
        prompts.push(prompt);
    }

    let export = PromptExport {
        version: "1.0".to_string(),
        exported_at: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        prompts,
    };

    let json = serde_json::to_string_pretty(&export)
        .map_err(|e| format!("Failed to serialize: {}", e))?;
    std::fs::write(&file_path, &json)
        .map_err(|e| format!("Failed to write file: {}", e))?;

    Ok(file_path)
}

#[tauri::command]
pub async fn import_prompts(
    state: State<'_, AppState>,
    file_path: String,
) -> Result<Vec<Prompt>, String> {
    let content = std::fs::read_to_string(&file_path)
        .map_err(|e| format!("Failed to read file: {}", e))?;
    let export: PromptExport = serde_json::from_str(&content)
        .map_err(|e| format!("Invalid prompt file: {}", e))?;

    let db = state.db.lock().await;
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let mut imported = Vec::new();

    for mut prompt in export.prompts {
        // Generate new ID to avoid conflicts
        prompt.id = Uuid::new_v4().to_string();
        prompt.created_at = now.clone();
        prompt.updated_at = now.clone();
        prompt.is_built_in = false;
        prompt.source = "user".to_string();

        db.conn.execute(
            "INSERT INTO prompt (id, title, content, source, category, contributor, isBuiltIn, isFavorite, version, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                prompt.id, prompt.title, prompt.content, prompt.source,
                prompt.category, prompt.contributor, prompt.is_built_in as i32,
                prompt.is_favorite as i32, prompt.version, prompt.created_at, prompt.updated_at
            ],
        ).map_err(|e| format!("Failed to import prompt: {}", e))?;

        imported.push(prompt);
    }

    Ok(imported)
}

// ─── Prompt Version Diff ───────────────────────────────────────────────────

use crate::db::models::PromptVersion;

impl PromptVersion {
    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            prompt_id: row.get("promptId")?,
            version: row.get("version")?,
            title: row.get("title")?,
            content: row.get("content")?,
            change_note: row.get("changeNote")?,
            created_at: row.get("createdAt")?,
        })
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptVersionDiff {
    pub version_a: PromptVersion,
    pub version_b: PromptVersion,
    pub diff_lines: Vec<DiffLine>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiffLine {
    pub line_type: String, // "added", "removed", "unchanged"
    pub content: String,
    pub line_number_a: Option<usize>,
    pub line_number_b: Option<usize>,
}

#[tauri::command]
pub async fn get_prompt_versions(
    state: State<'_, AppState>,
    prompt_id: String,
) -> Result<Vec<PromptVersion>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT * FROM promptVersion WHERE promptId = ?1 ORDER BY version DESC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([&prompt_id], |row| PromptVersion::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_prompt_version_diff(
    state: State<'_, AppState>,
    prompt_id: String,
    version_a: i32,
    version_b: i32,
) -> Result<PromptVersionDiff, String> {
    let db = state.db.lock().await;

    let va = db.conn.query_row(
        "SELECT * FROM promptVersion WHERE promptId = ?1 AND version = ?2",
        params![prompt_id, version_a],
        |row| PromptVersion::from_row(row),
    ).map_err(|e| format!("Version {} not found: {}", version_a, e))?;

    let vb = db.conn.query_row(
        "SELECT * FROM promptVersion WHERE promptId = ?1 AND version = ?2",
        params![prompt_id, version_b],
        |row| PromptVersion::from_row(row),
    ).map_err(|e| format!("Version {} not found: {}", version_b, e))?;

    let lines_a: Vec<&str> = va.content.lines().collect();
    let lines_b: Vec<&str> = vb.content.lines().collect();

    let mut diff_lines = Vec::new();
    let max_len = lines_a.len().max(lines_b.len());

    for i in 0..max_len {
        match (lines_a.get(i), lines_b.get(i)) {
            (Some(a), Some(b)) if a == b => {
                diff_lines.push(DiffLine {
                    line_type: "unchanged".to_string(),
                    content: a.to_string(),
                    line_number_a: Some(i + 1),
                    line_number_b: Some(i + 1),
                });
            }
            (Some(a), Some(b)) => {
                diff_lines.push(DiffLine {
                    line_type: "removed".to_string(),
                    content: a.to_string(),
                    line_number_a: Some(i + 1),
                    line_number_b: None,
                });
                diff_lines.push(DiffLine {
                    line_type: "added".to_string(),
                    content: b.to_string(),
                    line_number_a: None,
                    line_number_b: Some(i + 1),
                });
            }
            (Some(a), None) => {
                diff_lines.push(DiffLine {
                    line_type: "removed".to_string(),
                    content: a.to_string(),
                    line_number_a: Some(i + 1),
                    line_number_b: None,
                });
            }
            (None, Some(b)) => {
                diff_lines.push(DiffLine {
                    line_type: "added".to_string(),
                    content: b.to_string(),
                    line_number_a: None,
                    line_number_b: Some(i + 1),
                });
            }
            (None, None) => {}
        }
    }

    Ok(PromptVersionDiff {
        version_a: va,
        version_b: vb,
        diff_lines,
    })
}

// ─── Prompt Recommender ────────────────────────────────────────────────────

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptRecommendation {
    pub prompt_id: String,
    pub prompt_title: String,
    pub category: String,
    pub success_rate: f64,
    pub total_uses: i64,
    pub avg_review_score: Option<f64>,
}

#[tauri::command]
pub async fn get_prompt_recommendations(
    state: State<'_, AppState>,
    agent_type: Option<String>,
    category: Option<String>,
    limit: Option<i64>,
) -> Result<Vec<PromptRecommendation>, String> {
    let db = state.db.lock().await;
    let limit = limit.unwrap_or(10);

    let mut sql = String::from(
        "SELECT p.id, p.title, p.category,
                COUNT(pu.id) as totalUses,
                SUM(CASE WHEN pu.outcome = 'pass' THEN 1 ELSE 0 END) as successCount,
                AVG(pu.reviewScore) as avgScore
         FROM prompt p
         LEFT JOIN promptUsage pu ON pu.promptId = p.id
         WHERE 1=1"
    );

    let mut bind_values: Vec<String> = Vec::new();

    if let Some(ref at) = agent_type {
        sql.push_str(&format!(" AND pu.agentType = ?{}", bind_values.len() + 1));
        bind_values.push(at.clone());
    }
    if let Some(ref cat) = category {
        sql.push_str(&format!(" AND p.category = ?{}", bind_values.len() + 1));
        bind_values.push(cat.clone());
    }

    sql.push_str(" GROUP BY p.id HAVING totalUses > 0 ORDER BY (successCount * 1.0 / totalUses) DESC, totalUses DESC");
    sql.push_str(&format!(" LIMIT {}", limit));

    let mut stmt = db.conn.prepare(&sql).map_err(|e| e.to_string())?;

    let params_refs: Vec<&dyn rusqlite::types::ToSql> = bind_values
        .iter()
        .map(|s| s as &dyn rusqlite::types::ToSql)
        .collect();

    let rows = stmt.query_map(params_refs.as_slice(), |row| {
        let total: i64 = row.get("totalUses")?;
        let success: i64 = row.get("successCount")?;
        Ok(PromptRecommendation {
            prompt_id: row.get("id")?,
            prompt_title: row.get("title")?,
            category: row.get("category")?,
            success_rate: if total > 0 { success as f64 / total as f64 * 100.0 } else { 0.0 },
            total_uses: total,
            avg_review_score: row.get("avgScore")?,
        })
    }).map_err(|e| e.to_string())?;

    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}
