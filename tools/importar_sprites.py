"""Transforma os desenhos dos carros (JPEG, visto de cima, frente para cima)
em sprites PNG com fundo transparente em assets/images/cars/sprites/.

Para cada carro sai (todos do mesmo tamanho, com PAD px de margem):
  <id>.png         o carro recortado, com cores realçadas e contorno escuro
  <id>_paint.png   máscara da lataria (branco = pintável, com o sombreado),
                   usada pelo CarVisual.gd quando o carro recebe uma pintura
  <id>_shadow.png  sombra suave do carro no asfalto

Rodar: python tools/importar_sprites.py "<pasta com as imagens>"
"""

import os
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "cars", "sprites")
HEIGHT = 320  # altura do carro no sprite (no jogo ele tem ~64 px: fica nítido na garagem)
PAD = 16  # margem em volta (para o contorno e a sombra); o CarVisual.gd usa o mesmo valor
OUTLINE = (16, 18, 26)
OUTLINE_PX = 2.5  # espessura do contorno no sprite final

# id do carro -> (arquivo, ponto da lataria para amostrar a cor (x, y em 0..1), tolerância da cor)
CARS = {
    "equilibrado": ("WhatsApp Image 2026-10-24 at 20.45.50.jpeg", (0.5, 0.72), 60),
    "turbo": ("WhatsApp Image 2026-10-24 at 20.40.51.jpeg", (0.37, 0.75), 70),
    "blindado": ("WhatsApp Image 2026-10-24 at 20.40.52 (2).jpeg", (0.36, 0.55), 55),
    "pickup": ("WhatsApp Image 2026-10-24 at 20.40.52.jpeg", (0.5, 0.42), 70),
    "muscle": ("WhatsApp Image 2026-10-24 at 20.40.54.jpeg", (0.5, 0.5), 24),
    "uno": ("FIAT UNO.jpeg", (0.5, 0.2), 45),
    "esportivo": ("WhatsApp Image 2026-10-24 at 20.40.54 (2).jpeg", (0.5, 0.48), 75),
    "gol": ("GOL DE NARCELIO.jpeg", (0.5, 0.6), 40),
    "f1": ("WhatsApp Image 2026-10-24 at 20.40.54 (1).jpeg", (0.5, 0.12), 80),
    "roadster": ("WhatsApp Image 2026-10-24 at 20.49.17.jpeg", (0.5, 0.52), 70),
    "zero": ("WhatsApp Image 2026-10-24 at 20.40.53.jpeg", (0.6, 0.5), 28),
}
# Carros com fundo preso por dentro (entre rodas e asas): todo pixel com a
# cor do fundo vira transparente, não só o que encosta na borda.
HOLES = ["f1"]
# (BG_TOL, FRINGE_TOL) próprios: fundo escuro, perto da cor do contorno.
TOLS = {"uno": (16, 24)}
# Desenhos com traço de lápis/sombra realista: viram arte chapada (cores em
# áreas lisas + linhas limpas) para combinar com o resto do jogo.
# id -> número de cores
FLAT = {"equilibrado": 14, "blindado": 12, "f1": 14, "roadster": 12}

BG_TOL = 34  # distância de cor até o fundo que ainda conta como fundo
FRINGE_TOL = 70  # na borda, aceita pixels um pouco mais longe do fundo (halo do JPEG)


def dilate(m):
    out = m.copy()
    out[1:, :] |= m[:-1, :]
    out[:-1, :] |= m[1:, :]
    out[:, 1:] |= m[:, :-1]
    out[:, :-1] |= m[:, 1:]
    return out


def flood_from_border(allowed):
    """Pixels de `allowed` ligados à borda da imagem."""
    filled = np.zeros_like(allowed)
    filled[0, :] = allowed[0, :]
    filled[-1, :] = allowed[-1, :]
    filled[:, 0] = allowed[:, 0]
    filled[:, -1] = allowed[:, -1]
    while True:
        grown = dilate(filled) & allowed
        if grown.sum() == filled.sum():
            return filled
        filled = grown


