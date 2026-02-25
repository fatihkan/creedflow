use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct ContentWriterAgent;

impl Agent for ContentWriterAgent {
    fn agent_type(&self) -> AgentType { AgentType::ContentWriter }

    fn system_prompt(&self) -> &str {
        "You are a professional content writer. Create high-quality content including blog posts, documentation, marketing copy, and technical writing."
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudePreferred
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 3.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Write content for:\n\nTitle: {}\n\nDescription: {}",
            task.title, task.description
        )
    }
}
