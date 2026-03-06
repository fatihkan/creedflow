/// Content exporter — converts Markdown to HTML/plaintext/PDF/DOCX for publishing.

use once_cell::sync::Lazy;
use regex::Regex;

// Static regex patterns for inline markdown conversion (compiled once).
static RE_BOLD: Lazy<Regex> = Lazy::new(|| Regex::new(r"\*\*(.+?)\*\*").unwrap());
static RE_ITALIC: Lazy<Regex> = Lazy::new(|| Regex::new(r"\*(.+?)\*").unwrap());
static RE_CODE: Lazy<Regex> = Lazy::new(|| Regex::new(r"`(.+?)`").unwrap());
static RE_IMAGE: Lazy<Regex> = Lazy::new(|| Regex::new(r"!\[(.+?)\]\((.+?)\)").unwrap());
static RE_LINK: Lazy<Regex> = Lazy::new(|| Regex::new(r"\[(.+?)\]\((.+?)\)").unwrap());

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

    /// Convert markdown to DOCX bytes using docx-rs.
    pub fn markdown_to_docx(markdown: &str) -> Result<Vec<u8>, String> {
        use docx_rs::*;

        let mut docx = Docx::new();

        let mut in_code_block = false;
        for line in markdown.lines() {
            if line.starts_with("```") {
                in_code_block = !in_code_block;
                continue;
            }

            let trimmed = line.trim();

            if in_code_block {
                // Code block — monospace style
                let run = Run::new().add_text(line).fonts(RunFonts::new().ascii("Courier"));
                let para = Paragraph::new().add_run(run);
                docx = docx.add_paragraph(para);
            } else if trimmed.is_empty() {
                docx = docx.add_paragraph(Paragraph::new());
            } else if let Some(heading) = trimmed.strip_prefix("# ") {
                let run = Run::new().add_text(heading).bold();
                let para = Paragraph::new().add_run(run)
                    .style("Heading1");
                docx = docx.add_paragraph(para);
            } else if let Some(heading) = trimmed.strip_prefix("## ") {
                let run = Run::new().add_text(heading).bold();
                let para = Paragraph::new().add_run(run)
                    .style("Heading2");
                docx = docx.add_paragraph(para);
            } else if let Some(heading) = trimmed.strip_prefix("### ") {
                let run = Run::new().add_text(heading).bold();
                let para = Paragraph::new().add_run(run)
                    .style("Heading3");
                docx = docx.add_paragraph(para);
            } else if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
                let text = &trimmed[2..];
                let run = Run::new().add_text(format!("• {}", strip_markdown(text)));
                let para = Paragraph::new().add_run(run);
                docx = docx.add_paragraph(para);
            } else {
                // Regular paragraph — strip inline markdown
                let clean = strip_markdown(trimmed);
                let run = Run::new().add_text(clean);
                let para = Paragraph::new().add_run(run);
                docx = docx.add_paragraph(para);
            }
        }

        let mut buf = Vec::new();
        let cursor = std::io::Cursor::new(&mut buf);
        docx.build().pack(cursor).map_err(|e| format!("DOCX build error: {}", e))?;
        Ok(buf)
    }

    /// Convert markdown to PDF bytes using printpdf.
    pub fn markdown_to_pdf(markdown: &str) -> Result<Vec<u8>, String> {
        use printpdf::*;

        let (doc, page1, layer1) = PdfDocument::new(
            "CreedFlow Export",
            Mm(210.0),
            Mm(297.0),
            "Content",
        );

        let font = doc
            .add_builtin_font(BuiltinFont::Helvetica)
            .map_err(|e| format!("Font error: {}", e))?;
        let font_bold = doc
            .add_builtin_font(BuiltinFont::HelveticaBold)
            .map_err(|e| format!("Font error: {}", e))?;
        let font_mono = doc
            .add_builtin_font(BuiltinFont::Courier)
            .map_err(|e| format!("Font error: {}", e))?;

        let mut current_layer = doc.get_page(page1).get_layer(layer1);
        let mut y = Mm(280.0);
        let left_margin = Mm(20.0);
        let line_height = Mm(5.0);
        let mut in_code_block = false;
        let mut page_count = 1;

        for line in markdown.lines() {
            // Page break if near bottom
            if y.0 < 25.0 {
                let (new_page, new_layer) = doc.add_page(Mm(210.0), Mm(297.0), "Content");
                current_layer = doc.get_page(new_page).get_layer(new_layer);
                y = Mm(280.0);
                page_count += 1;
            }

            if line.starts_with("```") {
                in_code_block = !in_code_block;
                y -= Mm(2.0);
                continue;
            }

            let trimmed = line.trim();

            if in_code_block {
                current_layer.use_text(line, 9.0, left_margin, y, &font_mono);
                y -= line_height;
            } else if trimmed.is_empty() {
                y -= Mm(3.0);
            } else if let Some(heading) = trimmed.strip_prefix("# ") {
                y -= Mm(3.0);
                current_layer.use_text(heading, 18.0, left_margin, y, &font_bold);
                y -= Mm(8.0);
            } else if let Some(heading) = trimmed.strip_prefix("## ") {
                y -= Mm(2.0);
                current_layer.use_text(heading, 14.0, left_margin, y, &font_bold);
                y -= Mm(7.0);
            } else if let Some(heading) = trimmed.strip_prefix("### ") {
                y -= Mm(1.0);
                current_layer.use_text(heading, 12.0, left_margin, y, &font_bold);
                y -= Mm(6.0);
            } else if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
                let text = format!("  • {}", &trimmed[2..]);
                current_layer.use_text(&strip_markdown(&text), 10.0, left_margin, y, &font);
                y -= line_height;
            } else {
                // Word wrap at ~80 chars for A4
                let clean = strip_markdown(trimmed);
                let words: Vec<&str> = clean.split_whitespace().collect();
                let mut current_line = String::new();

                for word in words {
                    if current_line.len() + word.len() + 1 > 85 {
                        current_layer.use_text(&current_line, 10.0, left_margin, y, &font);
                        y -= line_height;
                        current_line = word.to_string();

                        if y.0 < 25.0 {
                            let (new_page, new_layer) = doc.add_page(Mm(210.0), Mm(297.0), "Content");
                            current_layer = doc.get_page(new_page).get_layer(new_layer);
                            y = Mm(280.0);
                            page_count += 1;
                        }
                    } else {
                        if !current_line.is_empty() {
                            current_line.push(' ');
                        }
                        current_line.push_str(word);
                    }
                }

                if !current_line.is_empty() {
                    current_layer.use_text(&current_line, 10.0, left_margin, y, &font);
                    y -= line_height;
                }
            }
        }

        let _ = page_count; // suppress unused warning
        doc.save_to_bytes().map_err(|e| format!("PDF save error: {}", e))
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
    let result = RE_BOLD.replace_all(&escaped, "<strong>$1</strong>");
    // Italic
    let result = RE_ITALIC.replace_all(&result, "<em>$1</em>");
    // Code
    let result = RE_CODE.replace_all(&result, "<code>$1</code>");
    // Images (before links to avoid conflict)
    let result = RE_IMAGE.replace_all(&result, r#"<img src="$2" alt="$1" style="max-width:100%;">"#);
    // Links
    let result = RE_LINK.replace_all(&result, "<a href=\"$2\">$1</a>");

    result.to_string()
}

/// Strip markdown formatting for plain text rendering (PDF).
fn strip_markdown(text: &str) -> String {
    text.replace("**", "")
        .replace("__", "")
        .replace('*', "")
        .replace('_', "")
        .replace('`', "")
}
