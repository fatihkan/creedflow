use crate::db::models::AppSettings;
use crate::state::AppState;
use std::fs;
use std::path::PathBuf;
use tauri::{Manager, State};

fn settings_path(app_handle: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| format!("Failed to get app data dir: {}", e))?;
    fs::create_dir_all(&dir).map_err(|e| format!("Failed to create app data dir: {}", e))?;
    Ok(dir.join("settings.json"))
}

#[tauri::command]
pub async fn get_settings(state: State<'_, AppState>) -> Result<AppSettings, String> {
    let path = settings_path(&state.app_handle)?;
    if path.exists() {
        let contents = fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read settings: {}", e))?;
        serde_json::from_str(&contents)
            .map_err(|e| format!("Failed to parse settings: {}", e))
    } else {
        let defaults = AppSettings::default();
        let json = serde_json::to_string_pretty(&defaults)
            .map_err(|e| format!("Failed to serialize settings: {}", e))?;
        fs::write(&path, &json)
            .map_err(|e| format!("Failed to write default settings: {}", e))?;
        Ok(defaults)
    }
}

#[tauri::command]
pub async fn update_settings(
    state: State<'_, AppState>,
    settings: AppSettings,
) -> Result<(), String> {
    let path = settings_path(&state.app_handle)?;
    let tmp_path = path.with_extension("json.tmp");
    let json = serde_json::to_string_pretty(&settings)
        .map_err(|e| format!("Failed to serialize settings: {}", e))?;
    fs::write(&tmp_path, &json)
        .map_err(|e| format!("Failed to write temp settings: {}", e))?;
    fs::rename(&tmp_path, &path)
        .map_err(|e| format!("Failed to rename settings file: {}", e))?;
    log::info!("Settings updated: projects_dir={}", settings.projects_dir);
    Ok(())
}

#[tauri::command]
pub async fn open_stripe_checkout(plan: String) -> Result<(), String> {
    let url = match plan.as_str() {
        "monthly" => "https://creedflow.com/checkout?plan=monthly",
        "yearly" => "https://creedflow.com/checkout?plan=yearly",
        _ => return Err(format!("Unknown plan: {}", plan)),
    };
    open::that(url).map_err(|e| format!("Failed to open browser: {}", e))?;
    Ok(())
}
