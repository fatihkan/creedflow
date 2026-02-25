use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct AnalyzerAgent;

impl Agent for AnalyzerAgent {
    fn agent_type(&self) -> AgentType { AgentType::Analyzer }

    fn system_prompt(&self) -> &str {
        "You are a senior software architect. Analyze the project description and decompose it into features and tasks. Output valid JSON with this structure: {\"features\": [{\"name\": \"\", \"description\": \"\", \"priority\": 0, \"tasks\": [{\"title\": \"\", \"description\": \"\", \"agentType\": \"\", \"priority\": 0, \"dependencies\": []}]}]}"
    }

    fn timeout_seconds(&self) -> i32 { 300 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::AnyBackend
    }

    fn max_budget_usd(&self) -> f64 { 2.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Analyze the following project and decompose it into features and actionable tasks.\n\n\
             Project: {}\n\nDescription: {}\n\n\
             Available agent types: analyzer, coder, reviewer, tester, devops, monitor, contentWriter, designer, imageGenerator, videoEditor, publisher.\n\n\
             Return JSON only.",
            task.title, task.description
        )
    }
}
