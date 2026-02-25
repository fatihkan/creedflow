#!/usr/bin/env python3
"""
Generate CreedFlow app icon — AI orchestration theme.

Design:
- macOS Big Sur rounded-rect shape
- Deep indigo-to-black gradient background
- Bold "CF" monogram — white with strong amber glow
- Hexagonal neural hub with 6 glowing nodes
- Flowing data lines radiating outward
- Amber/gold accent (matches app's forgeAmber)
"""

import math
import os
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE = 1024
CENTER = SIZE // 2
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
RESOURCES_DIR = os.path.join(PROJECT_DIR, "Resources")

# Color palette
BG_DARK = (8, 6, 22)
BG_MID = (18, 14, 48)
BG_CENTER = (30, 22, 72)
AMBER = (255, 179, 0)
AMBER_BRIGHT = (255, 215, 70)
AMBER_HOT = (255, 230, 120)
AMBER_DIM = (180, 130, 0)
WHITE = (255, 255, 255)


def lerp(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_radial_gradient(img):
    """Smooth radial gradient — bright center fading to dark edges."""
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, SIZE, SIZE], fill=BG_DARK)

    max_r = int(SIZE * 0.55)
    for r in range(max_r, 0, -1):
        t = r / max_r
        # Ease-out for smoother falloff
        t = t * t
        color = lerp(BG_CENTER, BG_DARK, t)
        draw.ellipse(
            [CENTER - r, CENTER - r, CENTER + r, CENTER + r],
            fill=color
        )


def draw_hex_network(overlay):
    """Hexagonal neural network with glowing nodes and connections."""
    draw = ImageDraw.Draw(overlay, "RGBA")

    num_nodes = 6
    hub_r = 200  # radius from center to outer nodes
    inner_r = 140  # inner ring

    # Compute node positions
    nodes = []
    for i in range(num_nodes):
        angle = math.radians(i * 60 - 90)  # start from top
        x = CENTER + int(hub_r * math.cos(angle))
        y = CENTER + int(hub_r * math.sin(angle))
        nodes.append((x, y))

    # Inner ring — subtle amber ring
    for r in range(inner_r + 20, inner_r - 2, -1):
        alpha = max(0, min(255, int(50 * (1 - abs(r - inner_r) / 20))))
        draw.ellipse(
            [CENTER - r, CENTER - r, CENTER + r, CENTER + r],
            outline=(*AMBER, alpha), width=1
        )

    # Connections: center to each node
    for nx, ny in nodes:
        # Glow line
        for w in range(8, 0, -2):
            alpha = int(25 * (9 - w))
            draw.line([(CENTER, CENTER), (nx, ny)], fill=(*AMBER_DIM, alpha), width=w)
        # Core line
        draw.line([(CENTER, CENTER), (nx, ny)], fill=(*AMBER, 100), width=2)

    # Connections between adjacent nodes (hexagon edges)
    for i in range(num_nodes):
        x1, y1 = nodes[i]
        x2, y2 = nodes[(i + 1) % num_nodes]
        for w in range(6, 0, -2):
            alpha = int(18 * (7 - w))
            draw.line([(x1, y1), (x2, y2)], fill=(*AMBER_DIM, alpha), width=w)
        draw.line([(x1, y1), (x2, y2)], fill=(*AMBER, 70), width=1)

    # Outer radiating lines from each node
    extensions = [
        (-90, 0.35), (-30, 0.30), (30, 0.32),
        (90, 0.35), (150, 0.28), (210, 0.33),
    ]
    for i, (base_angle, length_frac) in enumerate(extensions):
        nx, ny = nodes[i]
        angle = math.radians(base_angle + (i * 60 - 90))
        ext_len = int(SIZE * length_frac)
        ex = nx + int(ext_len * math.cos(angle))
        ey = ny + int(ext_len * math.sin(angle))
        # Keep within bounds
        ex = max(40, min(SIZE - 40, ex))
        ey = max(40, min(SIZE - 40, ey))

        for w in range(6, 0, -2):
            alpha = int(15 * (7 - w))
            draw.line([(nx, ny), (ex, ey)], fill=(*AMBER_DIM, alpha), width=w)
        draw.line([(nx, ny), (ex, ey)], fill=(*AMBER, 50), width=1)

        # End node (small)
        draw.ellipse([ex - 6, ey - 6, ex + 6, ey + 6], fill=(*AMBER, 60))
        draw.ellipse([ex - 3, ey - 3, ex + 3, ey + 3], fill=(*AMBER_BRIGHT, 120))

    # Draw hub nodes (bright, glowing)
    for nx, ny in nodes:
        # Outer glow
        for r in range(18, 0, -1):
            alpha = int(12 * (19 - r))
            draw.ellipse(
                [nx - r, ny - r, nx + r, ny + r],
                fill=(*AMBER, alpha)
            )
        # Core
        draw.ellipse([nx - 5, ny - 5, nx + 5, ny + 5], fill=(*AMBER_BRIGHT, 220))
        draw.ellipse([nx - 2, ny - 2, nx + 2, ny + 2], fill=(*AMBER_HOT, 255))


