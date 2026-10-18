"""Gera os desenhos dos carros (SVG) em assets/images/cars/ e scripts/CarData.gd.

Mesmo estilo do carro original (assets/images/player_car.png): visto de cima,
contorno escuro grosso, lataria com sombra nas laterais, chanfro de luz e
reflexo, vidros azul-claros com brilho, faróis com lente e lanternas de LED.

Cada modelo sai em camadas, desenhadas uma em cima da outra pelo CarVisual.gd:
  <modelo>_base.svg    pneus e peças escuras por baixo (cor fixa)
  <modelo>_body.svg    lataria em branco -> pintada com a cor do carro
  <modelo>_accent.svg  faixas/asas/baú em branco -> pintados com a cor de detalhe
  <modelo>_detail.svg  sombras, reflexos, vidros, luzes e contornos (cor fixa)

scripts/CarData.gd guarda onde ficam as rodas e os piscas de cada modelo
(o jogo desenha a banda do pneu girando e solta fumaça nas rodas de trás).

Tudo em unidades do jogo (1 = 1 pixel na pista), com o centro do carro em
(0, 0) e a frente para cima. O SVG sai SCALE vezes maior para ficar nítido
na garagem. Rodar: python tools/gerar_carros.py
"""

import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT_DIR = os.path.join(ROOT, "assets", "images", "cars")
DATA_FILE = os.path.join(ROOT, "scripts", "CarData.gd")
SCALE = 4

OUTLINE = "#12141c"
RUBBER = "#1b1c22"
DARK = "#23252d"
METAL = "#a3a9b4"
HEAD = "#ffd93a"
TAIL = "#e8141c"

MODELS = {} # nome -> dados para o CarData.gd


# ---------- geometria ----------

def sym(right):
    """Polígono simétrico a partir do lado direito (de cima para baixo)."""
    pts = list(right)
    for x, y in reversed(right):
        if x != 0:
            pts.append((-x, y))
    return pts


def mx(pts):
    return [(-x, y) for x, y in pts]


def f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".") or "0"


def smooth(pts, closed=True, k=1.0):
    """Caminho suave (Catmull-Rom) passando por todos os pontos: carrocerias."""
    n = len(pts)
    d = "M%s,%s" % (f(pts[0][0]), f(pts[0][1]))
    last = n if closed else n - 1
    for i in range(last):
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * k, p1[1] + (p2[1] - p0[1]) / 6 * k)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * k, p2[1] - (p3[1] - p1[1]) / 6 * k)
        d += " C%s,%s %s,%s %s,%s" % (f(c1[0]), f(c1[1]), f(c2[0]), f(c2[1]), f(p2[0]), f(p2[1]))
    return d + (" Z" if closed else "")


def rounded(pts, r=2.2):
    """Polígono com os cantos arredondados: vidros, tetos, luzes e painéis."""
    n = len(pts)
    corners = []
    for i in range(n):
        px, py = pts[i]
        out = []
        for qx, qy in (pts[i - 1], pts[(i + 1) % n]):
            dx, dy = qx - px, qy - py
            ln = max((dx * dx + dy * dy) ** 0.5, 1e-6)
            dd = min(r, ln / 2)
            out.append((px + dx / ln * dd, py + dy / ln * dd))
        corners.append(out)
    d = "M%s,%s" % (f(corners[0][0][0]), f(corners[0][0][1]))
    for i in range(n):
        a, b = corners[i]
        if i > 0:
            d += " L%s,%s" % (f(a[0]), f(a[1]))
        d += " Q%s,%s %s,%s" % (f(pts[i][0]), f(pts[i][1]), f(b[0]), f(b[1]))
    return d + " Z"


def shrink(pts, k):
    """Mesma forma, encolhida para o centro (lente dentro da carcaça)."""
    cx = sum(x for x, _ in pts) / len(pts)
    cy = sum(y for _, y in pts) / len(pts)
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


def box(x, y, w, h):
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]


def alpha_hex(svg):
    """#rrggbbaa -> #rrggbb + opacidade (o leitor de SVG do Godot não entende 8 dígitos)."""
    def rep(m):
        attr, rgb, a = m.group(1), m.group(2), int(m.group(3), 16) / 255
        return '%s="#%s" %s-opacity="%s"' % (attr, rgb, attr, f(a))
    return re.sub(r'(fill|stroke)="#([0-9a-fA-F]{6})([0-9a-fA-F]{2})"', rep, svg)


def path(d, fill="none", stroke=None, w=0.8, extra=""):
    s = '<path d="%s" fill="%s"' % (d, fill)
    if stroke:
        s += ' stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"' % (stroke, f(w))
    return s + extra + "/>"


def line(a, b, color=OUTLINE, w=0.8, alpha=1.0):
    return '<path d="M%s,%s L%s,%s" stroke="%s" stroke-opacity="%s" stroke-width="%s" stroke-linecap="round"/>' % (
        f(a[0]), f(a[1]), f(b[0]), f(b[1]), color, f(alpha), f(w))


# ---------- peças ----------

