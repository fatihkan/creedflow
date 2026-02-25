use crate::db::models::AppSettings;

#[tauri::command]
pub async fn get_settings() -> Result<AppSettings, String> {
    // TODO: Load from persistent config file
    Ok(AppSettings::default())
}

#[tauri::command]
pub async fn update_settings(settings: AppSettings) -> Result<(), String> {
    // TODO: Save to persistent config file
    log::info!("Settings updated: projects_dir={}", settings.projects_dir);
    Ok(())
}
