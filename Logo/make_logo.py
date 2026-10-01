# Draws the CurseForge logo: the block as it looks in game, with "FPS" over "ping".
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE, SCALE = 512, 4
S = SIZE * SCALE
FONT = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

def ring(inset, radius, fill):
    d.rounded_rectangle([inset, inset, S - 1 - inset, S - 1 - inset], radius=radius, fill=fill)

# Slot frame: gray metal edge, a dark seam, then the dark face.
# Square and filled to the corners: no see-through corners showing the page behind.
ring(0, 0, (28, 26, 24, 255))
ring(24, 130, (128, 126, 122, 255))
ring(56, 104, (62, 60, 57, 255))
ring(80, 84, (20, 18, 17, 255))
# Soft light from the top on the face.
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([S * 0.18, S * 0.06, S * 0.82, S * 0.62], fill=(58, 52, 46, 120))
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.08))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([80, 80, S - 81, S - 81], radius=84, fill=255)
img.paste(Image.alpha_composite(img, glow), (0, 0), mask)
d = ImageDraw.Draw(img)

# The line between the rows, green, fading out at both ends.
mid = S // 2
half = int(S * 0.30)
thick = int(S * 0.012)
line = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ld = ImageDraw.Draw(line)
for x in range(-half, half):
    a = int(255 * (1 - abs(x) / half) ** 0.8)
    ld.line([(mid + x, mid - thick // 2), (mid + x, mid + thick // 2)], fill=(0, 255, 0, a))
img = Image.alpha_composite(img, line)
d = ImageDraw.Draw(img)

# Words: each one's ink centered in its half, as far from the line as from the edge.
inner_top, inner_bottom = 80 + 40, S - 80 - 40
def word(text, size, color, top, bottom):
    font = ImageFont.truetype(FONT, size)
    l, t, r, b = d.textbbox((0, 0), text, font=font, stroke_width=int(size * 0.07))
    x = mid - (l + r) / 2
    y = (top + bottom) / 2 - (t + b) / 2
    d.text((x, y), text, font=font, fill=color, stroke_width=int(size * 0.07), stroke_fill=(0, 0, 0, 255))

word("FPS", int(S * 0.27), (255, 255, 255, 255), inner_top, mid - thick)
word("ping", int(S * 0.25), (0, 255, 0, 255), mid + thick, inner_bottom)

img.resize((SIZE, SIZE), Image.LANCZOS).save("AmILagging-logo.png")
print("saved")