class Car:
    def __init__(self, name, half_w, half_h, blink):
        self.name = name
        self.hw, self.hh = half_w, half_h
        self.layers = {"base": [], "body": [], "accent": [], "detail": []}
        self.defs = []
        self.n = 0
        self.glint_x = 0.0
        self.data = {"wheels": [], "blink": blink, "rear": []}

    def add(self, layer, svg):
        self.layers[layer].append(svg)

    def uid(self, prefix):
        self.n += 1
        return "%s%d" % (prefix, self.n)

    def clip(self, d):
        c = self.uid("c")
        self.defs.append('<clipPath id="%s"><path d="%s"/></clipPath>' % (c, d))
        return c

    def grad(self, stops, x2=0, y2=1, radial=False):
        g = self.uid("g")
        s = "".join('<stop offset="%s" stop-color="%s" stop-opacity="%s"/>' % (f(o), c, f(a)) for o, c, a in stops)
        if radial:
            self.defs.append('<radialGradient id="%s" cx="0.4" cy="0.4" r="0.7">%s</radialGradient>' % (g, s))
        else:
            self.defs.append('<linearGradient id="%s" x1="0" y1="0" x2="%s" y2="%s">%s</linearGradient>' % (g, f(x2), f(y2), s))
        return "url(#%s)" % g

    # pneus aparecendo dos lados. A banda de rodagem girando é desenhada pelo
    # jogo por cima (CarVisual), por isso o retângulo vai para o CarData.
    def wheels(self, rects, rear_from=0):
        tire = self.grad([(0, "#000", 0.45), (0.3, "#000", 0), (0.7, "#000", 0), (1, "#000", 0.45)], x2=1, y2=0)
        for x, y, w, h in rects:
            self.add("base", '<rect x="%s" y="%s" width="%s" height="%s" rx="1.7" fill="%s" stroke="%s" stroke-width="0.8"/>'
                     % (f(x), f(y), f(w), f(h), RUBBER, OUTLINE))
            self.add("base", '<rect x="%s" y="%s" width="%s" height="%s" rx="1.7" fill="%s"/>' % (f(x), f(y), f(w), f(h), tire))
            # ombro do pneu (borda de fora mais clara)
            ox = x + 0.9 if x < 0 else x + w - 0.9
            self.add("base", line((ox, y + 1.6), (ox, y + h - 1.6), "#5a5d68", 0.7, 0.8))
            self.data["wheels"].append((x, y, w, h))
            if y > rear_from:
                self.data["rear"].append((x + w / 2, y + h - 1))

    # lataria: forma branca (pintada) + sombra lateral, chanfro de luz e contorno
    def shell(self, d, layer="body", shade=0.5, outline=1.5):
        clip = self.clip(d)
        self.add(layer, path(d, "#fff"))
        side = self.grad([(0, "#000", shade), (0.16, "#000", shade * 0.35), (0.34, "#000", 0),
                          (0.7, "#000", 0.04), (0.86, "#000", shade * 0.4), (1, "#000", shade * 1.05)], x2=1, y2=0)
        top = self.grad([(0, "#fff", 0.2), (0.22, "#fff", 0), (0.8, "#000", 0), (1, "#000", 0.25)])
        self.add("detail", '<g clip-path="url(#%s)">%s%s'
                 # chanfro: luz na borda de cima/esquerda, sombra na de baixo/direita
                 '<path d="%s" fill="none" stroke="#fff" stroke-opacity="0.32" stroke-width="2.4" transform="translate(0.7,0.9)"/>'
                 '<path d="%s" fill="none" stroke="#000" stroke-opacity="0.28" stroke-width="2.4" transform="translate(-0.7,-0.9)"/>'
                 '</g>' % (clip, path(d, side), path(d, top), d, d))
        self.add("detail", path(d, "none", OUTLINE, outline))
        return clip

    # faixa de reflexo branca (cortada pela lataria)
    def shine(self, clip, pts, a=0.38):
        self.add("detail", '<g clip-path="url(#%s)">%s</g>' % (clip, path(smooth(pts), "#fff", extra=' fill-opacity="%s"' % f(a))))

    def panel_line(self, pts, w=0.7, a=0.55, both=True):
        for p in ([pts, mx(pts)] if both and any(x != 0 for x, _ in pts) else [pts]):
            d = smooth(p, False) if len(p) > 2 else "M%s,%s L%s,%s" % (f(p[0][0]), f(p[0][1]), f(p[1][0]), f(p[1][1]))
            self.add("detail", path(d, "none", OUTLINE, w, ' stroke-opacity="%s"' % f(a)))

    # peça pintada da cor do carro (teto, capô...) com volume próprio
    def part(self, d, layer="body", outline=0.9, tone=None):
        self.add(layer, path(d, "#fff"))
        clip = self.clip(d)
        if tone:
            self.add("detail", path(d, tone))
        self.add("detail", '<g clip-path="url(#%s)"><path d="%s" fill="none" stroke="#fff" stroke-opacity="0.28" '
                           'stroke-width="1.6" transform="translate(0.4,0.6)"/></g>' % (clip, d))
        self.add("detail", path(d, "none", OUTLINE, outline))

    def fill(self, d, color, outline=0.8, layer="detail"):
        self.add(layer, path(d, color, OUTLINE if outline else None, outline))

    def glass(self, d, outline=1.0, shine=True, dark=False):
        top, bot = ("#2b4d63", "#0f2233") if dark else ("#d2f6ff", "#4fb8e4")
        g = self.grad([(0, top, 1), (1, bot, 1)], x2=0.35, y2=1)
        clip = self.clip(d)
        self.add("detail", path(d, g))
        extra = ""
        if shine:
            gx = self.glint_x
            extra = ('<path d="M-40,40 L-30,40 L10,-60 L0,-60 Z" fill="#fff" fill-opacity="0.5" transform="translate(%s,0)"/>'
                     '<path d="M-40,40 L-37.5,40 L2.5,-60 L0,-60 Z" fill="#fff" fill-opacity="0.45" transform="translate(%s,0)"/>'
                     % (f(gx), f(gx + 5)))
        # brilho na borda de cima do vidro e escurecido embaixo
        self.add("detail", '<g clip-path="url(#%s)">%s'
                 '<path d="%s" fill="none" stroke="#fff" stroke-opacity="0.6" stroke-width="1.3" transform="translate(0,0.8)"/>'
                 '<path d="%s" fill="none" stroke="#06121c" stroke-opacity="0.35" stroke-width="1.6" transform="translate(0,-0.9)"/>'
                 '</g>' % (clip, extra, d, d))
        self.add("detail", path(d, "none", OUTLINE, outline))

    # farol: carcaça escura + lente com núcleo branco + reflexo
    def headlight(self, pts, both=True, drl=True):
        for p in ([pts, mx(pts)] if both else [pts]):
            self.fill(rounded(p, 1.2), DARK, 0.7)
            lens = self.grad([(0, "#fffbe8", 1), (0.55, "#ffe680", 1), (1, HEAD, 1)], radial=True)
            self.fill(rounded(shrink(p, 0.72), 0.9), lens, 0)
            cx = sum(x for x, _ in p) / len(p)
            cy = sum(y for _, y in p) / len(p)
            self.add("detail", '<circle cx="%s" cy="%s" r="0.8" fill="#fff"/>' % (f(cx - 0.5), f(cy - 0.3)))
            if drl:
                # luz diurna: filete claro na borda de dentro
                a, b = sorted(p, key=lambda q: q[1])[-2:]
                self.add("detail", line(a, b, "#fffbe0", 0.8, 0.9))

    # lanterna: carcaça escura + LED vermelho com filete claro
    def taillight(self, pts, both=True):
        for p in ([pts, mx(pts)] if both else [pts]):
            self.fill(rounded(p, 1.0), "#3a0a0e", 0.7)
            lens = self.grad([(0, "#ff7a6a", 1), (0.5, TAIL, 1), (1, "#9a0a10", 1)])
            self.fill(rounded(shrink(p, 0.7), 0.8), lens, 0)
            xs = [x for x, _ in p]
            ys = [y for _, y in p]
            cy = (min(ys) + max(ys)) / 2
            span = (max(xs) - min(xs)) * 0.3
            cx = sum(xs) / len(xs)
            self.add("detail", line((cx - span, cy), (cx + span, cy), "#ffc2b8", 0.6, 0.95))

    def round_lamp(self, x, y, r):
        for xx in (x, -x):
            self.add("detail", '<circle cx="%s" cy="%s" r="%s" fill="%s" fill-opacity="0.22"/>' % (f(xx), f(y), f(r * 1.5), HEAD))
            self.add("detail", '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="0.8"/>' % (f(xx), f(y), f(r), DARK, OUTLINE))
            lens = self.grad([(0, "#fffbe8", 1), (0.6, "#ffe680", 1), (1, HEAD, 1)], radial=True)
            self.add("detail", '<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (f(xx), f(y), f(r * 0.72), lens))
            self.add("detail", '<circle cx="%s" cy="%s" r="%s" fill="#fff" fill-opacity="0.9"/>' % (f(xx - r * 0.3), f(y - r * 0.3), f(r * 0.25)))

    def mirrors(self, y, x, w=3.4, h=2.6):
        for s in (1, -1):
            d = ("M%s,%s h%s a1.3,1.3 0 0 1 0,%s h-%s Z" if s > 0 else "M%s,%s h-%s a1.3,1.3 0 0 0 0,%s h%s Z") % (
                f(x * s), f(y), f(w - 1.3), f(h), f(w - 1.3))
            self.add("body", path(d, "#fff"))
            self.add("detail", path(d, "#000", extra=' fill-opacity="0.18"'))
            self.add("detail", path(d, "none", OUTLINE, 0.8))
            # espelho
            self.add("detail", line((x * s + 0.9 * s, y + h * 0.5), (x * s + (w - 1.2) * s, y + h * 0.5), "#9fe3fa", 0.8, 0.9))

    # para-choque: faixa mais escura na ponta, cortada pela lataria
    def bumper(self, clip, y0, y1, grille=None):
        top, bot = min(y0, y1), max(y0, y1)
        edge = bot if y1 > y0 else top
        self.add("detail", '<g clip-path="url(#%s)"><rect x="-30" y="%s" width="60" height="%s" fill="#000" fill-opacity="0.22"/>%s</g>'
                 % (clip, f(top), f(bot - top), line((-30, edge), (30, edge), OUTLINE, 0.7, 0.6)))
        if grille:
            x, y, w, h = grille
            self.fill(rounded(box(x, y, w, h), 1.0), "#15161b", 0.6)
            xx = x + 1.6
            while xx < x + w - 0.8:
                self.add("detail", line((xx, y + 0.6), (xx, y + h - 0.6), "#3d404a", 0.6))
                xx += 1.6

    def diffuser(self, x, y, w, h, fins=4):
        self.fill(rounded(box(x, y, w, h), 1.0), "#15161b", 0.7)
        for i in range(1, fins):
            xx = x + w * i / fins
            self.add("detail", line((xx, y + 0.4), (xx, y + h - 0.4), "#454852", 0.6))

    def exhaust(self, x, y, r=1.6):
        self.add("base", '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="0.6"/>' % (f(x), f(y), f(r), METAL, OUTLINE))
        self.add("base", '<circle cx="%s" cy="%s" r="%s" fill="#0d0e12"/>' % (f(x), f(y + 0.2), f(r * 0.55)))

    def write(self):
        w, h = self.hw * 2, self.hh * 2
        for layer, items in self.layers.items():
            p = os.path.join(OUT_DIR, "%s_%s.svg" % (self.name, layer))
            if not items:
                if os.path.exists(p):
                    os.remove(p)
                continue
            svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s %s %s %s">\n'
                   '<defs>%s</defs>\n%s\n</svg>\n' % (w * SCALE, h * SCALE, f(-self.hw), f(-self.hh), f(w), f(h),
                                                     "".join(self.defs), "\n".join(items)))
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(alpha_hex(svg))
        MODELS[self.name] = self.data


