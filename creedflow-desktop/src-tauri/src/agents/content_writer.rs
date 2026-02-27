use super::Agent;
use crate::backends::BackendPreferences;
use crate::db::models::{AgentTask, AgentType};

pub struct ContentWriterAgent;

impl Agent for ContentWriterAgent {
    fn agent_type(&self) -> AgentType { AgentType::ContentWriter }

    fn system_prompt(&self) -> &str {
        "You are an expert content writer. Your job is to create high-quality written content \
based on the given brief.\n\n\
You have access to the CreedFlow project state via MCP when configured, which lets \
you query project details and task context for more informed writing.\n\n\
Rules:\n\
- Produce clear, engaging, well-structured text\n\
- Match the requested tone and style (formal, casual, technical, etc.)\n\
- Include proper headings, sections, and formatting\n\
- Research the topic thoroughly before writing\n\
- Cite sources when making factual claims\n\
- Optimize for readability and audience engagement\n\
- Where an image would enhance the content, insert a placeholder: \
![description](creedflow:image:kebab-case-slug) — these will be replaced with generated images\n\n\
OUTPUT FORMAT — PREFERRED (JSON):\n\
Output your final result as a JSON object. No markdown fences, no explanation outside the JSON:\n\n\
{\n  \"assets\": [\n    {\n      \"type\": \"document\",\n      \"name\": \"kebab-case-title.md\",\n      \
\"content\": \"# Full Markdown Content\\n\\nYour complete article here...\"\n    }\n  ]\n}\n\n\
ALTERNATIVE FORMAT (YAML front matter + Markdown):\n\
If JSON output is difficult, you may use YAML front matter followed by Markdown:\n\n\
---\ntitle: \"Your Article Title\"\nname: \"kebab-case-title.md\"\ntags: [\"tag1\", \"tag2\"]\n\
summary: \"A brief summary of the article\"\n---\n\n# Full Markdown Content\n\n\
Your complete article here...\n\n\
LAST RESORT:\n\
If neither JSON nor YAML front matter is possible, output plain Markdown directly. \
The system will automatically wrap it as a document asset.\n\n\
Rules for JSON output:\n\
- \"type\" MUST be \"document\"\n\
- \"name\" MUST be kebab-case with .md extension (e.g. \"seo-guide-2026.md\")\n\
- \"content\" MUST contain the FULL text in Markdown format, not a summary or excerpt\n\
- For multi-part content (e.g. a blog series), include multiple items in the assets array\n\
- Each asset must be a complete, standalone piece of content\n\
- Do NOT wrap the JSON in markdown code fences"
    }

    fn timeout_seconds(&self) -> i32 { 600 }

    fn backend_preferences(&self) -> BackendPreferences {
        BackendPreferences::ClaudePreferred
    }

    fn mcp_servers(&self) -> Option<Vec<String>> {
        Some(vec!["creedflow".to_string()])
    }

    fn max_budget_usd(&self) -> f64 { 3.0 }

    fn build_prompt(&self, task: &AgentTask) -> String {
        let sanitized = sanitize_title(&task.title);
        format!(
            "Write the following content:\n\n\
            Title: {}\n\n\
            Brief: {}\n\n\
            Produce polished, publication-ready content. Write the FULL article — not an outline or summary.\n\
            Where images would enhance the content, insert: ![description](creedflow:image:slug)\n\n\
            PREFERRED — respond with JSON:\n\
            {{\n  \"assets\": [\n    {{\n      \"type\": \"document\",\n      \"name\": \"{sanitized}.md\",\n      \
            \"content\": \"# Your Title\\n\\nFull markdown content here...\"\n    }}\n  ]\n}}\n\n\
            ALTERNATIVE — respond with YAML front matter + Markdown:\n\
            ---\ntitle: \"{}\"\nname: \"{sanitized}.md\"\n---\n# Your Title\n\nFull markdown content here...",
            task.title, task.description, task.title,
        )
    }
}

fn sanitize_title(title: &str) -> String {
    title
        .to_lowercase()
        .replace(' ', "-")
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .take(50)
        .collect()
}
