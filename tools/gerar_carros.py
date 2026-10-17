"""Gera os desenhos dos carros (SVG) em assets/images/cars/.

Mesmo estilo do carro original (assets/images/player_car.png): visto de cima,
contorno escuro grosso, lataria com sombra nas laterais e reflexo, vidros
azul-claros com brilho, faróis amarelos e lanternas vermelhas.

Cada modelo sai em camadas, desenhadas uma em cima da outra pelo CarVisual.gd:
  <modelo>_base.svg    rodas e peças escuras por baixo (cor fixa)
  <modelo>_body.svg    lataria em branco -> pintada com a cor do carro
  <modelo>_accent.svg  faixas/asas em branco -> pintadas com a cor de detalhe
  <modelo>_detail.svg  sombras, reflexos, vidros, luzes e contornos (cor fixa)

Tudo em unidades do jogo (1 = 1 pixel na pista), com o centro do carro em
(0, 0) e a frente para cima. O SVG sai SCALE vezes maior para ficar nítido
na garagem. Rodar: python tools/gerar_carros.py
"""

import os
import re

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "cars")
SCALE = 4

OUTLINE = "#12141c"
WHEEL = "#16171c"
TREAD = "#3a3b42"
DARK = "#23252d"
METAL = "#9aa0aa"
HEAD = "#ffd93a"
TAIL = "#e8141c"


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
    return ("%.2f" % v).rstrip("0").rstrip(".")


def smooth(pts, closed=True, k=1.0):
    """Caminho suave (Catmull-Rom) passando por todos os pontos."""
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
    """Polígono com os cantos arredondados (vidros, tetos e painéis)."""
    n = len(pts)
    corners = []
    for i in range(n):
        px, py = pts[i]
        out = []
        for qx, qy in (pts[i - 1], pts[(i + 1) % n]):
            dx, dy = qx - px, qy - py
            ln = max((dx * dx + dy * dy) ** 0.5, 1e-6)
            d = min(r, ln / 2)
            out.append((px + dx / ln * d, py + dy / ln * d))
        corners.append(out)
    d = "M%s,%s" % (f(corners[0][0][0]), f(corners[0][0][1]))
    for i in range(n):
        a, b = corners[i]
        if i > 0:
            d += " L%s,%s" % (f(a[0]), f(a[1]))
        d += " Q%s,%s %s,%s" % (f(pts[i][0]), f(pts[i][1]), f(b[0]), f(b[1]))
    return d + " Z"


def alpha_hex(svg):
    """#rrggbbaa -> #rrggbb + opacidade (o leitor de SVG do Godot não entende o 8 dígitos)."""
    def rep(m):
        attr, rgb, a = m.group(1), m.group(2), int(m.group(3), 16) / 255
        return '%s="#%s" %s-opacity="%s"' % (attr, rgb, attr, f(a))
    return re.sub(r'(fill|stroke)="#([0-9a-fA-F]{6})([0-9a-fA-F]{2})"', rep, svg)


def poly(pts):
    return "M" + " L".join("%s,%s" % (f(x), f(y)) for x, y in pts) + " Z"


def rrect(x, y, w, h, r):
    return '<rect x="%s" y="%s" width="%s" height="%s" rx="%s"' % (f(x), f(y), f(w), f(h), f(r))


# ---------- peças ----------

