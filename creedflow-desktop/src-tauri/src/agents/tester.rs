use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct TesterAgent;

impl Agent for TesterAgent {
    fn agent_type(&self) -> AgentType { AgentType::Tester }

    fn system_prompt(&self) -> &str {
        "You are a QA engineer. Run the project's test suite, analyze results, and report any failures. Write additional tests if needed."
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudeOnly
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["creedflow".to_string()])
    }

    fn allowed_tools(&self) -> Option<Vec<String>> {
        Some(vec!["Bash".to_string(), "Read".to_string(), "Glob".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 3.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Run tests for the following task:\n\nTitle: {}\n\nDescription: {}",
            task.title, task.description
        )
    }
}
