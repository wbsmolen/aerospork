#!/usr/bin/env python3
"""
Generate j4 app icon with grid/window arrangement theme
Follows macOS Sequoia design guidelines with adaptive coloring
"""

from PIL import Image, ImageDraw
import json
import os

# macOS app icon sizes (all sizes needed for AppIcon.appiconset)
SIZES = [
    16, 32, 64, 128, 256, 512, 1024
]

# macOS accent color (default blue) - adaptive
ACCENT_COLOR = (0, 122, 255)  # macOS system blue
BACKGROUND_COLOR = (255, 255, 255, 255)  # White background
GRID_COLOR = (52, 52, 52)  # Dark gray for grid lines
WINDOW_FILL = (230, 240, 255)  # Light blue tint

def create_icon(size):
    """Create j4 icon at specified size with grid/window theme"""
    img = Image.new('RGBA', (size, size), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(img)

    # Calculate proportions
    padding = int(size * 0.12)  # 12% padding
    inner_size = size - (2 * padding)

    # Draw rounded rectangle background (macOS style)
    corner_radius = int(size * 0.22)  # 22% corner radius (macOS standard)
    draw.rounded_rectangle(
        [(padding, padding), (size - padding, size - padding)],
        radius=corner_radius,
        fill=WINDOW_FILL,
        outline=None
    )

    # Draw grid representing tiled windows (3x3 grid)
    grid_padding = int(size * 0.22)
    grid_size = size - (2 * grid_padding)
    cell_size = grid_size // 3
    line_width = max(2, int(size * 0.015))  # Adaptive line width

    # Draw grid lines (horizontal and vertical)
    for i in range(1, 3):
        # Horizontal lines
        y = grid_padding + (i * cell_size)
        draw.line(
            [(grid_padding, y), (size - grid_padding, y)],
            fill=GRID_COLOR,
            width=line_width
        )
        # Vertical lines
        x = grid_padding + (i * cell_size)
        draw.line(
            [(x, grid_padding), (x, size - grid_padding)],
            fill=GRID_COLOR,
            width=line_width
        )

    # Draw border rectangle
    border_width = max(3, int(size * 0.02))
    draw.rounded_rectangle(
        [(grid_padding, grid_padding), (size - grid_padding, size - grid_padding)],
        radius=int(corner_radius * 0.5),
        outline=ACCENT_COLOR,
        width=border_width
    )

    # Highlight one cell to show "active window" concept
    highlight_x = grid_padding + cell_size
    highlight_y = grid_padding + cell_size
    highlight_padding = max(2, line_width // 2)

    # Ensure we have valid coordinates
    x1 = highlight_x + highlight_padding
    y1 = highlight_y + highlight_padding
    x2 = highlight_x + cell_size - highlight_padding
    y2 = highlight_y + cell_size - highlight_padding

    if x2 > x1 and y2 > y1:  # Only draw if coordinates are valid
        draw.rectangle(
            [(x1, y1), (x2, y2)],
            fill=(*ACCENT_COLOR, 100),  # Semi-transparent accent color
            outline=None
        )

    return img

def generate_contents_json():
    """Generate Contents.json for AppIcon.appiconset"""
    images = []

    # Generate entries for all required sizes
    for size in SIZES:
        images.append({
            "filename": f"icon_{size}x{size}.png",
            "idiom": "mac",
            "scale": "1x",
            "size": f"{size}x{size}"
        })

        # Add 2x version for sizes <= 512
        if size <= 512:
            images.append({
                "filename": f"icon_{size}x{size}@2x.png",
                "idiom": "mac",
                "scale": "2x",
                "size": f"{size}x{size}"
            })

    contents = {
        "images": images,
        "info": {
            "author": "j4",
            "version": 1
        }
    }

    return contents

def main():
    output_dir = "resources/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)

    print("Generating j4 app icon...")

    # Generate 1x icons
    for size in SIZES:
        icon = create_icon(size)
        icon.save(f"{output_dir}/icon_{size}x{size}.png")
        print(f"  Generated {size}x{size} (1x)")

    # Generate 2x icons (for sizes <= 512)
    for size in [s for s in SIZES if s <= 512]:
        icon = create_icon(size * 2)
        icon.save(f"{output_dir}/icon_{size}x{size}@2x.png")
        print(f"  Generated {size}x{size} (2x)")

    # Generate Contents.json
    contents = generate_contents_json()
    with open(f"{output_dir}/Contents.json", 'w') as f:
        json.dump(contents, f, indent=2)

    print(f"\n✓ Icon set generated in {output_dir}")
    print("  Total files:", len(os.listdir(output_dir)))

if __name__ == "__main__":
    main()
