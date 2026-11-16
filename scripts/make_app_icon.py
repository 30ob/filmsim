"""生成 1024x1024 App 图标（无 alpha 通道，符合 App Store 要求）。

用法：
    python make_app_icon.py <输出路径>
"""
import sys
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # 超采样倍率，最后缩回 1024
W = SIZE * SS

CREAM_HI = np.array([255, 249, 240], dtype=np.float32)
CREAM_LO = np.array([214, 200, 182], dtype=np.float32)
INK = (26, 24, 26)


def _grid():
    y = np.linspace(0.0, 1.0, W, dtype=np.float32)[:, None]
    x = np.linspace(0.0, 1.0, W, dtype=np.float32)[None, :]
    return x, y


def _radial(cx, cy, radius, inner, outer):
    """径向渐变图（inner→outer），返回 HxWx3 float。"""
    x, y = _grid()
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / radius
    t = np.clip(dist, 0.0, 1.0)[..., None]
    return inner[None, None, :] * (1 - t) + outer[None, None, :] * t


def background() -> Image.Image:
    x, y = _grid()
    top = np.array([32, 32, 36], dtype=np.float32)
    bottom = np.array([9, 9, 11], dtype=np.float32)
    img = top[None, None, :] * (1 - y[..., None]) + bottom[None, None, :] * y[..., None]

    dist = np.sqrt((x - 0.5) ** 2 + ((y - 0.56) * 1.02) ** 2) / 0.60
    glow = np.clip(1.0 - dist, 0.0, 1.0) ** 2.6
    img = img + np.array([255, 156, 84], dtype=np.float32)[None, None, :] * glow[..., None] * 0.26

    vig = np.clip(np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.72, 0.0, 1.0) ** 2
    img = img * (1.0 - 0.42 * vig[..., None])

    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), mode="RGB")


def hexagon(cx, cy, r, rotation=0.0):
    return [
        (cx + r * math.cos(math.radians(rotation + 60 * i)),
         cy + r * math.sin(math.radians(rotation + 60 * i)))
        for i in range(6)
    ]


def main(out_path: str) -> None:
    img = background()
    cx = cy = W / 2

    disc = W * 0.302           # 奶油色圆盘
    rim = W * 0.318            # 金属外圈
    hole = W * 0.126           # 光圈开口

    # 外圈（金属筒）
    draw = ImageDraw.Draw(img)
    draw.ellipse([cx - rim, cy - rim, cx + rim, cy + rim], fill=(196, 184, 168))
    draw.ellipse([cx - rim + W * 0.006, cy - rim + W * 0.006,
                  cx + rim - W * 0.006, cy + rim - W * 0.006], fill=(120, 110, 100))

    # 奶油色盘（径向渐变 + 圆形遮罩）
    cream = _radial(0.42, 0.36, 0.95, CREAM_HI, CREAM_LO)
    cream_img = Image.fromarray(np.clip(cream, 0, 255).astype(np.uint8), mode="RGB")
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse([cx - disc, cy - disc, cx + disc, cy + disc], fill=255)
    img.paste(cream_img, (0, 0), mask)

    # 同心细环 + 边缘刻度
    overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for r, alpha in [(disc * 0.86, 26), (disc * 0.70, 22), (disc * 0.55, 18)]:
        od.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK + (alpha,), width=int(W * 0.0018))

    ticks = 60
    for i in range(ticks):
        a = math.radians(360 * i / ticks)
        inner_r = disc * 0.895
        outer_r = disc * (0.965 if i % 5 == 0 else 0.935)
        od.line(
            [(cx + inner_r * math.cos(a), cy + inner_r * math.sin(a)),
             (cx + outer_r * math.cos(a), cy + outer_r * math.sin(a))],
            fill=INK + (70 if i % 5 == 0 else 42,),
            width=int(W * (0.0022 if i % 5 == 0 else 0.0014)),
        )
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

    # 光圈开口：暖色径向渐变 + 六边形
    iris = _radial(0.5, 0.46, 0.26,
                   np.array([255, 214, 140], np.float32),
                   np.array([118, 58, 76], np.float32))
    iris_img = Image.fromarray(np.clip(iris, 0, 255).astype(np.uint8), mode="RGB")
    hmask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(hmask).polygon(hexagon(cx, cy, hole, 30), fill=255)
    img.paste(iris_img, (0, 0), hmask)

    # 叶片接缝
    seams = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(seams)
    for i in range(6):
        a = math.radians(30 + 60 * i)
        px, py = cx + hole * math.cos(a), cy + hole * math.sin(a)
        a2 = math.radians(30 + 60 * i + 44)
        qx, qy = cx + disc * 0.66 * math.cos(a2), cy + disc * 0.66 * math.sin(a2)
        sd.line([(px, py), (qx, qy)], fill=INK + (200,), width=int(W * 0.0048))
    seams = seams.filter(ImageFilter.GaussianBlur(W * 0.0008))
    img = Image.alpha_composite(img.convert("RGBA"), seams).convert("RGB")

    # 开口描边
    ImageDraw.Draw(img).polygon(hexagon(cx, cy, hole, 30),
                                outline=INK, width=int(W * 0.0042))

    # 外圈高光
    hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(hl).arc([cx - rim, cy - rim, cx + rim, cy + rim],
                           start=196, end=320, fill=(255, 252, 245, 150),
                           width=int(W * 0.0075))
    hl = hl.filter(ImageFilter.GaussianBlur(W * 0.0035))
    img = Image.alpha_composite(img.convert("RGBA"), hl).convert("RGB")

    # 胶片颗粒
    rng = np.random.default_rng(11)
    noise = rng.normal(0, 5.0, (W, W, 1)).astype(np.float32)
    arr = np.asarray(img, dtype=np.float32) + noise
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB")

    # 极轻柔光
    soft = img.filter(ImageFilter.GaussianBlur(W * 0.0018))
    img = Image.blend(img, soft, 0.30)

    img = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    img.save(out_path, format="PNG")
    print(f"wrote {out_path} {img.size} mode={img.mode}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
