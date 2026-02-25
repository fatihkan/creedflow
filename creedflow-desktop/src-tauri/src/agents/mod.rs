pub mod analyzer;
pub mod coder;
pub mod reviewer;
pub mod tester;
pub mod devops;
pub mod monitor;
pub mod content_writer;
pub mod designer;
pub mod image_generator;
pub mod video_editor;
pub mod publisher;

use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

/// Agent trait — mirrors Swift AgentProtocol.
pub trait Agent: Send + Sync {
    fn agent_type(&self) -> AgentType;
    fn system_prompt(&self) -> &str;
    fn timeout_seconds(&self) -> i32;
    fn backend_preferences(&self) -> BackendPreferences;
    fn mcp_servers(&self) -> Option<Vec<String>> { None }
    fn allowed_tools(&self) -> Option<Vec<String>> { None }
    fn max_budget_usd(&self) -> f64 { 1.0 }
    fn build_prompt(&self, task: &AgentTask) -> String;
}

/// Resolve an AgentType to its implementation.
pub fn resolve_agent(agent_type: &AgentType) -> Box<dyn Agent> {
    match agent_type {
        AgentType::Analyzer => Box::new(analyzer::AnalyzerAgent),
        AgentType::Coder => Box::new(coder::CoderAgent),
        AgentType::Reviewer => Box::new(reviewer::ReviewerAgent),
        AgentType::Tester => Box::new(tester::TesterAgent),
        AgentType::Devops => Box::new(devops::DevOpsAgent),
        AgentType::Monitor => Box::new(monitor::MonitorAgent),
        AgentType::ContentWriter => Box::new(content_writer::ContentWriterAgent),
        AgentType::Designer => Box::new(designer::DesignerAgent),
        AgentType::ImageGenerator => Box::new(image_generator::ImageGeneratorAgent),
        AgentType::VideoEditor => Box::new(video_editor::VideoEditorAgent),
        AgentType::Publisher => Box::new(publisher::PublisherAgent),
    }
}