# ---------- modelos ----------
# Car(nome, meia largura, meia altura, piscas (y frente, y trás, meia largura)).
# A tela de cada modelo precisa caber rodas, retrovisores e asas.

def gt():
    """Esportivo do carro original (Equilibrado pintado): GT de motor central."""
    c = Car("gt", 21, 38, (-31, 31, 17))
    c.wheels([(-19.5, -24, 4.5, 11), (15, -24, 4.5, 11), (-20, 12, 5, 13), (15, 12, 5, 13)])
    body = smooth(sym([(4, -36.5), (10, -35.5), (15, -32), (17.5, -26), (17.8, -20), (16.2, -12), (15.8, -4),
                       (17.4, 6), (18.6, 16), (18.4, 26), (16.6, 32), (12, 35.5), (4, 36.5)]))
    clip = c.shell(body)
    c.bumper(clip, -37, -33.8, (-6, -35.6, 12, 1.8))
    c.shine(clip, [(-12, -30), (-9, -32), (-8, -18), (-10, 10), (-13, 28), (-15, 26), (-14.5, 0), (-14, -22)], 0.3)
    c.panel_line([(5, -33.5), (8.5, -18)])
    c.panel_line([(15.5, -12), (13, -9)])
    c.mirrors(-11.5, 15.6)
    c.glint_x = -4
    c.glass(rounded(sym([(9, -17), (12.5, -13), (13.2, -5), (12, -2.5), (6, -3.2)]), 2.4), 1.1)
    c.part(rounded(sym([(10.5, -3.2), (11, 4), (10, 9.8), (6, 10.6)]), 2.4))
    for s in (1, -1):
        c.glass(rounded([(12.2 * s, -2.5), (14.4 * s, -1), (14.6 * s, 7), (13 * s, 10.5), (11.3 * s, 9.5)], 1.2), 0.9, False)
    # tampa do motor de vidro com aletas
    c.glass(rounded(sym([(9.5, 11.2), (10.5, 15), (10, 23), (7, 24.5)]), 2), 1.0, False, dark=True)
    for y in (14, 17, 20, 23):
        c.add("detail", line((-8.6, y), (8.6, y), OUTLINE, 1.1))
    c.add("detail", line((0, 11.2), (0, 24.5), OUTLINE, 1.1))
    for s in (1, -1):
        c.fill(rounded([(11.5 * s, 12), (14 * s, 13), (14 * s, 23), (11.5 * s, 22.5)], 0.8), DARK, 0.7)
        for y in (15, 18, 21):
            c.add("detail", line((11.8 * s, y), (13.7 * s, y), TAIL, 0.9))
    c.headlight([(10, -33), (14.6, -30), (15.2, -27), (13, -27.4), (9.5, -31)])
    c.add("detail", path("M-1.4,-33.2 L1.4,-33.2 L0,-35.2 Z", HEAD, OUTLINE, 0.4))
    c.taillight([(11, 32.4), (15, 29.8), (15.4, 31.6), (12, 34)])
    c.bumper(clip, 37, 33)
    c.diffuser(-7.5, 33, 15, 2.6, 5)
    c.write()


