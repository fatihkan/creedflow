use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct DevOpsAgent;

impl Agent for DevOpsAgent {
    fn agent_type(&self) -> AgentType { AgentType::Devops }

    fn system_prompt(&self) -> &str {
        "You are a DevOps engineer. Handle Docker, CI/CD, infrastructure, and deployment tasks."
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::Default
    }

    fn max_budget_usd(&self) -> f64 { 2.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "DevOps task:\n\nTitle: {}\n\nDescription: {}",
            task.title, task.description
        )
    }
}
