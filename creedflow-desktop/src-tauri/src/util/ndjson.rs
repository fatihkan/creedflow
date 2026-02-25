/// NDJSON stream parser — buffers partial JSON lines across pipe chunks.
/// Mirrors Swift NDJSONParser.
pub struct NDJSONParser {
    buffer: String,
}

impl NDJSONParser {
    pub fn new() -> Self {
        Self {
            buffer: String::new(),
        }
    }

    /// Feed a chunk of data and return any complete JSON lines.
    pub fn feed(&mut self, chunk: &str) -> Vec<serde_json::Value> {
        self.buffer.push_str(chunk);
        let mut results = Vec::new();

        while let Some(newline_pos) = self.buffer.find('\n') {
            let line: String = self.buffer.drain(..=newline_pos).collect();
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            match serde_json::from_str::<serde_json::Value>(trimmed) {
                Ok(value) => results.push(value),
                Err(_) => {
                    // Not valid JSON — could be partial, skip
                    log::debug!("Skipping non-JSON line: {}", trimmed);
                }
            }
        }

        results
    }

    /// Flush any remaining data in the buffer.
    pub fn flush(&mut self) -> Option<serde_json::Value> {
        let trimmed = self.buffer.trim().to_string();
        self.buffer.clear();
        if trimmed.is_empty() {
            return None;
        }
        serde_json::from_str(&trimmed).ok()
    }
}

/// Strip ANSI escape codes from CLI output.
pub fn strip_ansi(input: &str) -> String {
    let re = regex::Regex::new(r"\x1b\[[0-9;]*[a-zA-Z]").unwrap();
    re.replace_all(input, "").to_string()
}

/// Extract JSON from text that may contain markdown code blocks or other wrapping.
pub fn extract_json(text: &str) -> Option<serde_json::Value> {
    let cleaned = strip_ansi(text);

    // Try direct parse
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&cleaned) {
        return Some(v);
    }

    // Try extracting from markdown code blocks
    let patterns = ["```json\n", "```\n"];
    for pattern in &patterns {
        if let Some(start) = cleaned.find(pattern) {
            let content_start = start + pattern.len();
            if let Some(end) = cleaned[content_start..].find("```") {
                let json_str = &cleaned[content_start..content_start + end];
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(json_str.trim()) {
                    return Some(v);
                }
            }
        }
    }

    // Try finding first { ... } or [ ... ]
    if let Some(start) = cleaned.find('{') {
        if let Some(end) = cleaned.rfind('}') {
            let json_str = &cleaned[start..=end];
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(json_str) {
                return Some(v);
            }
        }
    }

    if let Some(start) = cleaned.find('[') {
        if let Some(end) = cleaned.rfind(']') {
            let json_str = &cleaned[start..=end];
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(json_str) {
                return Some(v);
            }
        }
    }

    None
}
