pub mod commands;
pub mod db;
pub mod state;
pub mod engine;
pub mod backends;
pub mod agents;
pub mod services;
pub mod util;

use state::AppState;
use std::sync::Arc;
use tauri::Manager;
use tokio::sync::Mutex;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    env_logger::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let app_handle = app.handle().clone();
            let db = db::Database::open(&db::default_db_path())?;
            db.run_migrations()?;

            let state = AppState {
                db: Arc::new(Mutex::new(db)),
                app_handle: app_handle.clone(),
            };
            app.manage(state);

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Projects
            commands::projects::list_projects,
            commands::projects::get_project,
            commands::projects::create_project,
            commands::projects::update_project,
            commands::projects::delete_project,
            // Tasks
            commands::tasks::list_tasks,
            commands::tasks::get_task,
            commands::tasks::create_task,
            commands::tasks::update_task_status,
            commands::tasks::get_task_dependencies,
            commands::tasks::archive_tasks,
            commands::tasks::restore_tasks,
            commands::tasks::permanently_delete_tasks,
            commands::tasks::list_archived_tasks,
            commands::tasks::retry_task_with_revision,
            // Backends
            commands::backends::list_backends,
            commands::backends::check_backend,
            commands::backends::toggle_backend,
            commands::backends::detect_dependencies,
            commands::backends::install_dependency,
            // Settings
            commands::settings::get_settings,
            commands::settings::update_settings,
            commands::settings::open_stripe_checkout,
            // Costs
            commands::costs::get_cost_summary,
            commands::costs::get_costs_by_project,
            // Reviews
            commands::reviews::list_reviews,
            commands::reviews::approve_review,
            commands::reviews::reject_review,
            commands::reviews::list_reviews_for_task,
            commands::reviews::get_pending_review_count,
            // Agents
            commands::agents::list_agent_types,
            commands::agents::get_agent_backend_info,
            // Assets
            commands::assets::list_assets,
            // Publishing
            commands::publishing::list_channels,
            commands::publishing::list_publications,
            // Deploy
            commands::deploy::list_deployments,
            commands::deploy::create_deployment,
            commands::deploy::get_deployment,
            commands::deploy::delete_deployments,
            // Prompts
            commands::prompts::list_prompts,
            commands::prompts::create_prompt,
            commands::prompts::delete_prompt,
            commands::prompts::toggle_favorite,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                let state = window.state::<AppState>();
                let tracker = &services::process_tracker::PROCESS_TRACKER;
                tracker.terminate_all();
                log::info!("All child processes terminated on window close");
                let _ = state;
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running CreedFlow");
}