class Car:
    def __init__(self, name, half_w, half_h):
        self.name = name
        self.hw, self.hh = half_w, half_h
        self.layers = {"base": [], "body": [], "accent": [], "detail": []}
        self.defs = []
        self.n = 0

    def add(self, layer, svg):
        self.layers[layer].append(svg)

    def uid(self, prefix):
        self.n += 1
        return "%s%d" % (prefix, self.n)

    # rodas aparecendo dos lados
    def wheels(self, rects):
        for x, y, w, h in rects:
            self.add("base", rrect(x, y, w, h, 1.6) + ' fill="%s" stroke="%s" stroke-width="0.8"/>' % (WHEEL, OUTLINE))
            yy = y + 1.6
            while yy < y + h - 1.2:
                self.add("base", '<path d="M%s,%s H%s" stroke="%s" stroke-width="0.7"/>' % (f(x + 0.8), f(yy), f(x + w - 0.8), TREAD))
                yy += 2.4

    # lataria: forma branca (pintada) + sombra lateral + reflexo + contorno
    def shell(self, d, layer="body", shade=0.5, outline=1.5):
        clip = self.uid("c")
        self.defs.append('<clipPath id="%s"><path d="%s"/></clipPath>' % (clip, d))
        self.add(layer, '<path d="%s" fill="#fff"/>' % d)
        g = self.uid("g")
        self.defs.append(
            '<linearGradient id="%s" x1="0" y1="0" x2="1" y2="0">'
            '<stop offset="0" stop-color="#000" stop-opacity="%s"/>'
            '<stop offset="0.16" stop-color="#000" stop-opacity="%s"/>'
            '<stop offset="0.34" stop-color="#000" stop-opacity="0"/>'
            '<stop offset="0.7" stop-color="#000" stop-opacity="0.04"/>'
            '<stop offset="0.86" stop-color="#000" stop-opacity="%s"/>'
            '<stop offset="1" stop-color="#000" stop-opacity="%s"/>'
            '</linearGradient>' % (g, f(shade), f(shade * 0.35), f(shade * 0.4), f(shade * 1.05)))
        v = self.uid("v")
        self.defs.append(
            '<linearGradient id="%s" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#fff" stop-opacity="0.18"/>'
            '<stop offset="0.25" stop-color="#fff" stop-opacity="0"/>'
            '<stop offset="0.8" stop-color="#000" stop-opacity="0"/>'
            '<stop offset="1" stop-color="#000" stop-opacity="0.22"/>'
            '</linearGradient>' % v)
        # os degradês usam a caixa da própria forma (objectBoundingBox)
        self.add("detail", '<g clip-path="url(#%s)"><path d="%s" fill="url(#%s)"/><path d="%s" fill="url(#%s)"/></g>'
                 % (clip, d, g, d, v))
        self.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (d, OUTLINE, f(outline)))
        return clip

    # faixa de reflexo branca (cortada pela lataria)
    def shine(self, clip, pts, a=0.38):
        self.add("detail", '<g clip-path="url(#%s)"><path d="%s" fill="#fff" fill-opacity="%s"/></g>' % (clip, smooth(pts), f(a)))

    def panel_line(self, pts, w=0.7, a=0.55, closed=False, both=True):
        d = smooth(pts, closed) if len(pts) > 2 else "M%s,%s L%s,%s" % (f(pts[0][0]), f(pts[0][1]), f(pts[1][0]), f(pts[1][1]))
        self.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="%s" stroke-linecap="round"/>' % (d, OUTLINE, f(a), f(w)))
        if both and any(x != 0 for x, _ in pts):
            m = mx(pts)
            d = smooth(m, closed) if len(m) > 2 else "M%s,%s L%s,%s" % (f(m[0][0]), f(m[0][1]), f(m[1][0]), f(m[1][1]))
            self.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="%s" stroke-linecap="round"/>' % (d, OUTLINE, f(a), f(w)))

    # peça pintada da cor do carro (teto, capô...) com contorno fino
    def part(self, d, layer="body", outline=0.9, tone=None):
        self.add(layer, '<path d="%s" fill="#fff"/>' % d)
        if tone:
            self.add("detail", '<path d="%s" fill="%s"/>' % (d, tone))
        self.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (d, OUTLINE, f(outline)))

    def fill(self, d, color, outline=0.8, layer="detail"):
        s = '<path d="%s" fill="%s"' % (d, color)
        if outline:
            s += ' stroke="%s" stroke-width="%s" stroke-linejoin="round"' % (OUTLINE, f(outline))
        self.add(layer, s + "/>")

    def glass(self, d, outline=1.0, shine=True, dark=False):
        g = self.uid("w")
        top, bot = ("#2b4d63", "#13283a") if dark else ("#c9f3ff", "#5cc4ea")
        self.defs.append('<linearGradient id="%s" x1="0" y1="0" x2="0.35" y2="1">'
                         '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % (g, top, bot))
        clip = self.uid("c")
        self.defs.append('<clipPath id="%s"><path d="%s"/></clipPath>' % (clip, d))
        self.add("detail", '<path d="%s" fill="url(#%s)"/>' % (d, g))
        if shine:
            self.add("detail", '<g clip-path="url(#%s)" fill="#fff">'
                     '<path d="M-40,40 L-30,40 L10,-60 L0,-60 Z" fill-opacity="0.55" transform="translate(%s,0)"/>'
                     '<path d="M-40,40 L-37,40 L3,-60 L0,-60 Z" fill-opacity="0.5" transform="translate(%s,0)"/>'
                     '</g>' % (clip, f(self.glint_x), f(self.glint_x + 5)))
        self.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (d, OUTLINE, f(outline)))

    glint_x = 0.0

    def lamp(self, pts, color, both=True, glint=True):
        for p in ([pts, mx(pts)] if both else [pts]):
            d = smooth(p) if len(p) > 3 else poly(p)
            self.fill(d, color, 0.7)
            if glint:
                cx = sum(x for x, _ in p) / len(p)
                cy = sum(y for _, y in p) / len(p)
                self.add("detail", '<circle cx="%s" cy="%s" r="0.75" fill="#fff" fill-opacity="0.9"/>' % (f(cx - 0.6), f(cy - 0.4)))

    def round_lamp(self, x, y, r, color):
        for xx in (x, -x):
            self.add("detail", '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="0.8"/>' % (f(xx), f(y), f(r), color, OUTLINE))
            self.add("detail", '<circle cx="%s" cy="%s" r="%s" fill="#fff" fill-opacity="0.85"/>' % (f(xx - r * 0.35), f(y - r * 0.35), f(r * 0.35)))

    def mirrors(self, y, x, w=3.4, h=2.6):
        for s in (1, -1):
            xx = x if s > 0 else -x - w
            d = "M%s,%s h%s a1.3,1.3 0 0 1 0,%s h-%s Z" % (f(xx), f(y), f(w - 1.3), f(h), f(w - 1.3)) if s > 0 else \
                "M%s,%s h-%s a1.3,1.3 0 0 0 0,%s h%s Z" % (f(-x), f(y), f(w - 1.3), f(h), f(w - 1.3))
            self.add("body", '<path d="%s" fill="#fff"/>' % d)
            self.add("detail", '<path d="%s" fill="#000" fill-opacity="0.18"/>' % d)
            self.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-width="0.8"/>' % (d, OUTLINE))

    def write(self):
        w, h = self.hw * 2, self.hh * 2
        for layer, items in self.layers.items():
            path = os.path.join(OUT_DIR, "%s_%s.svg" % (self.name, layer))
            if not items:
                if os.path.exists(path):
                    os.remove(path)
                continue
            svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s %s %s %s">\n'
                   '<defs>%s</defs>\n%s\n</svg>\n' % (w * SCALE, h * SCALE, f(-self.hw), f(-self.hh), f(w), f(h),
                                                     "".join(self.defs), "\n".join(items)))
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(alpha_hex(svg))