def blur(a):
    p = np.pad(a, 1, mode="edge")
    return (p[:-2, :-2] + p[:-2, 1:-1] + p[:-2, 2:] + p[1:-1, :-2] + p[1:-1, 1:-1] * 4
            + p[1:-1, 2:] + p[2:, :-2] + p[2:, 1:-1] + p[2:, 2:]) / 12.0


def gauss(a, radius):
    img = Image.fromarray((a * 255.0).clip(0, 255).astype(np.uint8), "L")
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0


def flatten(rgb, colors):
    """Arte chapada: tira hachuras e textura, mantém as linhas escuras."""
    up = rgb.resize((rgb.width * 2, rgb.height * 2), Image.LANCZOS)
    sm = up.filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.MedianFilter(5))
    q = sm.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, kmeans=3).convert("RGB")
    q = q.filter(ImageFilter.ModeFilter(5))
    lum = np.asarray(up.filter(ImageFilter.MedianFilter(3)).convert("L")).astype(np.float32)
    loc = np.asarray(up.convert("L").filter(ImageFilter.GaussianBlur(4))).astype(np.float32)
    line = gauss(np.clip((loc - lum - 18) / 25.0, 0, 1) * (lum < 90), 0.8)
    out = np.asarray(q).astype(np.float32)
    out = out * (1 - line[..., None]) + np.array(OUTLINE, np.float32) * line[..., None]
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB").resize(rgb.size, Image.LANCZOS)


