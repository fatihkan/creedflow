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
    ])
}