def sedan(name="sedan", taxi=False):
    """Sedã do tráfego (e táxi): três volumes bem marcados."""
    c = Car(name, 21, 36, (-30, 30, 17))
    c.wheels([(-19.5, -22, 4.5, 11), (15, -22, 4.5, 11), (-19.5, 9, 4.5, 12), (15, 9, 4.5, 12)])
    body = smooth(sym([(6, -33), (12.5, -32), (16, -29), (17.4, -23), (17.2, -14), (17, -2), (17.4, 12),
                       (17.4, 23), (16, 29.5), (12, 32.5), (5, 33)]))
    clip = c.shell(body)
    c.bumper(clip, -34, -30.6, (-6.5, -32.6, 13, 2))
    c.shine(clip, [(-12, -28), (-9, -30), (-8, -17), (-9, 14), (-11, 28), (-14, 26), (-14, 0), (-13.5, -20)], 0.28)
    c.panel_line([(6.5, -29.5), (8, -17.5)])
    c.panel_line([(-9, 25.5), (0, 26.2), (9, 25.5)], both=False)
    c.mirrors(-12.5, 16.8)
    c.glint_x = -3
    c.glass(rounded(sym([(11, -16.5), (13.6, -11), (14, -5.5), (8, -4.6)]), 2.4))
    c.part(rounded(sym([(12, -4.8), (12.4, 4), (12, 12.6), (8, 13.2)]), 2.6), tone="#ffffff18")
    for s in (1, -1):
        c.glass(rounded([(13.5 * s, -4), (15.6 * s, -2.5), (15.8 * s, 11), (13.4 * s, 12)], 1.2), 0.8, False)
        c.add("detail", line((13.4 * s, 3.8), (15.8 * s, 3.8), OUTLINE, 0.8))  # coluna entre as portas
    c.glass(rounded(sym([(12, 13.6), (11.5, 18.5), (8, 21)]), 2.2))
    if taxi:
        c.add("detail", '<rect x="-7.2" y="-1.2" width="14.4" height="7.4" rx="1.6" fill="%s" stroke="%s" stroke-width="0.8"/>' % (DARK, OUTLINE))
        c.add("detail", '<rect x="-6" y="0" width="12" height="5" rx="1" fill="#fff27a"/>')
        c.add("detail", '<text x="0" y="3.9" font-size="4.2" font-family="Arial" font-weight="bold" text-anchor="middle" fill="%s">TAXI</text>' % OUTLINE)
    c.headlight([(7, -31.2), (12.5, -30.5), (14.8, -27.8), (13.5, -26.8), (7.5, -28.2)])
    c.taillight([(8, 28.2), (14.8, 27.6), (13.5, 30.6), (8.5, 31)])
    c.bumper(clip, 33.5, 30.8)
    c.exhaust(-9, 33.2, 1.2)
    c.write()


def sport():
    """Turbo: esportivo baixo com faixas, aerofólio alto e escape quádruplo."""
    c = Car("sport", 21, 36, (-30, 30, 17))
    c.wheels([(-19.5, -23, 4.5, 11), (15, -23, 4.5, 11), (-20.5, 8, 5.5, 13.5), (15, 8, 5.5, 13.5)])
    for x in (-5.5, -2.6, 2.6, 5.5):
        c.exhaust(x, 33.2, 1.3)
    body = smooth(sym([(5, -33), (11, -32.5), (15, -29.5), (17.2, -23), (17, -15), (16.2, -6), (17.6, 4),
                       (18.4, 15), (18, 25), (16, 30.5), (10, 32.6), (4, 33)]))
    clip = c.shell(body)
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-6.2" y="-40" width="4" height="80" fill="#fff"/>'
                    '<rect x="2.2" y="-40" width="4" height="80" fill="#fff"/></g>' % clip)
    c.bumper(clip, -34, -30.8, (-7, -33, 14, 2))
    for s in (1, -1):  # entradas de ar no para-choque
        c.fill(rounded([(9.5 * s, -32), (13.6 * s, -30), (13.6 * s, -28.6), (9.5 * s, -29.6)], 0.7), "#15161b", 0.6)
    c.shine(clip, [(-13, -28), (-10, -30), (-9.5, -17), (-10, 12), (-12.5, 27), (-15, 25), (-14.5, 0), (-14.5, -20)], 0.25)
    c.panel_line([(9, -28), (11.5, -17)])
    c.panel_line([(2.4, -27), (3.2, -18)], 0.6, 0.45)  # vinco do capô
    c.mirrors(-11.5, 16)
    c.glint_x = -3
    c.glass(rounded(sym([(10.5, -15.5), (13.4, -9), (13.6, -2.5), (8, -1.6)]), 2.4))
    c.part(rounded(sym([(11.8, -1.8), (11.8, 4), (11, 10), (7, 10.8)]), 2.4))
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-6.2" y="-2" width="4" height="13" fill="#fff"/>'
                    '<rect x="2.2" y="-2" width="4" height="13" fill="#fff"/></g>' % clip)
    c.glass(rounded(sym([(11, 11.2), (10, 16), (7, 18)]), 2))
    for s in (1, -1):  # entradas de ar laterais
        c.fill(rounded([(14 * s, 2), (16.6 * s, 4), (16.8 * s, 13), (14.2 * s, 11.5)], 1), "#15161b", 0.7)
        for y in (5, 8, 11):
            c.add("detail", line((14.4 * s, y), (16.4 * s, y + 0.6), "#454852", 0.6))
    c.headlight([(7.5, -31.5), (12.8, -30), (14.6, -26.2), (9, -28.5)])
    c.taillight([(6, 29.2), (13.5, 28.6), (12, 31), (6.5, 31.2)])
    # aerofólio
    for x in (-18.5, 15.3):
        c.fill(rounded(box(x, 21.5, 3.2, 8.5), 1), DARK, 0.7)
    c.fill(rounded(box(-17.5, 23.6, 35, 5), 1.6), DARK, 0.9)
    c.add("accent", '<rect x="-16.5" y="24.4" width="33" height="1.6" rx="0.8" fill="#fff"/>')
    c.add("detail", line((-16, 27.6), (16, 27.6), "#4a4d57", 0.6))
    c.write()


