use serde_json::json;
use std::path::PathBuf;

/// Generates temporary MCP config JSON files for agents that declare mcpServers
pub struct MCPConfigGenerator;

impl MCPConfigGenerator {
    pub fn generate(
        server_names: &[&str],
        temp_dir: &PathBuf,
    ) -> Result<PathBuf, String> {
        let mut servers = serde_json::Map::new();

        for name in server_names {
            let config = match *name {
                "creedflow" => json!({
                    "command": "creedflow-mcp-server",
                    "args": ["--stdio"],
                }),
                "dalle" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-dalle"],
                }),
                "figma" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-figma"],
                }),
                "stability" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-stability"],
                }),
                "elevenlabs" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-elevenlabs"],
                }),
                "runway" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-runway"],
                }),
                "heygen" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-heygen"],
                }),
                "replicate" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-replicate"],
                }),
                "leonardo" => json!({
                    "command": "npx",
                    "args": ["-y", "@anthropic/mcp-leonardo"],
                }),
                _ => continue,
            };
            servers.insert(name.to_string(), config);
        }

        let config = json!({ "mcpServers": servers });
        let path = temp_dir.join(format!("creedflow-mcp-{}.json", uuid::Uuid::new_v4()));

        std::fs::create_dir_all(temp_dir).map_err(|e| e.to_string())?;
        std::fs::write(&path, serde_json::to_string_pretty(&config).unwrap())
            .map_err(|e| e.to_string())?;

        Ok(path)
    }
}
