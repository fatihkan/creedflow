use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentTypeInfo {
    pub agent_type: String,
    pub display_name: String,
    pub timeout_seconds: i32,
    pub backend_preference: String,
    pub has_mcp: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentBackendInfo {
    pub agent_type: String,
    pub default_preference: String,
    pub allowed_backends: Vec<String>,
}

#[tauri::command]
pub async fn list_agent_types() -> Result<Vec<AgentTypeInfo>, String> {
    Ok(vec![
        AgentTypeInfo { agent_type: "analyzer".into(), display_name: "Analyzer".into(), timeout_seconds: 300, backend_preference: "anyBackend".into(), has_mcp: false },
        AgentTypeInfo { agent_type: "coder".into(), display_name: "Coder".into(), timeout_seconds: 900, backend_preference: "claudeOnly".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "reviewer".into(), display_name: "Reviewer".into(), timeout_seconds: 300, backend_preference: "claudeOnly".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "tester".into(), display_name: "Tester".into(), timeout_seconds: 600, backend_preference: "claudeOnly".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "devops".into(), display_name: "DevOps".into(), timeout_seconds: 600, backend_preference: "default".into(), has_mcp: false },
        AgentTypeInfo { agent_type: "monitor".into(), display_name: "Monitor".into(), timeout_seconds: 300, backend_preference: "default".into(), has_mcp: false },
        AgentTypeInfo { agent_type: "contentWriter".into(), display_name: "Content Writer".into(), timeout_seconds: 600, backend_preference: "claudePreferred".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "designer".into(), display_name: "Designer".into(), timeout_seconds: 600, backend_preference: "claudePreferred".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "imageGenerator".into(), display_name: "Image Generator".into(), timeout_seconds: 600, backend_preference: "claudePreferred".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "videoEditor".into(), display_name: "Video Editor".into(), timeout_seconds: 900, backend_preference: "claudePreferred".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "publisher".into(), display_name: "Publisher".into(), timeout_seconds: 600, backend_preference: "claudePreferred".into(), has_mcp: true },
        AgentTypeInfo { agent_type: "planner".into(), display_name: "Planner".into(), timeout_seconds: 300, backend_preference: "anyBackend".into(), has_mcp: false },
    ])
}

#[tauri::command]
pub async fn get_agent_backend_info() -> Result<Vec<AgentBackendInfo>, String> {
    let all_backends = vec!["claude", "codex", "gemini", "ollama", "lmStudio", "llamaCpp", "mlx"];
    let cloud_backends = vec!["claude", "codex", "gemini"];
    let claude_only = vec!["claude"];

    Ok(vec![
        AgentBackendInfo { agent_type: "analyzer".into(), default_preference: "anyBackend".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "coder".into(), default_preference: "claudeOnly".into(), allowed_backends: claude_only.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "reviewer".into(), default_preference: "claudeOnly".into(), allowed_backends: claude_only.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "tester".into(), default_preference: "claudeOnly".into(), allowed_backends: claude_only.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "devops".into(), default_preference: "default".into(), allowed_backends: cloud_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "monitor".into(), default_preference: "default".into(), allowed_backends: cloud_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "contentWriter".into(), default_preference: "claudePreferred".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "designer".into(), default_preference: "claudePreferred".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "imageGenerator".into(), default_preference: "claudePreferred".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "videoEditor".into(), default_preference: "claudePreferred".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "publisher".into(), default_preference: "claudePreferred".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
        AgentBackendInfo { agent_type: "planner".into(), default_preference: "anyBackend".into(), allowed_backends: all_backends.iter().map(|s| s.to_string()).collect() },
    ])
}