def armored():
    """Blindado: caixa robusta, quebra-mato, rebites, escotilha e estepe atrás."""
    c = Car("armored", 22, 38, (-28, 30, 18))
    c.wheels([(-21, -23, 5, 14), (16, -23, 5, 14), (-21, 10, 5, 14), (16, 10, 5, 14)])
    body = smooth(sym([(14, -31), (17.6, -30), (19, -27), (19.2, -10), (19.2, 26), (18.4, 30.8), (15, 32.3)]))
    clip = c.shell(body, shade=0.55)
    c.shine(clip, [(-15, -26), (-12, -27), (-12, 25), (-15.5, 27)], 0.18)
    # quebra-mato
    c.fill(rounded(box(-17, -35.5, 34, 5), 1.2), "#4c4f55", 0.9)
    for x in (-11, -1.5, 8):
        c.fill(rounded(box(x, -36.6, 3, 7), 0.8), METAL, 0.7)
    c.add("detail", line((-15, -33), (15, -33), "#2c2e33", 0.7))
    c.headlight([(10, -29.5), (16, -29.5), (16, -26.5), (10, -26.5)], drl=False)
    c.part(rounded(sym([(15.5, -25.5), (15.5, -21)]), 1), tone="#00000033")
    for x in range(-12, 13, 4):  # grade do capô
        c.add("detail", line((x, -25), (x, -21.5), OUTLINE, 0.7, 0.6))
    c.glint_x = -2
    c.glass(rounded(sym([(12, -19.5), (13.4, -15), (13, -11)]), 1.6), 1.0)
    for x in (-4, 4):
        c.add("detail", line((x, -19.6), (x, -11), OUTLINE, 1.3))
    c.mirrors(-15.5, 19)
    c.part(rounded(sym([(15.6, -9.5), (16, 0), (16, 20), (15.4, 27.5)]), 2.4), tone="#0000001f")
    for y in (-1, 13):
        c.panel_line([(-15.5, y), (15.5, y)], 0.8, 0.6, both=False)
    # barra de luzes no teto
    c.fill(rounded(box(-9, -8, 18, 2.6), 1), DARK, 0.7)
    for x in (-6, -2, 2, 6):
        c.add("detail", '<rect x="%s" y="-7.4" width="2.6" height="1.4" rx="0.5" fill="#fff6c8"/>' % f(x - 1.3))
    # escotilha
    c.add("detail", '<circle cx="0" cy="6" r="7.6" fill="#00000055" stroke="%s" stroke-width="1"/>' % OUTLINE)
    c.add("accent", '<circle cx="0" cy="6" r="4.2" fill="#fff"/>')
    c.add("detail", '<circle cx="0" cy="6" r="4.2" fill="#00000030" stroke="%s" stroke-width="0.8"/>' % OUTLINE)
    c.add("detail", '<rect x="-3" y="5" width="6" height="2" rx="0.6" fill="%s"/>' % OUTLINE)
    for x, y in ((-12.5, -6), (12.5, -6), (-12.5, 24), (12.5, 24), (-12.5, 9), (12.5, 9)):
        c.add("detail", '<circle cx="%s" cy="%s" r="1.6" fill="%s" stroke="%s" stroke-width="0.5"/>' % (f(x), f(y), METAL, OUTLINE))
    c.taillight([(11, 28), (16.5, 28), (16.5, 30.5), (11, 30.5)])
    # estepe na traseira
    c.fill(rounded(box(-6, 30.6, 12, 4.4), 2), RUBBER, 0.8)
    c.add("detail", line((-4.5, 32.8), (4.5, 32.8), "#4a4c55", 0.8))
    c.write()


def pickup():
    """Pickup: cabine alta, barra de faróis, caçamba com frisos e engate."""
    c = Car("pickup", 22, 38, (-32, 33, 18))
    c.wheels([(-21, -26, 5, 14), (16, -26, 5, 14), (-21, 14, 5, 14), (16, 14, 5, 14)])
    c.add("base", '<rect x="-1.6" y="34.5" width="3.2" height="3" rx="0.8" fill="%s" stroke="%s" stroke-width="0.5"/>' % (METAL, OUTLINE))
    body = smooth(sym([(10, -35), (15.5, -34), (18.2, -31), (19.2, -24), (19, -12), (19.2, 10), (19.2, 32),
                       (18, 35), (12, 35.6)]))
    clip = c.shell(body)
    c.bumper(clip, -36, -32.4)
    c.fill(rounded(box(-9, -35.6, 18, 3.4), 1), DARK, 0.7)
    for x in (-6, -3, 0, 3, 6):
        c.add("detail", line((x, -35), (x, -32.8), METAL, 0.6))
    c.shine(clip, [(-14, -30), (-11, -32), (-11, 8), (-15, 8), (-15, -20)], 0.28)
    c.headlight([(10.5, -33.2), (16, -32), (16.5, -28.8), (11, -29.8)])
    c.panel_line([(5, -30), (6, -18.5)])
    c.mirrors(-15.5, 19)
    c.glint_x = -3
    c.glass(rounded(sym([(13, -17.5), (15, -11), (15.2, -6.5), (9, -6)]), 2.4))
    c.part(rounded(sym([(14.2, -6.4), (14.4, 1), (14, 6.4)]), 2.4))
    c.fill(rounded(box(-10, -5.2, 20, 2.2), 1), DARK, 0.6)  # barra de faróis no teto
    for x in (-7, -3.5, 0, 3.5, 7):
        c.add("detail", '<circle cx="%s" cy="-4.1" r="0.8" fill="#fff6c8"/>' % f(x))
    c.glass(rounded(sym([(13.6, 6.6), (13, 9.4)]), 1), 0.9, False)
    # caçamba
    c.fill(rounded(box(-16, 11.5, 32, 21), 1.4), "#2a2620", 1)
    for y in (16, 20.5, 25, 29.5):
        c.add("detail", '<rect x="-14.5" y="%s" width="29" height="1.6" rx="0.6" fill="#3d372e"/>' % f(y))
    for x in (-17.4, 14.4):
        c.add("accent", '<rect x="%s" y="10.6" width="3" height="22.5" rx="1" fill="#fff"/>' % f(x))
        c.add("detail", '<rect x="%s" y="10.6" width="3" height="22.5" rx="1" fill="none" stroke="%s" stroke-width="0.7"/>' % (f(x), OUTLINE))
    c.add("accent", '<rect x="-16" y="10" width="32" height="2.4" rx="1" fill="#fff"/>')
    c.add("detail", '<rect x="-16" y="10" width="32" height="2.4" rx="1" fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.part(rounded(box(-15.5, 32, 31, 3.2), 1), tone="#00000022")
    c.taillight([(15, 29.5), (18, 29.5), (18, 33.5), (15, 33.5)])
    c.write()


def muscle():
    """Muscle: capô comprido com tomada de ar, faróis redondos e traseira larga."""
    c = Car("muscle", 21, 36, (-31, 31, 17))
    c.wheels([(-19.5, -23, 4.5, 12), (15, -23, 4.5, 12), (-20.5, 9, 5.5, 14.5), (15, 9, 5.5, 14.5)])
    for x in (-10, 10):
        c.exhaust(x, 33.8, 1.8)
    body = smooth(sym([(10, -33.4), (14.5, -33), (16.8, -30), (17.6, -22), (17.4, -12), (17.2, 2), (17.8, 14),
                       (17.8, 25), (16.8, 31), (13, 33.2), (8, 33.5)]))
    clip = c.shell(body)
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-7" y="-40" width="5" height="80" fill="#fff"/>'
                    '<rect x="2" y="-40" width="5" height="80" fill="#fff"/></g>' % clip)
    c.bumper(clip, -34, -31.4, (-7.5, -33, 15, 2))
    c.shine(clip, [(-13.5, -28), (-11, -30), (-10.5, 10), (-13, 28), (-15.5, 26), (-15, -20)], 0.22)
    # tomada de ar do capô
    c.fill(rounded(sym([(5.2, -26.5), (6, -20), (6, -14.5)]), 1.6), "#00000066", 0.8)
    c.fill(rounded(box(-4, -25.6, 8, 3.4), 0.8), "#0d0e12", 0.6)
    for x in (-2, 0, 2):
        c.add("detail", line((x, -25.2), (x, -22.6), "#3d404a", 0.5))
    c.mirrors(-8.5, 16.8)
    c.glint_x = -3
    c.glass(rounded(sym([(12, -10.5), (14, -5), (14, 0.5), (8, 1.4)]), 2.4))
    c.part(rounded(sym([(13, 1.2), (13, 7), (12, 13), (8, 13.6)]), 2.4))
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-7" y="0" width="5" height="14" fill="#fff"/>'
                    '<rect x="2" y="0" width="5" height="14" fill="#fff"/></g>' % clip)
    c.glass(rounded(sym([(11.5, 14), (12, 18), (8, 20.5)]), 2))
    c.fill(rounded(box(-15, 25, 30, 2.6), 1), DARK, 0.6)  # aerofólio baixo
    c.round_lamp(11.5, -29.4, 3.0)
    c.taillight([(5, 29.4), (15, 29.4), (14.5, 31.8), (5, 31.8)])
    c.write()


