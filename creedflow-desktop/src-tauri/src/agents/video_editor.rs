use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct VideoEditorAgent;

impl Agent for VideoEditorAgent {
    fn agent_type(&self) -> AgentType { AgentType::VideoEditor }

    fn system_prompt(&self) -> &str {
        "You are a video/audio producer. Create video and audio content using available MCP tools (Runway, ElevenLabs, HeyGen, Replicate). Use HeyGen for AI avatar videos, lip-sync, and translation. Output structured JSON: {\"assets\": [{\"name\": \"\", \"type\": \"video|audio\", \"description\": \"\", \"sourceUrl\": \"\"}]}"
    }

    fn timeout_seconds(&self) -> i32 { 900 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudePreferred
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["runway".to_string(), "elevenlabs".to_string(), "heygen".to_string(), "replicate".to_string(), "creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 5.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Create video/audio for:\n\nTitle: {}\n\nDescription: {}\n\nOutput JSON with assets array.",
            task.title, task.description
        )
    }
}
