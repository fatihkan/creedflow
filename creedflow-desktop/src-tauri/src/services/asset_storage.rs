use crate::db::Database;
use rusqlite::params;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Asset file storage — saves creative agent output files to disk and records them in DB.
pub struct AssetStorageService;

impl AssetStorageService {
    /// Save an asset file to the project's assets directory.
    pub async fn save_asset(
        project_name: &str,
        file_name: &str,
        data: &[u8],
    ) -> Result<(String, String), String> {
        let base_dir = dirs::home_dir()
            .unwrap_or_default()
            .join("CreedFlow")
            .join("projects")
            .join(project_name)
            .join("assets");

        std::fs::create_dir_all(&base_dir)
            .map_err(|e| format!("Failed to create assets dir: {}", e))?;

        let file_path = base_dir.join(file_name);
        std::fs::write(&file_path, data)
            .map_err(|e| format!("Failed to write asset: {}", e))?;

        // Calculate SHA256 checksum
        let checksum = hex::encode(Sha256::digest(data));

        Ok((
            file_path.to_string_lossy().to_string(),
            checksum,
        ))
    }

    /// Save asset metadata to the database.
    pub async fn record_asset(
        db: &Arc<Mutex<Database>>,
        id: &str,
        project_id: &str,
        task_id: &str,
        agent_type: &str,
        asset_type: &str,
        name: &str,
        description: &str,
        file_path: &str,
        mime_type: Option<&str>,
        file_size: Option<i64>,
        checksum: Option<&str>,
        parent_asset_id: Option<&str>,
    ) -> Result<(), String> {
        let db_lock = db.lock().await;

        // Determine version number
        let version: i32 = if let Some(parent_id) = parent_asset_id {
            let parent_version: i32 = db_lock
                .conn
                .query_row(
                    "SELECT version FROM generatedAsset WHERE id = ?1",
                    [parent_id],
                    |row| row.get(0),
                )
                .unwrap_or(0);
            parent_version + 1
        } else {
            1
        };

        db_lock
            .conn
            .execute(
                "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, fileSize, status, version, checksum, parentAssetId, createdAt, updatedAt)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'generated', ?11, ?12, ?13, datetime('now'), datetime('now'))",
                params![
                    id, project_id, task_id, agent_type, asset_type, name,
                    description, file_path, mime_type, file_size, version,
                    checksum, parent_asset_id,
                ],
            )
            .map_err(|e| format!("Failed to record asset: {}", e))?;

        Ok(())
    }

    /// Get the assets directory for a project.
    pub fn assets_dir(project_name: &str) -> PathBuf {
        dirs::home_dir()
            .unwrap_or_default()
            .join("CreedFlow")
            .join("projects")
            .join(project_name)
            .join("assets")
    }
}
