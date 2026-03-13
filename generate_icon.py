#!/usr/bin/env python3
"""Generate a modern TitleBar app icon - floating glass bars in 3D."""

from PIL import Image, ImageDraw, ImageFilter
import math

SIZE = 1024
CORNER = 220


def lerp(a, b, t):
    return a + (b - a) * t


def radial_gradient(size):
    """Deep violet radial gradient background."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    cx, cy = size * 0.45, size * 0.32
    for y in range(size):
        for x in range(size):
            dx, dy = (x - cx) / size, (y - cy) / size
            d = min(math.sqrt(dx * dx + dy * dy) * 1.7, 1.0)
            r = int(lerp(140, 16, d))
            g = int(lerp(85, 8, d))
            b = int(lerp(255, 42, d))
            px[x, y] = (r, g, b, 255)
    return img


def squircle_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def draw_floating_bar(canvas, cx, cy, w, h, radius, skew_y, fill, outline_alpha, shadow_blur, glow_color=None):
    """Draw a single floating rounded bar with shadow and optional glow."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    x0, y0 = cx - w // 2, cy - h // 2
    x1, y1 = cx + w // 2, cy + h // 2

    # Perspective skew: shift top-left vs bottom-right
    # We simulate this with a slight trapezoid effect using polygon
    # But for simplicity, use rounded rect with offset

    # Shadow
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        [x0 + 6, y0 + 10 + skew_y, x1 + 6, y1 + 10 + skew_y],
        radius=radius, fill=(0, 0, 0, 70),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(shadow_blur))
    canvas = Image.alpha_composite(canvas, shadow)

    # Glow behind bar
    if glow_color:
        glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.rounded_rectangle(
            [x0 - 15, y0 - 10, x1 + 15, y1 + 10],
            radius=radius + 10, fill=glow_color,
        )
        glow = glow.filter(ImageFilter.GaussianBlur(30))
        canvas = Image.alpha_composite(canvas, glow)

    # Bar body
    d.rounded_rectangle(
        [x0, y0, x1, y1],
        radius=radius,
        fill=fill,
        outline=(255, 255, 255, outline_alpha),
        width=2,
    )

    canvas = Image.alpha_composite(canvas, layer)
    return canvas


# --- Build icon ---
mask = squircle_mask(SIZE, CORNER)

# Background gradient
bg = radial_gradient(SIZE)
bg.putalpha(mask)

# Add subtle noise/texture via a faint grid of dots
texture = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
td = ImageDraw.Draw(texture)
for y in range(0, SIZE, 48):
    for x in range(0, SIZE, 48):
        a = int(6 + 4 * math.sin(x * 0.01) * math.cos(y * 0.01))
        td.ellipse([x, y, x + 2, y + 2], fill=(255, 255, 255, a))
texture.putalpha(Image.composite(texture.split()[3], Image.new("L", (SIZE, SIZE), 0), mask))
bg = Image.alpha_composite(bg, texture)

cx = SIZE // 2

# --- Bar 1 (back, topmost, smallest, most transparent) ---
bg = draw_floating_bar(
    bg, cx - 20, 290, 380, 52, 16, 0,
    fill=(255, 255, 255, 25),
    outline_alpha=20,
    shadow_blur=15,
)

# --- Bar 2 (middle) ---
bg = draw_floating_bar(
    bg, cx - 8, 410, 460, 60, 18, 0,
    fill=(255, 255, 255, 45),
    outline_alpha=35,
    shadow_blur=18,
)

# Small dots on middle bar (traffic lights, faint)
mid_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
md = ImageDraw.Draw(mid_layer)
for i, c in enumerate([(255, 95, 86, 80), (255, 189, 46, 80), (39, 201, 63, 80)]):
    dx = cx - 8 - 460 // 2 + 30 + i * 24
    md.ellipse([dx - 6, 404, dx + 6, 416], fill=c)
# Small pill on middle bar
pill_cx = cx - 8
md.rounded_rectangle([pill_cx - 30, 402, pill_cx + 30, 418], radius=8, fill=(255, 255, 255, 50))
bg = Image.alpha_composite(bg, mid_layer)

# --- Bar 3 (front, biggest, most visible — the "active" title bar) ---
bg = draw_floating_bar(
    bg, cx + 5, 555, 540, 72, 20, 0,
    fill=(255, 255, 255, 70),
    outline_alpha=60,
    shadow_blur=22,
    glow_color=(140, 100, 255, 40),
)

# Traffic lights on front bar
front_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
fd = ImageDraw.Draw(front_layer)
front_left = cx + 5 - 540 // 2

for i, c in enumerate([(255, 95, 86, 210), (255, 189, 46, 210), (39, 201, 63, 210)]):
    dx = front_left + 38 + i * 30
    fd.ellipse([dx - 9, 546, dx + 9, 564], fill=c)

# Title pill on front bar
fp_cx = cx + 5
fd.rounded_rectangle(
    [fp_cx - 50, 545, fp_cx + 50, 565],
    radius=10, fill=(255, 255, 255, 100),
)

bg = Image.alpha_composite(bg, front_layer)

# --- Decorative: small floating accent bars below ---
bg = draw_floating_bar(
    bg, cx + 30, 690, 340, 32, 12, 0,
    fill=(255, 255, 255, 22),
    outline_alpha=15,
    shadow_blur=10,
)
bg = draw_floating_bar(
    bg, cx + 50, 755, 240, 26, 10, 0,
    fill=(255, 255, 255, 14),
    outline_alpha=10,
    shadow_blur=8,
)

# --- Top specular highlight ---
hl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
for i in range(50):
    a = int(15 * (1 - i / 50))
    hd.rounded_rectangle(
        [40 + i, i, SIZE - 40 - i, i + 2],
        radius=max(CORNER - i, 10),
        fill=(255, 255, 255, a),
    )
hl.putalpha(Image.composite(hl.split()[3], Image.new("L", (SIZE, SIZE), 0), mask))
bg = Image.alpha_composite(bg, hl)

# --- Rim ---
rim = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(rim).rounded_rectangle(
    [1, 1, SIZE - 2, SIZE - 2], radius=CORNER,
    outline=(255, 255, 255, 18), width=2,
)
rim.putalpha(Image.composite(rim.split()[3], Image.new("L", (SIZE, SIZE), 0), mask))
bg = Image.alpha_composite(bg, rim)

# Final clip
final = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
final.paste(bg, mask=mask)
final.save("assets/TitleBar.png")
print("Icon saved to assets/TitleBar.png")
