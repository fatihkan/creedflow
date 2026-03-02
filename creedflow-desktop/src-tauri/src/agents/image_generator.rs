use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct ImageGeneratorAgent;

impl Agent for ImageGeneratorAgent {
    fn agent_type(&self) -> AgentType { AgentType::ImageGenerator }

    fn system_prompt(&self) -> &str {
        "You are an AI image generator. Create images using available MCP tools (DALL-E, Stability AI, Replicate, Leonardo.AI). Replicate supports FLUX, SDXL, and other models. Leonardo.AI provides style control and motion. Output structured JSON: {\"assets\": [{\"name\": \"\", \"type\": \"image\", \"description\": \"\", \"sourceUrl\": \"\"}]}"
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudePreferred
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["dalle".to_string(), "stability".to_string(), "replicate".to_string(), "leonardo".to_string(), "creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 5.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        format!(
            "Generate images for:\n\nTitle: {}\n\nDescription: {}\n\nOutput JSON with assets array.",
            task.title, task.description
        )
    }
}
