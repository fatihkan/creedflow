use crate::db::Database;
use crate::db::models::GeneratedAsset;
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tokio::sync::Mutex;

/// Asset versioning — manages version chains via parentAssetId linked list.
pub struct AssetVersioningService;

impl AssetVersioningService {
    /// Get the full version history for an asset (newest first).
    pub async fn get_version_chain(
        db: &Arc<Mutex<Database>>,
        asset_id: &str,
    ) -> Result<Vec<GeneratedAsset>, String> {
        let db_lock = db.lock().await;

        // Find the root asset (no parent)
        let mut root_id = asset_id.to_string();
        loop {
            let parent: Option<String> = db_lock
                .conn
                .query_row(
                    "SELECT parentAssetId FROM generatedAsset WHERE id = ?1",
                    [&root_id],
                    |row| row.get(0),
                )
                .ok()
                .flatten();

            match parent {
                Some(pid) => root_id = pid,
                None => break,
            }
        }

        // Walk the chain from root forward
        let mut chain = Vec::new();
        let mut current_id = Some(root_id);

        while let Some(id) = current_id {
            let asset: Option<GeneratedAsset> = db_lock
                .conn
                .query_row(
                    "SELECT * FROM generatedAsset WHERE id = ?1",
                    [&id],
                    |row| GeneratedAsset::from_row(row),
                )
                .ok();

            match asset {
                Some(a) => {
                    let next_id = db_lock
                        .conn
                        .query_row(
                            "SELECT id FROM generatedAsset WHERE parentAssetId = ?1",
                            [&a.id],
                            |row| row.get::<_, String>(0),
                        )
                        .ok();
                    chain.push(a);
                    current_id = next_id;
                }
                None => break,
            }
        }

        // Reverse so newest is first
        chain.reverse();
        Ok(chain)
    }

    /// Compute SHA256 checksum for a file.
    pub fn compute_checksum(data: &[u8]) -> String {
        hex::encode(Sha256::digest(data))
    }

    /// Verify a file's integrity against its stored checksum.
    pub async fn verify_integrity(
        db: &Arc<Mutex<Database>>,
        asset_id: &str,
    ) -> Result<bool, String> {
        let (file_path, stored_checksum) = {
            let db_lock = db.lock().await;
            let row: (String, Option<String>) = db_lock
                .conn
                .query_row(
                    "SELECT filePath, checksum FROM generatedAsset WHERE id = ?1",
                    [asset_id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .map_err(|e| format!("Asset not found: {}", e))?;
            row
        };

        let stored = match stored_checksum {
            Some(c) => c,
            None => return Ok(true), // No checksum stored — skip verification
        };

        let data = std::fs::read(&file_path)
            .map_err(|e| format!("Failed to read file: {}", e))?;
        let actual = Self::compute_checksum(&data);

        Ok(actual == stored)
    }

    /// Get the latest version of an asset (follows the chain to the end).
    pub async fn get_latest_version(
        db: &Arc<Mutex<Database>>,
        asset_id: &str,
    ) -> Result<GeneratedAsset, String> {
        let chain = Self::get_version_chain(db, asset_id).await?;
        chain
            .into_iter()
            .next() // First element is newest (chain is reversed)
            .ok_or_else(|| "Asset not found".to_string())
    }
}
