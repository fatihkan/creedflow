use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct DesignerAgent;

impl Agent for DesignerAgent {
    fn agent_type(&self) -> AgentType { AgentType::Designer }

    fn system_prompt(&self) -> &str {
        "You are a UI/UX designer. Create design specs, wireframes, and visual designs. Output structured JSON: {\"assets\": [{\"name\": \"\", \"type\": \"design\", \"description\": \"\"}]}"
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudePreferred
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["figma".to_string(), "creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 3.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Design task:\n\nTitle: {}\n\nDescription: {}\n\nOutput JSON with assets array.",
            task.title, task.description
        )
    }
}