def coupe():
    """Esportivo: superesportivo de motor central, linhas elegantes e lâminas laterais."""
    c = Car("coupe", 21, 37, (-30, 30, 17))
    c.wheels([(-19.5, -23, 4.5, 11.5), (15, -23, 4.5, 11.5), (-20, 9, 5, 14), (15, 9, 5, 14)])
    c.exhaust(0, 34, 1.6)
    body = smooth(sym([(3, -35), (9, -34), (14, -31), (17, -25), (17.4, -18), (16, -8), (16.4, 2),
                       (18, 12), (18.2, 22), (16.2, 30), (10.5, 34), (3, 34.6)]))
    clip = c.shell(body)
    c.bumper(clip, -36, -32.8, (-5, -34.6, 10, 1.6))
    c.shine(clip, [(-12, -29), (-9, -31), (-7, -17), (-9, 12), (-12.5, 28), (-15, 26), (-14, 0), (-13.5, -22)], 0.28)
    c.panel_line([(4, -31), (9, -16.5)])
    c.headlight([(9, -31.5), (14, -28.5), (14.5, -25.5), (8.5, -28.8)])
    c.mirrors(-12, 16.2)
    c.glint_x = -3
    c.glass(rounded(sym([(10.5, -15), (13.6, -9), (14, -2), (13, 9), (9, 10.5)]), 2.6))
    c.part(rounded(sym([(9, -3.5), (9.4, 3), (8.4, 8.5)]), 2.2))
    for s in (1, -1):  # lâminas laterais
        x = 15 if s > 0 else -18
        c.add("accent", '<rect x="%s" y="-1" width="3" height="11" rx="1" fill="#fff"/>' % f(x))
        c.add("detail", '<rect x="%s" y="-1" width="3" height="11" rx="1" fill="none" stroke="%s" stroke-width="0.7"/>' % (f(x), OUTLINE))
    # tampa do motor com grelhas
    c.glass(rounded(sym([(10, 12), (10, 18), (9, 24.5)]), 2), 1.0, False, dark=True)
    for y in (14.5, 17.5, 20.5, 23):
        c.add("detail", line((-8.6, y), (8.6, y), OUTLINE, 1.1))
    c.add("detail", line((0, 12), (0, 24.5), OUTLINE, 1.1))
    for s in (1, -1):
        c.fill(rounded([(11 * s, 12), (14 * s, 13), (14 * s, 23), (11 * s, 23)], 0.8), DARK, 0.7)
        for y in (15, 18, 21):
            c.add("detail", line((11.3 * s, y), (13.7 * s, y), TAIL, 0.9))
    c.add("accent", '<rect x="-7" y="28.6" width="14" height="2.6" rx="1" fill="#fff"/>')
    c.add("detail", '<rect x="-7" y="28.6" width="14" height="2.6" rx="1" fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.taillight([(8, 28.4), (14.5, 27.8), (13.5, 30.6), (8, 31)])
    c.diffuser(-6, 31.6, 12, 2.4, 4)
    c.write()


def f1():
    """F1: bico fino, asas largas, sidepods, halo e pneus enormes."""
    c = Car("f1", 23, 40, (-30, 30, 14))
    for s in (1, -1):  # braços da suspensão
        for a, b in (((5, -22), (14, -21)), ((5, -17), (14, -20)), ((10, 16), (14, 20)), ((9, 22), (14, 21))):
            c.add("base", line((a[0] * s, a[1]), (b[0] * s, b[1]), OUTLINE, 1.3))
    c.wheels([(-21.5, -28.5, 8, 14), (13.5, -28.5, 8, 14), (-22.5, 12, 9, 17), (13.5, 12, 9, 17)])
    body = smooth(sym([(2.2, -35.5), (4, -28), (5.6, -18), (7.5, -9.5), (12.5, -4), (13.4, 4), (13, 18),
                       (10.5, 26), (7, 31), (3, 32)]))
    clip = c.shell(body, shade=0.45)
    c.shine(clip, [(-3, -32), (-1.5, -32), (-2, -12), (-8, 4), (-9.5, 18), (-11.5, 16), (-10, 0), (-4, -14)], 0.35)
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-1" y="-36" width="2" height="22" fill="#fff"/></g>' % clip)
    # asa dianteira
    wing = smooth(sym([(19, -38.8), (19.4, -34.5), (14, -33.6), (0, -34.6)]))
    c.add("accent", path(wing, "#fff"))
    c.add("detail", path(wing, "#000", extra=' fill-opacity="0.12"'))
    c.add("detail", path(wing, "none", OUTLINE, 0.9))
    c.add("detail", line((-17, -36.6), (17, -36.6), "#000", 0.6, 0.35))
    for x in (-20.4, 17.4):
        c.fill(rounded(box(x, -40, 3, 7.4), 0.8), DARK, 0.7)
    # entradas laterais (sidepods)
    for s in (1, -1):
        x = 9 if s > 0 else -12
        c.add("accent", '<rect x="%s" y="2" width="3" height="15" rx="1" fill="#fff"/>' % f(x))
        c.add("detail", '<rect x="%s" y="2" width="3" height="15" rx="1" fill="none" stroke="%s" stroke-width="0.7"/>' % (f(x), OUTLINE))
        c.fill(rounded(box(8 if s > 0 else -12, -2.6, 4, 3.4), 1), "#0d0e12", 0.7)
    # cockpit + capacete + halo
    c.fill(rounded(sym([(4.2, -11.5), (5.2, -4), (5, 5.5)]), 2), "#0d0e12", 0.9)
    helmet = c.grad([(0, "#fff3a0", 1), (0.6, "#ffd23a", 1), (1, "#d99a10", 1)], radial=True)
    c.add("detail", '<circle cx="0" cy="-3" r="3.4" fill="%s" stroke="%s" stroke-width="0.8"/>' % (helmet, OUTLINE))
    c.add("detail", '<rect x="-2.2" y="-5.2" width="4.4" height="1.6" rx="0.6" fill="#1d2a3a"/>')
    c.add("detail", path("M-6.5,-1.5 A6.5,6.5 0 0 1 6.5,-1.5", "none", OUTLINE, 1.8))
    c.add("detail", line((0, -8), (0, -14), OUTLINE, 1.8))
    c.panel_line([(0, 8), (0, 26)], 0.8, 0.6, both=False)
    # asa traseira
    c.fill(rounded(box(-17, 28.5, 34, 6.5), 1.4), DARK, 0.9)
    c.add("accent", '<rect x="-16" y="29.2" width="32" height="2.2" rx="1" fill="#fff"/>')
    c.add("detail", line((-15.5, 33), (15.5, 33), "#4a4d57", 0.6))
    c.add("detail", '<rect x="-2" y="35" width="4" height="2.2" rx="0.6" fill="%s" stroke="%s" stroke-width="0.6"/>' % (TAIL, OUTLINE))
    c.write()


def legend():
    """ZERO: carro do futuro em forma de gota, neon e propulsores."""
    c = Car("legend", 22, 39, (-26, 30, 17))
    c.wheels([(-21, -16, 5, 13), (16, -16, 5, 13), (-21, 12, 5, 14), (16, 12, 5, 14)])
    body = smooth(sym([(0, -37), (5, -33), (10, -26), (15, -14), (18.4, -2), (19, 12), (18.4, 24), (15, 31),
                       (8, 34.4)]))
    clip = c.shell(body, shade=0.4)
    c.shine(clip, [(-4, -32), (-2.5, -32), (-6, -14), (-12, 4), (-14, 22), (-16, 20), (-14, 0), (-8, -18)], 0.22)
    for s in (1, -1):  # aletas traseiras
        c.fill(rounded([(10 * s, 20), (13 * s, 22), (13.5 * s, 31), (10.5 * s, 30)], 0.8), "#0d0e12", 0.7)
    # cockpit em gota
    c.glint_x = -3
    c.glass(rounded(sym([(0, -20), (5, -14), (8, -5), (8.4, 7), (6.4, 13.5), (0, 15.5)]), 3), 1.1, True, dark=True)
    c.mirrors(-8, 16.4)
    # linhas de neon (cor de detalhe)
    c.add("accent", line((0, -34), (0, -22), "#fff", 1.8))
    for s in (1, -1):
        c.add("accent", path(smooth([(14 * s, -1), (14.6 * s, 10), (12 * s, 22)], False), "none", "#fff", 1.8))
        c.add("accent", path(smooth([(4 * s, -30), (9 * s, -24), (12 * s, -17)], False), "none", "#fff", 1.2))
    c.add("accent", path(body, "none", "#fff", 1.2))
    for x in (-7, 7):  # propulsores
        c.add("detail", '<circle cx="%s" cy="32" r="3.8" fill="%s"/>' % (f(x), OUTLINE))
        c.add("accent", '<circle cx="%s" cy="32" r="2.4" fill="#fff"/>' % f(x))
        c.add("detail", '<circle cx="%s" cy="31.4" r="1.1" fill="#fff" fill-opacity="0.8"/>' % f(x))
    c.write()


def van():
    """Van do tráfego: frente curta, teto comprido com bagageiro."""
    c = Car("van", 22, 38, (-33, 33, 18))
    c.wheels([(-21, -26, 5, 13), (16, -26, 5, 13), (-21, 16, 5, 13), (16, 16, 5, 13)])
    body = smooth(sym([(12, -35.5), (16.5, -34.4), (18.8, -31), (19.2, -24), (19.2, 30), (18.4, 34.2), (15, 35.4)]))
    clip = c.shell(body)
    c.bumper(clip, -36.5, -33)
    c.fill(rounded(box(-8, -35.4, 16, 2.8), 1), DARK, 0.7)
    c.shine(clip, [(-15, -29), (-12, -31), (-12, 30), (-15, 31)], 0.2)
    c.headlight([(10, -33.6), (15.5, -33), (16, -30), (10.5, -30.5)])
    c.glint_x = -3
    c.glass(rounded(sym([(14, -29), (16, -24), (15.6, -19.5), (9, -19)]), 2.6))
    c.mirrors(-26, 19)
    c.part(rounded(sym([(15.5, -18.5), (16, -10), (16, 26), (15.4, 31.5)]), 2.6), tone="#ffffff18")
    for x in (-11, 11):  # bagageiro
        c.add("detail", line((x, -14), (x, 24), METAL, 1.0))
    for y in (-6, 7, 20):
        c.add("detail", line((-11, y), (11, y), METAL, 0.8))
    c.taillight([(13.5, 30), (17, 30), (17, 34), (13.5, 34)])
    c.bumper(clip, 36, 33.6)
    c.write()


def truck():
    """Caminhão: cabine com retrovisores grandes, tanque e baú comprido (cor de detalhe)."""
    c = Car("truck", 24, 66, (-60, 60, 21))
    c.wheels([(-22, -56, 4, 12), (18, -56, 4, 12),
              (-23, 30, 4, 12), (19, 30, 4, 12), (-23, 45, 4, 12), (19, 45, 4, 12)], rear_from=20)
    c.add("base", '<rect x="-6" y="-39" width="12" height="9" rx="1" fill="%s" stroke="%s" stroke-width="0.8"/>' % (DARK, OUTLINE))
    cab = smooth(sym([(12, -62.6), (17, -61.6), (19.2, -58), (19.4, -40), (18, -35.6), (14, -35)]))
    clip = c.shell(cab)
    c.bumper(clip, -63.6, -60, (-8, -62.4, 16, 2))
    c.shine(clip, [(-15, -57), (-12, -59), (-12, -38), (-15, -38)], 0.25)
    c.headlight([(12, -61.4), (17, -60.6), (17.4, -57.6), (12, -58.2)])
    c.glint_x = -3
    c.glass(rounded(sym([(16, -57), (16.6, -52), (16, -49.5), (9, -49)]), 2.6))
    c.part(rounded(sym([(14.6, -48.4), (15.4, -44), (14.6, -39)]), 2.4), tone="#00000022")
    for s in (1, -1):
        c.fill(rounded(box(19.4 if s > 0 else -23.4, -55, 4, 6), 1), DARK, 0.7)
        c.add("detail", line((21.4 * s, -54.2), (21.4 * s, -49.8), "#9fe3fa", 0.8))
    # baú (cor de detalhe)
    trailer = smooth(sym([(19.5, -32.4), (21.2, -31), (21.2, 60), (19.8, 62.4)]))
    tclip = c.clip(trailer)
    c.add("accent", path(trailer, "#fff"))
    side = c.grad([(0, "#000", 0.35), (0.15, "#000", 0.08), (0.5, "#000", 0), (0.85, "#000", 0.12), (1, "#000", 0.4)], x2=1, y2=0)
    c.add("detail", '<g clip-path="url(#%s)">%s</g>' % (tclip, path(trailer, side)))
    for y in range(-24, 60, 10):
        c.add("detail", '<rect x="-18" y="%d" width="36" height="1.4" fill="#000" fill-opacity="0.16"/>' % y)
        c.add("detail", '<rect x="-18" y="%s" width="36" height="0.6" fill="#fff" fill-opacity="0.2"/>' % f(y + 1.4))
    c.shine(tclip, [(-17, -29), (-14, -29), (-14, 58), (-17, 58)], 0.18)
    c.add("detail", path(trailer, "none", OUTLINE, 1.5))
    c.fill(rounded(box(-21, 58, 42, 4.2), 1.2), "#00000055", 0.8)
    c.taillight([(14, 58.6), (19, 58.6), (19, 61.4), (14, 61.4)])
    c.write()


def bus():
    """Ônibus: janelas em fila, ar-condicionado e faixas (cor de detalhe)."""
    c = Car("bus", 24, 70, (-66, 66, 21))
    c.wheels([(-23, -50, 4, 14), (19, -50, 4, 14), (-23, 38, 4, 14), (19, 38, 4, 14)])
    body = smooth(sym([(15, -68.4), (19.6, -67.4), (21.2, -64), (21.2, 64), (19.6, 67.6), (15, 68.4)]))
    clip = c.shell(body, shade=0.45)
    c.bumper(clip, -69, -66.4)
    c.shine(clip, [(-17, -60), (-14, -61), (-14, 62), (-17, 62)], 0.16)
    c.glint_x = -4
    c.glass(rounded(sym([(17, -65.5), (18.4, -61), (18, -56.5), (10, -56)]), 2.6))
    for s in (1, -1):
        c.fill(rounded(box(21.4 if s > 0 else -23.6, -62.5, 2.2, 5), 0.8), DARK, 0.6)
    for y in range(-50, 62, 14):
        for x in (16.2, -19.2):
            c.glass(rounded(box(x, y, 3, 10.5), 0.8), 0.7, False)
    # teto: ar-condicionado e escotilhas
    c.part(rounded(sym([(11, -42.5), (11.6, -33), (11, -23.5)]), 2.4), tone="#ffffff55")
    for y in (-38, -33, -28):
        c.add("detail", line((-9, y), (9, y), OUTLINE, 0.8, 0.5))
    c.part(rounded(sym([(7, 29.6), (7.6, 35), (7, 40.4)]), 2), tone="#ffffff55")
    for y in (-5, 8):
        c.add("accent", '<rect x="-14" y="%s" width="28" height="3" rx="1" fill="#fff"/>' % f(y))
        c.add("detail", '<rect x="-14" y="%s" width="28" height="3" rx="1" fill="none" stroke="%s" stroke-width="0.7"/>' % (f(y), OUTLINE))
    c.headlight([(13, -67.6), (18, -67.2), (18, -65), (13, -65.2)], drl=False)
    c.taillight([(13, 64.6), (18, 64.6), (18, 67.4), (13, 67.4)])
    c.write()


def write_data():
    """scripts/CarData.gd: rodas, rodas de trás e piscas de cada modelo."""
    out = ["extends RefCounted", "",
           "# Gerado por tools/gerar_carros.py (não editar à mão).",
           "# wheels: pneus (a banda gira por cima no CarVisual); rear: rodas de trás",
           "# (fumaça e marcas de pneu); blink: y da frente, y de trás e meia largura.", "",
           "const MODELS := {"]
    for name, d in MODELS.items():
        wheels = ", ".join("Rect2(%s, %s, %s, %s)" % tuple(f(v) for v in r) for r in d["wheels"])
        rear = ", ".join("Vector2(%s, %s)" % (f(x), f(y)) for x, y in d["rear"])
        out.append('\t"%s": {' % name)
        out.append('\t\t"wheels": [%s],' % wheels)
        out.append('\t\t"rear": [%s],' % rear)
        out.append('\t\t"blink": Vector3(%s, %s, %s),' % tuple(f(v) for v in d["blink"]))
        out.append("\t},")
    out.append("}")
    with open(DATA_FILE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    gt()
    sedan()
    sedan("taxi", taxi=True)
    sport()
    armored()
    pickup()
    muscle()
    coupe()
    f1()
    legend()
    van()
    truck()
    bus()
    write_data()
    print("carros gerados em", os.path.normpath(OUT_DIR))
