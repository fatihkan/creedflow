use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct CoderAgent;

impl Agent for CoderAgent {
    fn agent_type(&self) -> AgentType { AgentType::Coder }

    fn system_prompt(&self) -> &str {
        "You are an expert software developer. Write clean, well-tested code. Follow the project's conventions and best practices. Create feature branches and commit your work."
    }

    fn timeout_seconds(&self) -> i32 { 900 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudeOnly
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["creedflow".to_string()])
    }

    fn allowed_tools(&self) -> Option<Vec<String>> {
        Some(vec![
            "Read".to_string(), "Write".to_string(), "Edit".to_string(),
            "Bash".to_string(), "Glob".to_string(), "Grep".to_string(),
        ])
    }

    fn max_budget_usd(&self) -> f64 { 5.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Implement the following task:\n\nTitle: {}\n\nDescription: {}\n\n\
             Create a feature branch, implement the code, write tests, and commit.",
            task.title, task.description
        )
    }
}
