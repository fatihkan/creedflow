use serde::Serialize;
use tauri::State;
use crate::state::AppState;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    pub latest_version: String,
    pub current_version: String,
    pub release_url: String,
    pub release_notes: String,
}

#[tauri::command]
pub async fn check_for_updates(
    _state: State<'_, AppState>,
) -> Result<Option<UpdateInfo>, String> {
    let current = env!("CARGO_PKG_VERSION");

    let client = reqwest::Client::builder()
        .user_agent("CreedFlow-Desktop")
        .build()
        .map_err(|e| e.to_string())?;

    let resp = client
        .get("https://api.github.com/repos/fatihkan/creedflow/releases/latest")
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !resp.status().is_success() {
        // Fail silently — no update info
        return Ok(None);
    }

    let json: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;

    let tag = json["tag_name"]
        .as_str()
        .unwrap_or("")
        .trim_start_matches('v');

    if tag.is_empty() {
        return Ok(None);
    }

    // Simple semver comparison
    if is_newer(tag, current) {
        let release_url = json["html_url"]
            .as_str()
            .unwrap_or("https://github.com/fatihkan/creedflow/releases")
            .to_string();

        let release_notes = json["body"]
            .as_str()
            .unwrap_or("")
            .chars()
            .take(500)
            .collect::<String>();

        Ok(Some(UpdateInfo {
            latest_version: tag.to_string(),
            current_version: current.to_string(),
            release_url,
            release_notes,
        }))
    } else {
        Ok(None)
    }
}

fn is_newer(latest: &str, current: &str) -> bool {
    let parse = |v: &str| -> Vec<u32> {
        v.split('.')
            .filter_map(|s| s.parse().ok())
            .collect()
    };
    let l = parse(latest);
    let c = parse(current);
    for i in 0..3 {
        let lv = l.get(i).copied().unwrap_or(0);
        let cv = c.get(i).copied().unwrap_or(0);
        if lv > cv {
            return true;
        }
        if lv < cv {
            return false;
        }
    }
    false
}
