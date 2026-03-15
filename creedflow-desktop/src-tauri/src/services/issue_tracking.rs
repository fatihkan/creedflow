use crate::db::models::{IssueMapping, IssueTrackingConfig};
use rusqlite::Connection;

/// Stub Linear service for the desktop app.
/// Full GraphQL implementation is in the Swift native app;
/// this provides basic CRUD scaffolding for the Tauri frontend.
pub struct LinearService;

impl LinearService {
    pub fn import_issues(
        _conn: &Connection,
        _config: &IssueTrackingConfig,
    ) -> Result<Vec<IssueMapping>, String> {
        // TODO: Implement Linear GraphQL import (mirrors Swift LinearSyncService)
        // For now, return empty — the Swift app has the full implementation.
        Ok(vec![])
    }
}

/// Stub Jira service — not yet implemented.
pub struct JiraService;

impl JiraService {
    pub fn import_issues(
        _conn: &Connection,
        _config: &IssueTrackingConfig,
    ) -> Result<Vec<IssueMapping>, String> {
        Err("Jira integration is not yet implemented".to_string())
    }
}
