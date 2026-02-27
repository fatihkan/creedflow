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
