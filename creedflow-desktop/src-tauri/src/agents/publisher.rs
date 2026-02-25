use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct PublisherAgent;

impl Agent for PublisherAgent {
    fn agent_type(&self) -> AgentType { AgentType::Publisher }

    fn system_prompt(&self) -> &str {
        "You are a content publisher. Distribute content to publishing channels (Medium, WordPress, Twitter, LinkedIn). Output structured JSON: {\"publications\": [{\"channelType\": \"\", \"title\": \"\", \"content\": \"\", \"tags\": []}]}"
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudePreferred
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 2.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Publish content:\n\nTitle: {}\n\nDescription: {}",
            task.title, task.description
        )
    }
}