def process(car_id, src, sample, tol):
    src_img = Image.open(src).convert("RGB")
    raw = np.asarray(src_img).astype(np.float32)
    # tira o chiado do JPEG antes de recortar e realçar
    clean = src_img.filter(ImageFilter.MedianFilter(3))
    h, w = raw.shape[:2]
    border = np.concatenate([raw[0], raw[-1], raw[:, 0], raw[:, -1]])
    bg_color = np.median(border, axis=0)
    dist = np.linalg.norm(raw - bg_color, axis=2)

    bg_tol, fringe_tol = TOLS.get(car_id, (BG_TOL, FRINGE_TOL))
    bg = flood_from_border(dist < bg_tol)
    if car_id in HOLES:
        bg |= dist < bg_tol
    # come o halo claro que o JPEG deixa em volta do contorno
    for _ in range(3):
        bg |= dilate(bg) & (dist < fringe_tol)
    alpha = (~bg).astype(np.float32)
    alpha = np.clip(blur(alpha) * 1.25 - 0.1, 0.0, 1.0)

    rgb = np.asarray(clean).astype(np.float32)
    # o que sobrou do halo (cor de fundo colada na borda) vira contorno
    near = bg.copy()
    for _ in range(4):
        near = dilate(near)
    fringe = near & ~bg & (dist < fringe_tol + 40)
    rgb[fringe] = OUTLINE

    # lataria: cor parecida com a amostrada
    sx, sy = int(sample[0] * w), int(sample[1] * h)
    body_color = np.median(rgb[sy - 3:sy + 4, sx - 3:sx + 4].reshape(-1, 3), axis=0)
    body = (np.linalg.norm(rgb - body_color, axis=2) < tol) & (alpha > 0.5)
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    ref = max(float(body_color @ np.array([0.299, 0.587, 0.114])), 40.0)
    shade = np.clip(lum / ref, 0.0, 1.0) * 255.0
    paint_a = blur(blur(body.astype(np.float32))) * alpha

    ys, xs = np.nonzero(alpha > 0.05)
    box = (xs.min() - 1, ys.min() - 1, xs.max() + 2, ys.max() + 2)
    ch = box[3] - box[1]
    size = (round((box[2] - box[0]) * HEIGHT / ch), HEIGHT)

    # cores mais vivas e traço mais nítido
    look = ImageEnhance.Color(clean).enhance(1.18)
    look = ImageEnhance.Contrast(look).enhance(1.08)
    look = np.asarray(look).astype(np.float32)
    # fora do carro a cor vira a do contorno: ao reduzir, o fundo claro não
    # vaza para a borda (era o que deixava o carro com cara de recorte)
    look[alpha < 0.6] = OUTLINE
    car = Image.fromarray(np.dstack([look, alpha * 255.0]).clip(0, 255).astype(np.uint8), "RGBA")
    car = car.crop(box).resize(size, Image.LANCZOS)
    a_s = np.asarray(car)[..., 3].astype(np.float32) / 255.0
    rgb_s = car.convert("RGB")
    if car_id in FLAT:
        rgb_s = flatten(rgb_s, FLAT[car_id])
    rgb_s = rgb_s.filter(ImageFilter.UnsharpMask(radius=1.4, percent=70, threshold=2))
    # volume igual ao dos carros do jogo: laterais mais escuras, meio mais claro
    inside = gauss((a_s > 0.5).astype(np.float32), 9)
    vol = 0.8 + 0.26 * np.clip(inside * 1.6 - 0.35, 0, 1)
    rgb_s = np.asarray(rgb_s).astype(np.float32) * vol[..., None]

    paint = Image.fromarray(np.dstack([shade, shade, shade, paint_a * 255.0]).clip(0, 255).astype(np.uint8), "RGBA")
    paint = paint.crop(box).resize(size, Image.LANCZOS)

    # tudo numa tela com margem PAD
    W, H = size[0] + PAD * 2, size[1] + PAD * 2
    a_full = np.zeros((H, W), np.float32)
    a_full[PAD:PAD + size[1], PAD:PAD + size[0]] = a_s
    rgb_full = np.zeros((H, W, 3), np.float32)
    rgb_full[PAD:PAD + size[1], PAD:PAD + size[0]] = rgb_s
    # a borda de dentro da silhueta também vira contorno (traço firme e escuro)
    edge = np.clip((1.0 - gauss((a_full > 0.5).astype(np.float32), 1.2)) * 2.2, 0.0, 1.0) * (a_full > 0.02)
    rgb_full = rgb_full * (1 - edge[..., None]) + np.array(OUTLINE, np.float32) * edge[..., None]

    # contorno: a silhueta engordada, por baixo do carro (esconde o resto do halo)
    ring = np.clip(gauss((a_full > 0.5).astype(np.float32), OUTLINE_PX * 0.5) * 2.5, 0.0, 1.0)
    ring = np.maximum(ring, a_full)
    for _ in range(int(OUTLINE_PX)):
        ring = np.maximum(ring, blur(ring) * 1.6).clip(0.0, 1.0)
    out_rgb = rgb_full * a_full[..., None] + np.array(OUTLINE, np.float32) * (1.0 - a_full[..., None])
    car_out = Image.fromarray(np.dstack([out_rgb, ring * 255.0]).clip(0, 255).astype(np.uint8), "RGBA")

    paint_out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    paint_out.paste(paint, (PAD, PAD))

    shadow_a = gauss(ring, 5.0) * 0.85
    shadow = Image.fromarray(np.dstack([np.zeros((H, W, 3)), shadow_a * 255.0]).clip(0, 255).astype(np.uint8), "RGBA")
    return car_out, paint_out, shadow


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src_dir = sys.argv[1]
    only = sys.argv[2:]
    os.makedirs(OUT_DIR, exist_ok=True)
    for car_id, (name, sample, tol) in CARS.items():
        if only and car_id not in only:
            continue
        car, paint, shadow = process(car_id, os.path.join(src_dir, name), sample, tol)
        car.save(os.path.join(OUT_DIR, car_id + ".png"))
        paint.save(os.path.join(OUT_DIR, car_id + "_paint.png"))
        shadow.save(os.path.join(OUT_DIR, car_id + "_shadow.png"))
        print("%-12s %dx%d" % (car_id, car.width, car.height))


if __name__ == "__main__":
    main()
