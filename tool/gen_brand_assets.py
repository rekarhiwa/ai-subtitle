from pathlib import Path

from PIL import Image

src = Path(
    r"C:\Users\rekar\.cursor\projects\c-Users-rekar-Desktop-project-subtitle"
    r"\assets\montage_logo_1024.jpg"
)
root = Path(r"C:\Users\rekar\Desktop\project\subtitle")
brand = root / "assets" / "branding"
brand.mkdir(parents=True, exist_ok=True)

img = Image.open(src).convert("RGBA")
w, h = img.size
side = min(w, h)
left = (w - side) // 2
top = (h - side) // 2
img = img.crop((left, top, left + side, top + side)).resize(
    (1024, 1024), Image.Resampling.LANCZOS
)

img.save(brand / "montage_logo.png", optimize=True)
img.save(brand / "logo_mark.png", optimize=True)

mipmaps = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
res = root / "android" / "app" / "src" / "main" / "res"
for folder, size in mipmaps.items():
    out = res / folder / "ic_launcher.png"
    img.resize((size, size), Image.Resampling.LANCZOS).save(out, optimize=True)
    print("wrote", out)

for dens, size in [
    ("drawable-hdpi", 162),
    ("drawable-xhdpi", 216),
    ("drawable-xxhdpi", 324),
    ("drawable-xxxhdpi", 432),
]:
    d = res / dens
    d.mkdir(parents=True, exist_ok=True)
    f = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = int(size * 0.72)
    m = img.resize((s, s), Image.Resampling.LANCZOS)
    f.paste(m, ((size - s) // 2, (size - s) // 2), m)
    f.save(d / "ic_launcher_foreground.png", optimize=True)

splash_sizes = {
    "drawable-mdpi": 160,
    "drawable-hdpi": 240,
    "drawable-xhdpi": 320,
    "drawable-xxhdpi": 480,
    "drawable-xxxhdpi": 640,
}
for dens, size in splash_sizes.items():
    d = res / dens
    d.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    m = img.resize((size, size), Image.Resampling.LANCZOS)
    canvas.paste(m, (0, 0), m)
    canvas.save(d / "splash_logo.png", optimize=True)
    print("splash", dens, size)

(res / "drawable").mkdir(parents=True, exist_ok=True)
img.resize((320, 320), Image.Resampling.LANCZOS).save(
    res / "drawable" / "splash_logo.png", optimize=True
)

ico_path = root / "windows" / "runner" / "resources" / "app_icon.ico"
sizes = [16, 32, 48, 64, 128, 256]
ico_images = [img.resize((s, s), Image.Resampling.LANCZOS) for s in sizes]
ico_images[0].save(ico_path, format="ICO", sizes=[(s, s) for s in sizes])
print("ico", ico_path)
print("done")
