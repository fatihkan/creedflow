use std::path::{Path, PathBuf};
use std::process::Command;

/// Thumbnail generation service for Linux/macOS.
/// Uses system tools when available, falls back to placeholder SVG.
pub struct ThumbnailService;

impl ThumbnailService {
    /// Get the thumbnails directory.
    fn thumbnails_dir() -> PathBuf {
        let base = dirs::data_dir()
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".local/share"));
        base.join("creedflow").join("thumbnails")
    }

    /// Generate a thumbnail for an asset file. Returns the thumbnail path.
    pub fn generate(asset_id: &str, file_path: &str, asset_type: &str) -> Result<String, String> {
        let thumb_dir = Self::thumbnails_dir();
        std::fs::create_dir_all(&thumb_dir)
            .map_err(|e| format!("Failed to create thumbnails dir: {}", e))?;

        let thumb_path = thumb_dir.join(format!("{}.png", asset_id));

        // If thumbnail already exists, return it
        if thumb_path.exists() {
            return Ok(thumb_path.to_string_lossy().to_string());
        }

        let source = Path::new(file_path);
        let generated = match asset_type {
            "image" => Self::generate_image_thumbnail(source, &thumb_path),
            "video" => Self::generate_video_thumbnail(source, &thumb_path),
            _ => false,
        };

        if generated && thumb_path.exists() {
            Ok(thumb_path.to_string_lossy().to_string())
        } else {
            // Generate placeholder SVG-based thumbnail
            Self::generate_placeholder(asset_id, asset_type, &thumb_dir)
        }
    }

    /// Try to resize an image using `convert` (ImageMagick) or `sips` (macOS).
    fn generate_image_thumbnail(source: &Path, dest: &Path) -> bool {
        // Try ImageMagick (Linux)
        if Command::new("convert")
            .args([
                source.to_str().unwrap_or(""),
                "-thumbnail",
                "200x200>",
                "-quality",
                "85",
                dest.to_str().unwrap_or(""),
            ])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
        {
            return true;
        }

        // Try sips (macOS)
        if Command::new("sips")
            .args([
                "-z",
                "200",
                "200",
                source.to_str().unwrap_or(""),
                "--out",
                dest.to_str().unwrap_or(""),
            ])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
        {
            return true;
        }

        false
    }

    /// Try to extract video thumbnail using ffmpeg.
    fn generate_video_thumbnail(source: &Path, dest: &Path) -> bool {
        Command::new("ffmpeg")
            .args([
                "-i",
                source.to_str().unwrap_or(""),
                "-vframes",
                "1",
                "-vf",
                "scale=200:-1",
                "-y",
                dest.to_str().unwrap_or(""),
            ])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    /// Generate a simple placeholder SVG file for non-image assets.
    fn generate_placeholder(asset_id: &str, asset_type: &str, thumb_dir: &Path) -> Result<String, String> {
        let (icon, color) = match asset_type {
            "image" => ("🖼", "#34d399"),
            "video" => ("🎬", "#60a5fa"),
            "audio" => ("🎵", "#a78bfa"),
            "design" => ("🎨", "#f472b6"),
            "document" => ("📄", "#fbbf24"),
            _ => ("📦", "#9ca3af"),
        };

        let svg = format!(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"200\" viewBox=\"0 0 200 200\">\
             <rect width=\"200\" height=\"200\" fill=\"#18181b\" rx=\"12\"/>\
             <text x=\"100\" y=\"90\" text-anchor=\"middle\" font-size=\"48\">{icon}</text>\
             <text x=\"100\" y=\"130\" text-anchor=\"middle\" font-size=\"14\" fill=\"{color}\">{asset_type}</text>\
             </svg>"
        );

        let svg_path = thumb_dir.join(format!("{}.svg", asset_id));
        std::fs::write(&svg_path, svg)
            .map_err(|e| format!("Failed to write placeholder: {}", e))?;
        Ok(svg_path.to_string_lossy().to_string())
    }
}
