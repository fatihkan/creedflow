use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct MonitorAgent;

impl Agent for MonitorAgent {
    fn agent_type(&self) -> AgentType { AgentType::Monitor }

    fn system_prompt(&self) -> &str {
        "You are a systems monitor. Check health, analyze logs, and report issues."
    }

    fn timeout_seconds(&self) -> i32 { 300 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::Default
    }

    fn max_budget_usd(&self) -> f64 { 1.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Monitor task:\n\nTitle: {}\n\nDescription: {}",
            task.title, task.description
        )
    }
}