# ---------- modelos ----------
# (meia largura, meia altura) da tela de cada modelo: precisa caber rodas,
# retrovisores e asas. O CarVisual desenha a imagem centrada no carro.

def gt():
    """Esportivo do carro original (Equilibrado pintado)."""
    c = Car("gt", 21, 38)
    c.wheels([(-19.5, -24, 4.5, 11), (15, -24, 4.5, 11), (-20, 12, 5, 13), (15, 12, 5, 13)])
    body = smooth(sym([(4, -36.5), (10, -35.5), (15, -32), (17.5, -26), (17.8, -20), (16.2, -12), (15.8, -4),
                       (17.4, 6), (18.6, 16), (18.4, 26), (16.6, 32), (12, 35.5), (4, 36.5)]))
    clip = c.shell(body)
    c.shine(clip, [(-12, -30), (-9, -32), (-8, -18), (-10, 10), (-13, 28), (-15, 26), (-14.5, 0), (-14, -22)], 0.3)
    c.panel_line([(5, -34.5), (8.5, -18)])
    c.panel_line([(15.5, -12), (13, -9)])
    c.mirrors(-11.5, 15.6)
    c.glint_x = -4
    c.glass(rounded(sym([(9, -17), (12.5, -13), (13.2, -5), (12, -2.5), (6, -3.5)])), 1.1)
    c.part(rounded(sym([(10.5, -3.5), (11, 4), (10, 9.5), (6, 10.5)])))
    c.glass(rounded([(12.2, -2.5), (14.4, -1), (14.6, 7), (13, 10.5), (11.3, 9.5), (12, 3)]), 0.9, False)
    c.glass(rounded(mx([(12.2, -2.5), (14.4, -1), (14.6, 7), (13, 10.5), (11.3, 9.5), (12, 3)])), 0.9, False)
    # tampa do motor de vidro com aletas
    c.glass(rounded(sym([(9.5, 11), (10.5, 15), (10, 23), (7, 24.5)])), 1.0, False, dark=True)
    for y in (14, 17, 20, 23):
        c.add("detail", '<path d="M-8.6,%s H8.6" stroke="%s" stroke-width="1.1"/>' % (f(y), OUTLINE))
    c.add("detail", '<path d="M0,11 V24.5" stroke="%s" stroke-width="1.1"/>' % OUTLINE)
    for s in (1, -1):
        c.fill(poly([(11.5 * s, 12), (14 * s, 13), (14 * s, 23), (11.5 * s, 22.5)]), DARK, 0.7)
        for y in (15, 18, 21):
            c.add("detail", '<path d="M%s,%s H%s" stroke="%s" stroke-width="0.9"/>' % (f(11.8 * s), f(y), f(13.7 * s), TAIL))
    c.lamp([(10, -33), (14.6, -30), (15.2, -27), (13, -27.4), (9.5, -31)], HEAD)
    c.add("detail", '<path d="M-1.4,-33.5 L1.4,-33.5 L0,-35.6 Z" fill="%s" stroke="%s" stroke-width="0.4"/>' % (HEAD, OUTLINE))
    c.lamp([(11, 32.5), (15, 30), (15.4, 31.6), (12, 34)], TAIL)
    c.fill(smooth(sym([(7, 33), (7.5, 35.4)])), DARK, 0.6)
    c.write()


def sedan(name="sedan", taxi=False):
    c = Car(name, 21, 36)
    c.wheels([(-19.5, -22, 4.5, 11), (15, -22, 4.5, 11), (-19.5, 9, 4.5, 12), (15, 9, 4.5, 12)])
    body = smooth(sym([(6, -33), (12.5, -32), (16, -29), (17.4, -23), (17.2, -14), (17, -2), (17.4, 12),
                       (17.4, 23), (16, 29.5), (12, 32.5), (5, 33)]))
    clip = c.shell(body)
    c.shine(clip, [(-12, -28), (-9, -30), (-8, -17), (-9, 14), (-11, 28), (-14, 26), (-14, 0), (-13.5, -20)], 0.28)
    c.panel_line([(6.5, -31), (8, -17.5)])
    c.panel_line([(-9, 25.5), (0, 26.2), (9, 25.5)], both=False)
    c.mirrors(-12.5, 16.8)
    c.glint_x = -3
    c.glass(rounded(sym([(11, -16.5), (13.6, -11), (14, -5.5), (8, -4.5)])))
    c.part(rounded(sym([(12, -5), (12.4, 4), (12, 12.5), (8, 13.2)])), tone="#ffffff22")
    for s in (1, -1):
        c.glass(rounded([(13.5 * s, -4), (15.6 * s, -2.5), (15.8 * s, 11), (13.4 * s, 12)]), 0.8, False)
    c.glass(rounded(sym([(12, 13.5), (11.5, 18.5), (8, 21)])))
    if taxi:
        c.add("detail", rrect(-7.2, -1.2, 14.4, 7.4, 1.6) + ' fill="%s" stroke="%s" stroke-width="0.8"/>' % (DARK, OUTLINE))
        c.add("detail", rrect(-6, 0, 12, 5, 1.0) + ' fill="#fff27a"/>')
        c.add("detail", '<text x="0" y="3.9" font-size="4.2" font-family="Arial" font-weight="bold" text-anchor="middle" fill="%s">TAXI</text>' % OUTLINE)
    c.lamp([(7, -31.2), (12.5, -30.5), (14.8, -27.8), (13.5, -26.8), (7.5, -28.2)], HEAD)
    c.lamp([(8, 28.2), (14.8, 27.6), (13.5, 30.6), (8.5, 31)], TAIL)
    c.write()