def draw_cf_text(img):
    """Draw bold 'CF' monogram with strong glow effect."""
    # Find a suitable bold font
    font_candidates = [
        "/System/Library/Fonts/SFPro-Bold.otf",
        "/System/Library/Fonts/SFNS.ttf",
        "/Library/Fonts/SF-Pro-Display-Bold.otf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
    ]
    font = None
    font_size = 220
    for fp in font_candidates:
        if os.path.exists(fp):
            try:
                font = ImageFont.truetype(fp, font_size)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()

    text = "CF"

    # Measure text
    temp = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    temp_draw = ImageDraw.Draw(temp)
    bbox = temp_draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = CENTER - tw // 2
    ty = CENTER - th // 2 - 12  # slight up offset for visual centering

    # === Glow layers ===
    # Layer 1: Wide amber glow
    glow1 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g1d = ImageDraw.Draw(glow1)
    g1d.text((tx, ty), text, font=font, fill=(*AMBER, 180))
    glow1 = glow1.filter(ImageFilter.GaussianBlur(radius=30))

    # Layer 2: Medium amber-white glow
    glow2 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g2d = ImageDraw.Draw(glow2)
    g2d.text((tx, ty), text, font=font, fill=(*AMBER_BRIGHT, 200))
    glow2 = glow2.filter(ImageFilter.GaussianBlur(radius=12))

    # Layer 3: Tight white glow
    glow3 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g3d = ImageDraw.Draw(glow3)
    g3d.text((tx, ty), text, font=font, fill=(255, 250, 240, 220))
    glow3 = glow3.filter(ImageFilter.GaussianBlur(radius=4))

    # Composite glow layers
    img_rgba = img.convert("RGBA")
    img_rgba = Image.alpha_composite(img_rgba, glow1)
    img_rgba = Image.alpha_composite(img_rgba, glow2)
    img_rgba = Image.alpha_composite(img_rgba, glow3)

    # Main crisp text on top — bright white
    main_draw = ImageDraw.Draw(img_rgba, "RGBA")
    main_draw.text((tx, ty), text, font=font, fill=(255, 252, 245, 250))

    return img_rgba


def draw_bottom_bar(overlay):
    """Amber accent bar at the bottom."""
    draw = ImageDraw.Draw(overlay, "RGBA")
    bar_y = 870
    bar_h = 4
    bar_w = 240
    bx = CENTER - bar_w // 2

    for x in range(bar_w):
        t = abs(x - bar_w // 2) / (bar_w // 2)
        alpha = int(200 * (1 - t * t))
        draw.rectangle(
            [bx + x, bar_y, bx + x + 1, bar_y + bar_h],
            fill=(*AMBER, alpha)
        )

    # Wider subtle glow behind bar
    bar_glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(bar_glow)
    gd.rectangle(
        [bx - 20, bar_y - 8, bx + bar_w + 20, bar_y + bar_h + 8],
        fill=(*AMBER, 40)
    )
    bar_glow = bar_glow.filter(ImageFilter.GaussianBlur(radius=10))
    return Image.alpha_composite(overlay, bar_glow)


def draw_subtle_particles(overlay):
    """Tiny ambient particles for depth."""
    draw = ImageDraw.Draw(overlay, "RGBA")
    import random
    random.seed(42)  # deterministic

    for _ in range(30):
        x = random.randint(60, SIZE - 60)
        y = random.randint(60, SIZE - 60)
        # Skip if too close to center (CF text area)
        if abs(x - CENTER) < 160 and abs(y - CENTER) < 120:
            continue
        size = random.randint(1, 3)
        alpha = random.randint(20, 60)
        draw.ellipse(
            [x - size, y - size, x + size, y + size],
            fill=(*AMBER, alpha)
        )


def generate_icon():
    """Generate the full 1024x1024 icon."""
    # 1. Background
    bg = Image.new("RGBA", (SIZE, SIZE), (*BG_DARK, 255))
    draw_radial_gradient(bg)

    # 2. macOS rounded rect mask
    corner_radius = int(SIZE * 0.22)
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=corner_radius, fill=255)

    # Apply mask to background
    result = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    result.paste(bg, (0, 0), mask)

    # 3. Network overlay
    network = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_hex_network(network)
    draw_subtle_particles(network)
    network = draw_bottom_bar(network)

    # Mask overlay
    network_masked = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    network_masked.paste(network, (0, 0), mask)
    result = Image.alpha_composite(result, network_masked)

    # 4. CF text with glow (needs special handling)
    result = draw_cf_text(result)

    # Re-apply mask to final (clean edges)
    final = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    final.paste(result, (0, 0), mask)

    return final


def create_iconset(icon_1024):
    """Create .iconset and convert to .icns."""
    iconset_dir = os.path.join(RESOURCES_DIR, "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, size in sizes:
        resized = icon_1024.resize((size, size), Image.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename), "PNG")
        print(f"  {filename} ({size}x{size})")

    icns_path = os.path.join(RESOURCES_DIR, "AppIcon.icns")
    result = subprocess.run(
        ["iconutil", "-c", "icns", iconset_dir, "-o", icns_path],
        capture_output=True, text=True
    )

    if result.returncode == 0:
        print(f"\n  AppIcon.icns created: {icns_path}")
        shutil.rmtree(iconset_dir)
    else:
        print(f"\n  iconutil failed: {result.stderr}")

    return icns_path


def main():
    print("Generating CreedFlow app icon...")
    print("")

    os.makedirs(RESOURCES_DIR, exist_ok=True)

    icon = generate_icon()

    preview_path = os.path.join(RESOURCES_DIR, "AppIcon-preview.png")
    icon.save(preview_path, "PNG")
    print(f"  Preview: {preview_path}")
    print("")

    print("Creating .icns:")
    create_iconset(icon)

    # File size
    icns_path = os.path.join(RESOURCES_DIR, "AppIcon.icns")
    if os.path.exists(icns_path):
        size_kb = os.path.getsize(icns_path) // 1024
        print(f"  Size: {size_kb} KB")

    print("\nDone!")


if __name__ == "__main__":
    main()
