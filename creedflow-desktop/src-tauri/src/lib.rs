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

            let db_arc = Arc::new(Mutex::new(db));

            // Spawn webhook server if enabled in settings
            {
                let db_guard = db_arc.blocking_lock();
                let webhook_enabled: bool = db_guard.conn
                    .query_row(
                        "SELECT value FROM appSetting WHERE key = 'webhookEnabled'",
                        [],
                        |row| row.get::<_, String>(0),
                    )
                    .map(|v| v == "true" || v == "1")
                    .unwrap_or(false);

                if webhook_enabled {
                    let port: u16 = db_guard.conn
                        .query_row(
                            "SELECT value FROM appSetting WHERE key = 'webhookPort'",
                            [],
                            |row| row.get::<_, String>(0),
                        )
                        .ok()
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(8080);

                    let api_key: Option<String> = db_guard.conn
                        .query_row(
                            "SELECT value FROM appSetting WHERE key = 'webhookApiKey'",
                            [],
                            |row| row.get::<_, String>(0),
                        )
                        .ok()
                        .filter(|k| !k.is_empty());

                    let github_secret: Option<String> = db_guard.conn
                        .query_row(
                            "SELECT value FROM appSetting WHERE key = 'webhookGithubSecret'",
                            [],
                            |row| row.get::<_, String>(0),
                        )
                        .ok()
                        .filter(|k| !k.is_empty());

                    let db_clone = db_arc.clone();
                    drop(db_guard);

                    tokio::spawn(async move {
                        let server = services::webhook_server::WebhookServer::new(port, api_key, db_clone)
                            .with_github_secret(github_secret);
                        server.run().await;
                    });
                }
            }

            let state = AppState {
                db: db_arc,
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
            commands::projects::export_project_docs,
            commands::projects::get_project_time_stats,
            commands::projects::export_project_zip,
            commands::projects::export_project_bundle,
            commands::projects::import_project_bundle,
            commands::projects::list_project_templates,
            commands::projects::create_project_from_template,
            commands::projects::get_project_health,
            commands::projects::get_project_forecast,
            commands::projects::list_project_diagrams,
            commands::projects::get_diagram_content,
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
            commands::tasks::duplicate_task,
            commands::tasks::batch_retry_tasks,
            commands::tasks::batch_cancel_tasks,
            commands::tasks::add_task_comment,
            commands::tasks::list_task_comments,
            commands::tasks::get_task_graph,
            commands::tasks::get_task_prompt_history,
            // Backends
            commands::backends::list_backends,
            commands::backends::check_backend,
            commands::backends::toggle_backend,
            commands::backends::detect_dependencies,
            commands::backends::install_dependency,
            commands::backends::detect_package_manager_cmd,
            commands::backends::compare_backends,
            commands::backends::export_comparison,
            // Settings
            commands::settings::get_settings,
            commands::settings::update_settings,
            // commands::settings::open_stripe_checkout, // disabled — no payment
            // Costs
            commands::costs::get_cost_summary,
            commands::costs::get_costs_by_project,
            commands::costs::get_cost_by_agent,
            commands::costs::get_cost_by_backend,
            commands::costs::get_cost_timeline,
            commands::costs::get_task_statistics,
            commands::costs::get_backend_scores,
            commands::costs::get_cost_budgets,
            commands::costs::upsert_cost_budget,
            commands::costs::delete_cost_budget,
            commands::costs::get_budget_utilization,
            commands::costs::acknowledge_budget_alert,
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
            commands::assets::get_asset,
            commands::assets::get_asset_versions,
            commands::assets::approve_asset,
            commands::assets::delete_asset,
            // Publishing
            commands::publishing::list_channels,
            commands::publishing::list_publications,
            commands::publishing::create_channel,
            commands::publishing::update_channel,
            commands::publishing::delete_channel,
            // Deploy
            commands::deploy::list_deployments,
            commands::deploy::create_deployment,
            commands::deploy::get_deployment,
            commands::deploy::delete_deployments,
            commands::deploy::cancel_deployment,
            commands::deploy::get_deployment_logs,
            // Prompts
            commands::prompts::list_prompts,
            commands::prompts::create_prompt,
            commands::prompts::delete_prompt,
            commands::prompts::toggle_favorite,
            // Prompt Chains
            commands::prompts::list_prompt_chains,
            commands::prompts::get_prompt_chain,
            commands::prompts::create_prompt_chain,
            commands::prompts::delete_prompt_chain,
            commands::prompts::add_chain_step,
            commands::prompts::remove_chain_step,
            commands::prompts::reorder_chain_steps,
            commands::prompts::update_chain_step,
            commands::prompts::update_prompt_chain,
            // Prompt Effectiveness
            commands::prompts::get_prompt_effectiveness,
            // Prompt Import/Export
            commands::prompts::export_prompts,
            commands::prompts::import_prompts,
            // Prompt Versions & Diff
            commands::prompts::get_prompt_versions,
            commands::prompts::get_prompt_version_diff,
            // Prompt Recommender
            commands::prompts::get_prompt_recommendations,
            // Platform
            commands::platform::open_terminal,
            commands::platform::open_in_file_manager,
            commands::platform::open_url,
            commands::platform::detect_editors,
            commands::platform::open_in_editor,
            commands::platform::get_preferred_editor,
            commands::platform::set_preferred_editor,
            commands::platform::get_platform,
            // Chat
            commands::chat::send_chat_message,
            commands::chat::stream_chat_response,
            commands::chat::list_chat_messages,
            commands::chat::approve_chat_proposal,
            commands::chat::reject_chat_proposal,
            // Notifications & Health
            commands::notifications::list_notifications,
            commands::notifications::get_unread_count,
            commands::notifications::mark_notification_read,
            commands::notifications::mark_all_notifications_read,
            commands::notifications::dismiss_notification,
            commands::notifications::delete_notification,
            commands::notifications::clear_all_notifications,
            commands::notifications::get_backend_health_status,
            commands::notifications::get_mcp_health_status,
            // MCP
            commands::mcp::list_mcp_servers,
            commands::mcp::create_mcp_server,
            commands::mcp::update_mcp_server,
            commands::mcp::delete_mcp_server,
            // Git
            commands::git::git_ensure_branch_structure,
            commands::git::git_setup_feature_branch,
            commands::git::git_auto_commit,
            commands::git::git_merge_feature_to_dev,
            commands::git::git_promote_dev_to_staging,
            commands::git::git_promote_staging_to_main,
            commands::git::git_current_branch,
            commands::git::git_log,
            commands::git::get_git_config,
            commands::git::set_git_config,
            // Database Maintenance
            commands::database::get_db_info,
            commands::database::vacuum_database,
            commands::database::backup_database,
            commands::database::prune_old_logs,
            commands::database::export_database_json,
            commands::database::factory_reset_database,
            // Personas
            commands::personas::get_agent_personas,
            commands::personas::create_agent_persona,
            commands::personas::update_agent_persona,
            commands::personas::delete_agent_persona,
            // Issue Tracking
            commands::issue_tracking::list_issue_configs,
            commands::issue_tracking::create_issue_config,
            commands::issue_tracking::update_issue_config,
            commands::issue_tracking::delete_issue_config,
            commands::issue_tracking::import_issues,
            commands::issue_tracking::list_issue_mappings,
            // Automation
            commands::automation::list_automation_flows,
            commands::automation::create_automation_flow,
            commands::automation::update_automation_flow,
            commands::automation::delete_automation_flow,
            commands::automation::toggle_automation_flow,
            // Updates
            commands::updates::check_for_updates,
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