def sport():
    c = Car("sport", 21, 36)
    c.wheels([(-19.5, -23, 4.5, 11), (15, -23, 4.5, 11), (-20.5, 8, 5.5, 13.5), (15, 8, 5.5, 13.5)])
    body = smooth(sym([(5, -33), (11, -32.5), (15, -29.5), (17.2, -23), (17, -15), (16.2, -6), (17.6, 4),
                       (18.4, 15), (18, 25), (16, 30.5), (10, 32.6), (4, 33)]))
    clip = c.shell(body)
    # faixas de corrida (cor de detalhe), cortadas pela lataria
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-6.2" y="-40" width="4" height="80" fill="#fff"/>'
                    '<rect x="2.2" y="-40" width="4" height="80" fill="#fff"/></g>' % clip)
    c.shine(clip, [(-13, -28), (-10, -30), (-9.5, -17), (-10, 12), (-12.5, 27), (-15, 25), (-14.5, 0), (-14.5, -20)], 0.25)
    c.panel_line([(9, -30), (11.5, -17)])
    c.mirrors(-11.5, 16)
    c.glint_x = -3
    c.glass(rounded(sym([(10.5, -15.5), (13.4, -9), (13.6, -2.5), (8, -1.5)])))
    c.part(rounded(sym([(11.8, -2), (11.8, 4), (11, 10), (7, 10.8)])))
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-6.2" y="-2" width="4" height="13" fill="#fff"/>'
                    '<rect x="2.2" y="-2" width="4" height="13" fill="#fff"/></g>' % clip)
    c.glass(rounded(sym([(11, 11.2), (10, 16), (7, 18)])))
    for s in (1, -1):
        c.fill(smooth([(14 * s, 2), (16.6 * s, 4), (16.8 * s, 13), (14.2 * s, 11.5)]), DARK, 0.7)
    c.lamp([(7.5, -31.5), (12.8, -30), (14.6, -26.2), (9, -28.5)], HEAD)
    c.lamp([(6, 29.2), (13.5, 28.6), (12, 31), (6.5, 31.2)], TAIL)
    # aerofólio
    for x in (-18.5, 15.3):
        c.add("detail", rrect(x, 21.5, 3.2, 8.5, 1) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    c.add("detail", rrect(-17.5, 23.6, 35, 5, 1.6) + ' fill="%s" stroke="%s" stroke-width="0.9"/>' % (DARK, OUTLINE))
    c.add("accent", rrect(-16.5, 24.4, 33, 1.6, 0.8) + ' fill="#fff"/>')
    for x in (-4.5, 4.5):
        c.add("detail", '<circle cx="%s" cy="32.4" r="1.9" fill="%s" stroke="%s" stroke-width="0.6"/>' % (f(x), METAL, OUTLINE))
    c.write()


def armored():
    c = Car("armored", 22, 38)
    c.wheels([(-21, -23, 5, 14), (16, -23, 5, 14), (-21, 10, 5, 14), (16, 10, 5, 14)])
    body = smooth(sym([(14, -31), (17.6, -30), (19, -27), (19.2, -10), (19.2, 26), (18.4, 30.8), (15, 32.3)]))
    clip = c.shell(body, shade=0.55)
    c.shine(clip, [(-15, -26), (-12, -27), (-12, 25), (-15.5, 27)], 0.18)
    # para-choque de impulsão
    c.add("detail", rrect(-17, -35.5, 34, 5, 1.2) + ' fill="#4c4f55" stroke="%s" stroke-width="0.9"/>' % OUTLINE)
    for x in (-11, -1.5, 8):
        c.add("detail", rrect(x, -36.6, 3, 7, 0.8) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (METAL, OUTLINE))
    c.lamp([(10, -29.5), (16, -29.5), (16, -26.5), (10, -26.5)], HEAD)
    c.part(poly(sym([(15.5, -25.5), (15.5, -21)])), tone="#00000033")
    c.glint_x = -2
    c.glass(rounded(sym([(12, -19.5), (13.4, -15), (13, -11)])), 1.0)
    for x in (-4, 4):
        c.add("detail", '<path d="M%s,-19.6 V-11" stroke="%s" stroke-width="1.3"/>' % (f(x), OUTLINE))
    c.mirrors(-15.5, 19)
    c.part(rounded(sym([(15.6, -9.5), (16, 0), (16, 20), (15.4, 27.5)])), tone="#0000001f")
    for y in (-1, 13):
        c.panel_line([(-15.5, y), (15.5, y)], 0.8, 0.6, both=False)
    # escotilha
    c.add("detail", '<circle cx="0" cy="6" r="7.6" fill="#00000055" stroke="%s" stroke-width="1"/>' % OUTLINE)
    c.add("accent", '<circle cx="0" cy="6" r="4.2" fill="#fff"/>')
    c.add("detail", '<circle cx="0" cy="6" r="4.2" fill="#00000030" stroke="%s" stroke-width="0.8"/>' % OUTLINE)
    c.add("detail", rrect(-3, 5, 6, 2, 0.6) + ' fill="%s"/>' % OUTLINE)
    for x, y in ((-12.5, -6), (12.5, -6), (-12.5, 24), (12.5, 24), (-12.5, 9), (12.5, 9)):
        c.add("detail", '<circle cx="%s" cy="%s" r="1.6" fill="%s" stroke="%s" stroke-width="0.5"/>' % (f(x), f(y), METAL, OUTLINE))
    c.lamp([(11, 28), (16.5, 28), (16.5, 30.5), (11, 30.5)], TAIL)
    c.write()


def pickup():
    c = Car("pickup", 22, 38)
    c.wheels([(-21, -26, 5, 14), (16, -26, 5, 14), (-21, 14, 5, 14), (16, 14, 5, 14)])
    body = smooth(sym([(10, -35), (15.5, -34), (18.2, -31), (19.2, -24), (19, -12), (19.2, 10), (19.2, 32),
                       (18, 35), (12, 35.6)]))
    clip = c.shell(body)
    c.shine(clip, [(-14, -30), (-11, -32), (-11, 8), (-15, 8), (-15, -20)], 0.28)
    c.add("detail", rrect(-9, -35.6, 18, 3.4, 1) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    for x in (-6, -3, 0, 3, 6):
        c.add("detail", '<path d="M%s,-35 V-32.8" stroke="%s" stroke-width="0.6"/>' % (f(x), METAL))
    c.lamp([(10.5, -33.2), (16, -32), (16.5, -28.8), (11, -29.8)], HEAD)
    c.panel_line([(5, -30), (6, -18.5)])
    c.mirrors(-15.5, 19)
    c.glint_x = -3
    c.glass(rounded(sym([(13, -17.5), (15, -11), (15.2, -6.5), (9, -6)])))
    c.part(rounded(sym([(14.2, -6.5), (14.4, 1), (14, 6.5)])))
    c.glass(rounded(sym([(13.6, 6.5), (13, 9.4)])), 0.9, False)
    # caçamba
    c.add("detail", rrect(-16, 11.5, 32, 21, 1.4) + ' fill="#2a2620" stroke="%s" stroke-width="1"/>' % OUTLINE)
    for y in (16, 20.5, 25, 29.5):
        c.add("detail", rrect(-14.5, y, 29, 1.6, 0.6) + ' fill="#3d372e"/>')
    for x in (-17.4, 14.4):
        c.add("accent", rrect(x, 10.6, 3, 22.5, 1) + ' fill="#fff"/>')
        c.add("detail", rrect(x, 10.6, 3, 22.5, 1) + ' fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.add("accent", rrect(-16, 10, 32, 2.4, 1) + ' fill="#fff"/>')
    c.add("detail", rrect(-16, 10, 32, 2.4, 1) + ' fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.add("body", rrect(-15.5, 32, 31, 3.2, 1) + ' fill="#fff"/>')
    c.add("detail", rrect(-15.5, 32, 31, 3.2, 1) + ' fill="#00000022" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.lamp([(15, 29.5), (18, 29.5), (18, 33.5), (15, 33.5)], TAIL)
    c.write()


def muscle():
    c = Car("muscle", 21, 36)
    c.wheels([(-19.5, -23, 4.5, 12), (15, -23, 4.5, 12), (-20.5, 9, 5.5, 14.5), (15, 9, 5.5, 14.5)])
    body = smooth(sym([(10, -33.4), (14.5, -33), (16.8, -30), (17.6, -22), (17.4, -12), (17.2, 2), (17.8, 14),
                       (17.8, 25), (16.8, 31), (13, 33.2), (8, 33.5)]))
    clip = c.shell(body)
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-7" y="-40" width="5" height="80" fill="#fff"/>'
                    '<rect x="2" y="-40" width="5" height="80" fill="#fff"/></g>' % clip)
    c.shine(clip, [(-13.5, -28), (-11, -30), (-10.5, 10), (-13, 28), (-15.5, 26), (-15, -20)], 0.22)
    # entrada de ar do capô
    c.fill(rounded(sym([(5.2, -26.5), (6, -20), (6, -15)])), "#00000066", 0.8)
    c.add("detail", rrect(-4, -25, 8, 3, 0.8) + ' fill="%s"/>' % OUTLINE)
    c.mirrors(-8.5, 16.8)
    c.glint_x = -3
    c.glass(rounded(sym([(12, -10.5), (14, -5), (14, 0.5), (8, 1.5)])))
    c.part(rounded(sym([(13, 1), (13, 7), (12, 13), (8, 13.6)])))
    c.add("accent", '<g clip-path="url(#%s)"><rect x="-7" y="0" width="5" height="14" fill="#fff"/>'
                    '<rect x="2" y="0" width="5" height="14" fill="#fff"/></g>' % clip)
    c.glass(rounded(sym([(11.5, 14), (12, 18), (8, 20.5)])))
    c.add("detail", rrect(-15, 25, 30, 2.6, 1) + ' fill="%s" stroke="%s" stroke-width="0.6"/>' % (DARK, OUTLINE))
    for x in (-11.5, 11.5):
        c.add("detail", '<circle cx="%s" cy="-29.4" r="4.6" fill="%s" fill-opacity="0.25"/>' % (f(x), HEAD))
    c.round_lamp(11.5, -29.4, 3.0, HEAD)
    c.lamp([(5, 29.6), (15, 29.6), (14.5, 31.8), (5, 31.8)], TAIL)
    for x in (-10, 10):
        c.add("detail", '<circle cx="%s" cy="33.8" r="1.9" fill="%s" stroke="%s" stroke-width="0.6"/>' % (f(x), METAL, OUTLINE))
    c.write()


def coupe():
    c = Car("coupe", 21, 37)
    c.wheels([(-19.5, -23, 4.5, 11.5), (15, -23, 4.5, 11.5), (-20, 9, 5, 14), (15, 9, 5, 14)])
    body = smooth(sym([(3, -35), (9, -34), (14, -31), (17, -25), (17.4, -18), (16, -8), (16.4, 2),
                       (18, 12), (18.2, 22), (16.2, 30), (10.5, 34), (3, 34.6)]))
    clip = c.shell(body)
    c.shine(clip, [(-12, -29), (-9, -31), (-7, -17), (-9, 12), (-12.5, 28), (-15, 26), (-14, 0), (-13.5, -22)], 0.28)
    c.panel_line([(4, -32), (9, -16.5)])
    c.lamp([(9, -31.5), (14, -28.5), (14.5, -25.5), (8.5, -28.8)], HEAD)
    c.mirrors(-12, 16.2)
    c.glint_x = -3
    c.glass(rounded(sym([(10.5, -15), (13.6, -9), (14, -2), (13, 9), (9, 10.5)])))
    c.part(rounded(sym([(9, -3.5), (9.4, 3), (8.4, 8.5)])))
    for s in (1, -1):
        c.add("accent", rrect(15 if s > 0 else -18, -1, 3, 11, 1) + ' fill="#fff"/>')
        c.add("detail", rrect(15 if s > 0 else -18, -1, 3, 11, 1) + ' fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.glass(rounded(sym([(10, 12), (10, 18), (9, 24.5)])), 1.0, False, dark=True)
    for y in (14.5, 17.5, 20.5, 23):
        c.add("detail", '<path d="M-8.6,%s H8.6" stroke="%s" stroke-width="1.1"/>' % (f(y), OUTLINE))
    c.add("detail", '<path d="M0,12 V24.5" stroke="%s" stroke-width="1.1"/>' % OUTLINE)
    for s in (1, -1):
        c.fill(poly([(11 * s, 12), (14 * s, 13), (14 * s, 23), (11 * s, 23)]), DARK, 0.7)
        for y in (15, 18, 21):
            c.add("detail", '<path d="M%s,%s H%s" stroke="%s" stroke-width="0.9"/>' % (f(11.3 * s), f(y), f(13.7 * s), TAIL))
    c.add("accent", rrect(-7, 29, 14, 3, 1) + ' fill="#fff"/>')
    c.add("detail", rrect(-7, 29, 14, 3, 1) + ' fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.lamp([(8, 28.4), (14.5, 27.8), (13.5, 30.6), (8, 31)], TAIL)
    c.write()


def f1():
    c = Car("f1", 23, 40)
    # braços da suspensão
    for s in (1, -1):
        for a, b in (((5, -22), (14, -21)), ((5, -17), (14, -20)), ((10, 16), (14, 20)), ((9, 22), (14, 21))):
            c.add("base", '<path d="M%s,%s L%s,%s" stroke="%s" stroke-width="1.3"/>' % (f(a[0] * s), f(a[1]), f(b[0] * s), f(b[1]), OUTLINE))
    c.wheels([(-21.5, -28.5, 8, 14), (13.5, -28.5, 8, 14), (-22.5, 12, 9, 17), (13.5, 12, 9, 17)])
    body = smooth(sym([(2.2, -35.5), (4, -28), (5.6, -18), (7.5, -9.5), (12.5, -4), (13.4, 4), (13, 18),
                       (10.5, 26), (7, 31), (3, 32)]))
    clip = c.shell(body, shade=0.45)
    c.shine(clip, [(-3, -32), (-1.5, -32), (-2, -12), (-8, 4), (-9.5, 18), (-11.5, 16), (-10, 0), (-4, -14)], 0.35)
    # asa dianteira
    wing = smooth(sym([(19, -38.8), (19.4, -34.5), (14, -33.6), (0, -34.6)]))
    c.add("accent", '<path d="%s" fill="#fff"/>' % wing)
    c.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-width="0.9"/>' % (wing, OUTLINE))
    for x in (-20.4, 17.4):
        c.add("detail", rrect(x, -40, 3, 7.4, 0.8) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    # entradas laterais
    for s in (1, -1):
        c.add("accent", rrect(9 if s > 0 else -12, 2, 3, 15, 1) + ' fill="#fff"/>')
        c.add("detail", rrect(9 if s > 0 else -12, 2, 3, 15, 1) + ' fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
        c.add("detail", rrect(8 if s > 0 else -12, -2.6, 4, 3.4, 1) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    # cockpit + capacete + halo
    c.fill(rounded(sym([(4.2, -11.5), (5.2, -4), (5, 5.5)])), DARK, 0.9)
    c.add("detail", '<circle cx="0" cy="-3" r="3.4" fill="#ffd23a" stroke="%s" stroke-width="0.8"/>' % OUTLINE)
    c.add("detail", rrect(-2.2, -5.2, 4.4, 1.6, 0.6) + ' fill="#7fd8f5"/>')
    c.add("detail", '<path d="M-6.5,-1.5 A6.5,6.5 0 0 1 6.5,-1.5" fill="none" stroke="%s" stroke-width="1.8"/>' % OUTLINE)
    c.add("detail", '<path d="M0,-8 V-14" stroke="%s" stroke-width="1.8"/>' % OUTLINE)
    c.panel_line([(0, 8), (0, 26)], 0.8, 0.6, both=False)
    # asa traseira
    c.add("detail", rrect(-17, 28.5, 34, 6.5, 1.4) + ' fill="%s" stroke="%s" stroke-width="0.9"/>' % (DARK, OUTLINE))
    c.add("accent", rrect(-16, 29.2, 32, 2.2, 1) + ' fill="#fff"/>')
    c.add("detail", rrect(-2, 35, 4, 2.2, 0.6) + ' fill="%s" stroke="%s" stroke-width="0.6"/>' % (TAIL, OUTLINE))
    c.write()


def legend():
    c = Car("legend", 22, 39)
    c.wheels([(-21, -16, 5, 13), (16, -16, 5, 13), (-21, 12, 5, 14), (16, 12, 5, 14)])
    body = smooth(sym([(0, -37), (5, -33), (10, -26), (15, -14), (18.4, -2), (19, 12), (18.4, 24), (15, 31),
                       (8, 34.4)]))
    clip = c.shell(body, shade=0.4)
    c.shine(clip, [(-4, -32), (-2.5, -32), (-6, -14), (-12, 4), (-14, 22), (-16, 20), (-14, 0), (-8, -18)], 0.22)
    # cockpit em gota
    c.glint_x = -3
    c.glass(rounded(sym([(0, -20), (5, -14), (8, -5), (8.4, 7), (6.4, 13.5), (0, 15.5)])), 1.1, True, dark=True)
    c.mirrors(-8, 16.4)
    # linhas de neon (cor de detalhe)
    for d in ("M0,-34 L0,-22",):
        c.add("accent", '<path d="%s" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>' % d)
    for s in (1, -1):
        c.add("accent", '<path d="%s" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>'
              % smooth([(14 * s, -1), (14.6 * s, 10), (12 * s, 22)], False))
        c.add("accent", '<path d="%s" fill="none" stroke="#fff" stroke-width="1.2" stroke-linecap="round"/>'
              % smooth([(4 * s, -30), (9 * s, -24), (12 * s, -17)], False))
    c.add("accent", '<path d="%s" fill="none" stroke="#fff" stroke-width="1.2"/>' % body)
    for x in (-7, 7):
        c.add("detail", '<circle cx="%s" cy="32" r="3.8" fill="%s" stroke="%s" stroke-width="0.6"/>' % (f(x), OUTLINE, OUTLINE))
        c.add("accent", '<circle cx="%s" cy="32" r="2.8" fill="#fff"/>' % f(x))
    c.write()


def van():
    c = Car("van", 22, 38)
    c.wheels([(-21, -26, 5, 13), (16, -26, 5, 13), (-21, 16, 5, 13), (16, 16, 5, 13)])
    body = smooth(sym([(12, -35.5), (16.5, -34.4), (18.8, -31), (19.2, -24), (19.2, 30), (18.4, 34.2), (15, 35.4)]))
    clip = c.shell(body)
    c.shine(clip, [(-15, -29), (-12, -31), (-12, 30), (-15, 31)], 0.2)
    c.add("detail", rrect(-8, -35.4, 16, 2.8, 1) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    c.lamp([(10, -33.6), (15.5, -33), (16, -30), (10.5, -30.5)], HEAD)
    c.glint_x = -3
    c.glass(rounded(sym([(14, -29), (16, -24), (15.6, -19.5), (9, -19)])))
    c.mirrors(-26, 19)
    c.part(rounded(sym([(15.5, -18.5), (16, -10), (16, 26), (15.4, 31.5)])), tone="#ffffff20")
    for y in (-6, 7, 20):
        c.panel_line([(-13.5, y), (13.5, y)], 0.8, 0.5, both=False)
    c.add("detail", rrect(-10, -14, 20, 4, 1.2) + ' fill="%s" stroke="%s" stroke-width="0.6"/>' % (METAL, OUTLINE))
    c.lamp([(13.5, 30), (17, 30), (17, 34), (13.5, 34)], TAIL)
    c.write()


def truck():
    c = Car("truck", 24, 66)
    c.wheels([(-22, -56, 4, 12), (18, -56, 4, 12),
              (-23, 30, 4, 12), (19, 30, 4, 12), (-23, 45, 4, 12), (19, 45, 4, 12)])
    c.add("base", rrect(-6, -39, 12, 9, 1) + ' fill="%s" stroke="%s" stroke-width="0.8"/>' % (DARK, OUTLINE))
    cab = smooth(sym([(12, -62.6), (17, -61.6), (19.2, -58), (19.4, -40), (18, -35.6), (14, -35)]))
    clip = c.shell(cab)
    c.shine(clip, [(-15, -57), (-12, -59), (-12, -38), (-15, -38)], 0.25)
    c.add("detail", rrect(-9, -63, 18, 2.8, 1) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    c.lamp([(12, -61.4), (17, -60.6), (17.4, -57.6), (12, -58.2)], HEAD)
    c.glint_x = -3
    c.glass(rounded(sym([(16, -57), (16.6, -52), (16, -49.5), (9, -49)])))
    c.part(rounded(sym([(14.6, -48.4), (15.4, -44), (14.6, -39)])), tone="#00000022")
    for x in (19.4, -23.4):
        c.add("detail", rrect(x, -55, 4, 6, 1) + ' fill="%s" stroke="%s" stroke-width="0.7"/>' % (DARK, OUTLINE))
    # baú (cor de detalhe)
    trailer = smooth(sym([(19.5, -32.4), (21.2, -31), (21.2, 60), (19.8, 62.4)]))
    tclip = c.uid("c")
    c.defs.append('<clipPath id="%s"><path d="%s"/></clipPath>' % (tclip, trailer))
    c.add("accent", '<path d="%s" fill="#fff"/>' % trailer)
    g = c.uid("g")
    c.defs.append('<linearGradient id="%s" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000" stop-opacity="0.35"/>'
                  '<stop offset="0.15" stop-color="#000" stop-opacity="0.08"/><stop offset="0.5" stop-color="#000" stop-opacity="0"/>'
                  '<stop offset="0.85" stop-color="#000" stop-opacity="0.12"/><stop offset="1" stop-color="#000" stop-opacity="0.4"/></linearGradient>' % g)
    c.add("detail", '<g clip-path="url(#%s)"><path d="%s" fill="url(#%s)"/></g>' % (tclip, trailer, g))
    for y in range(-24, 60, 10):
        c.add("detail", '<rect x="-18" y="%d" width="36" height="1.4" fill="#000" fill-opacity="0.16"/>' % y)
    c.shine(tclip, [(-17, -29), (-14, -29), (-14, 58), (-17, 58)], 0.18)
    c.add("detail", '<path d="%s" fill="none" stroke="%s" stroke-width="1.5"/>' % (trailer, OUTLINE))
    c.add("detail", rrect(-21, 58, 42, 4.2, 1.2) + ' fill="#00000055" stroke="%s" stroke-width="0.8"/>' % OUTLINE)
    c.lamp([(14, 58.6), (19, 58.6), (19, 61.4), (14, 61.4)], TAIL)
    c.write()


def bus():
    c = Car("bus", 24, 70)
    c.wheels([(-23, -50, 4, 14), (19, -50, 4, 14), (-23, 38, 4, 14), (19, 38, 4, 14)])
    body = smooth(sym([(15, -68.4), (19.6, -67.4), (21.2, -64), (21.2, 64), (19.6, 67.6), (15, 68.4)]))
    clip = c.shell(body, shade=0.45)
    c.shine(clip, [(-17, -60), (-14, -61), (-14, 62), (-17, 62)], 0.16)
    c.glint_x = -4
    c.glass(rounded(sym([(17, -65.5), (18.4, -61), (18, -56.5), (10, -56)])))
    for x in (21.4, -23.6):
        c.add("detail", rrect(x, -62.5, 2.2, 5, 0.8) + ' fill="%s" stroke="%s" stroke-width="0.6"/>' % (DARK, OUTLINE))
    for y in range(-50, 62, 14):
        for x in (16.2, -19.2):
            c.glass("M%s,%s h3 v10.5 h-3 Z" % (f(x), f(y)), 0.7, False)
    # teto: ar-condicionado e escotilhas
    c.part(rounded(sym([(11, -42.5), (11.6, -33), (11, -23.5)])), tone="#ffffff55")
    for y in (-38, -33, -28):
        c.panel_line([(-9, y), (9, y)], 0.8, 0.5, both=False)
    c.part(rounded(sym([(7, 29.6), (7.6, 35), (7, 40.4)])), tone="#ffffff55")
    for y in (-5, 8):
        c.add("accent", rrect(-14, y, 28, 3, 1) + ' fill="#fff"/>')
        c.add("detail", rrect(-14, y, 28, 3, 1) + ' fill="none" stroke="%s" stroke-width="0.7"/>' % OUTLINE)
    c.lamp([(13, -67.6), (18, -67.2), (18, -65), (13, -65.2)], HEAD)
    c.lamp([(13, 64.6), (18, 64.6), (18, 67.4), (13, 67.4)], TAIL)
    c.write()


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
    print("carros gerados em", os.path.normpath(OUT_DIR))
