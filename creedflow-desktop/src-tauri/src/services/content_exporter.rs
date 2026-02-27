/// Content exporter — converts Markdown to HTML/plaintext for publishing.

pub struct ContentExporter;

impl ContentExporter {
    /// Convert markdown to HTML (basic conversion).
    pub fn markdown_to_html(markdown: &str) -> String {
        let mut html = String::new();
        let mut in_code_block = false;

        for line in markdown.lines() {
            if line.starts_with("```") {
                if in_code_block {
                    html.push_str("</code></pre>\n");
                    in_code_block = false;
                } else {
                    html.push_str("<pre><code>");
                    in_code_block = true;
                }
                continue;
            }

            if in_code_block {
                html.push_str(&escape_html(line));
                html.push('\n');
                continue;
            }

            let trimmed = line.trim();
            if trimmed.is_empty() {
                html.push_str("<br>\n");
            } else if let Some(heading) = trimmed.strip_prefix("### ") {
                html.push_str(&format!("<h3>{}</h3>\n", escape_html(heading)));
            } else if let Some(heading) = trimmed.strip_prefix("## ") {
                html.push_str(&format!("<h2>{}</h2>\n", escape_html(heading)));
            } else if let Some(heading) = trimmed.strip_prefix("# ") {
                html.push_str(&format!("<h1>{}</h1>\n", escape_html(heading)));
            } else if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
                html.push_str(&format!("<li>{}</li>\n", escape_html(&trimmed[2..])));
            } else {
                html.push_str(&format!("<p>{}</p>\n", inline_markdown(trimmed)));
            }
        }

        if in_code_block {
            html.push_str("</code></pre>\n");
        }

        html
    }

    /// Convert markdown to plaintext (strip formatting).
    pub fn markdown_to_plaintext(markdown: &str) -> String {
        let mut text = String::new();

        for line in markdown.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("```") {
                continue;
            }
            // Strip heading markers
            let clean = trimmed
                .trim_start_matches('#')
                .trim_start_matches(' ')
                .to_string();
            // Strip bold/italic markers
            let clean = clean.replace("**", "").replace("__", "").replace('*', "").replace('_', "");
            text.push_str(&clean);
            text.push('\n');
        }

        text
    }
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn inline_markdown(text: &str) -> String {
    let escaped = escape_html(text);
    // Bold
    let result = regex::Regex::new(r"\*\*(.+?)\*\*")
        .unwrap()
        .replace_all(&escaped, "<strong>$1</strong>");
    // Italic
    let result = regex::Regex::new(r"\*(.+?)\*")
        .unwrap()
        .replace_all(&result, "<em>$1</em>");
    // Code
    let result = regex::Regex::new(r"`(.+?)`")
        .unwrap()
        .replace_all(&result, "<code>$1</code>");
    // Links
    let result = regex::Regex::new(r"\[(.+?)\]\((.+?)\)")
        .unwrap()
        .replace_all(&result, "<a href=\"$2\">$1</a>");

    result.to_string()
}
