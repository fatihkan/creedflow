use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct ReviewerAgent;

impl Agent for ReviewerAgent {
    fn agent_type(&self) -> AgentType { AgentType::Reviewer }

    fn system_prompt(&self) -> &str {
        "You are a senior code reviewer. Review the code changes thoroughly for correctness, security, performance, and best practices. Return JSON: {\"score\": 0.0, \"verdict\": \"pass|needsRevision|fail\", \"summary\": \"\", \"issues\": \"\", \"suggestions\": \"\", \"securityNotes\": \"\"}"
    }

    fn timeout_seconds(&self) -> i32 { 300 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudeOnly
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 2.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Review the code for the following task:\n\nTitle: {}\n\nDescription: {}\n\n\
             Score from 0-10 (>=7.0 PASS, 5.0-6.9 NEEDS_REVISION, <5.0 FAIL). Return JSON only.",
            task.title, task.description
        )
    }
}
