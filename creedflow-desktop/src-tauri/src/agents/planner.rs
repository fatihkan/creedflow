use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct PlannerAgent;

impl Agent for PlannerAgent {
    fn agent_type(&self) -> AgentType { AgentType::Planner }

    fn system_prompt(&self) -> &str {
        "You are a senior project planner and strategist. You create detailed project plans, \
         sprint breakdowns, timelines, milestones, dependency graphs, risk analyses, and roadmaps. \
         You focus on actionable planning — not code architecture or technical analysis. \
         Your output is structured markdown with clear phases, deliverables, and timelines."
    }

    fn timeout_seconds(&self) -> i32 { 300 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::AnyBackend
    }

    fn max_budget_usd(&self) -> f64 { 1.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        let desc = &task.description;

        if desc.starts_with("[SPRINT]") || desc.contains("[SPRINT]") {
            let clean = desc.replace("[SPRINT]", "").trim().to_string();
            format!(
                "Create a SPRINT PLAN for the following project/feature.\n\n\
                 Include:\n\
                 - Sprint goals and scope\n\
                 - Task breakdown with story points or estimated hours\n\
                 - Task prioritization (P0/P1/P2)\n\
                 - Sprint capacity and velocity assumptions\n\
                 - Dependencies between tasks\n\
                 - Acceptance criteria for sprint completion\n\
                 - Risk factors and mitigation\n\n\
                 Format as structured markdown with tables where appropriate.\n\n\
                 Title: {}\n\nDescription: {}",
                task.title, clean
            )
        } else if desc.starts_with("[ROADMAP]") || desc.contains("[ROADMAP]") {
            let clean = desc.replace("[ROADMAP]", "").trim().to_string();
            format!(
                "Create a PROJECT ROADMAP for the following project.\n\n\
                 Include:\n\
                 - Executive summary\n\
                 - Project phases with timelines (Phase 1, 2, 3...)\n\
                 - Key milestones and deliverables per phase\n\
                 - Resource requirements and team allocation\n\
                 - Risk analysis with probability and impact\n\
                 - Alternative approaches and trade-offs\n\
                 - Success metrics and KPIs\n\
                 - Dependencies and critical path\n\n\
                 Format as structured markdown with Mermaid Gantt chart if applicable.\n\n\
                 Title: {}\n\nDescription: {}",
                task.title, clean
            )
        } else {
            format!(
                "Create a detailed TASK PLAN for the following work.\n\n\
                 Include:\n\
                 - Objective and scope\n\
                 - Step-by-step task breakdown\n\
                 - Dependencies and ordering (DAG)\n\
                 - Timeline with milestones\n\
                 - Estimated complexity per task (low/medium/high)\n\
                 - Risks and blockers\n\
                 - Definition of done\n\n\
                 Format as structured markdown.\n\n\
                 Title: {}\n\nDescription: {}",
                task.title, task.description
            )
        }
    }
}
