# -*- coding: utf-8 -*-
"""联机 VS 角色卡 v1 占位件生成器（程序化矢量+元素色剪影）。

依据：美术规划/联机01移交_VS角色卡与播报图标.md（S4）
路线：主人 2026-10-27 批「程序化矢量+剪影」——零素材成本/零版权/无限高清。
产出：
  assets/ui/frames/net_vs_*.png      交付件（2x 设计分辨率）
  <会话可视化目录>/vs_v1_preview/     预览拷贝（1x，仅供网页样张，非交付物）
铁律：交付件只是占位，观感归主人实机终验；正式卡面=二期另批。
"""
import os, math, json, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = r"E:\项目储存\决竞球battle-ball"
ASSET_DIR = os.path.join(ROOT, "assets", "ui", "frames")
VIZ = r"C:\Users\Lenovo\.zcode\v2\visualizations\970e3e78308f9f8ede57e1cae25e98a10085c22c22d22288114ca613e8661312"
PREVIEW = os.path.join(VIZ, "vs_v1_preview")

FINAL = 2   # 交付倍率（2x）
K = 4       # 绘制超采样倍数（设计坐标 × K，再降采样抗锯齿）

def C(hexstr, a=255):
    h = hexstr.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

def with_a(c, a):
    return (c[0], c[1], c[2], a)

TEAM_ALLY  = C('6FD3FF')   # 己方·冰蓝（协会蓝白冷调）
TEAM_ENEMY = C('FF6B4A')   # 敌方·熔橙（竞技清晰度撞色）
GOLD  = C('E8C15A')        # 品牌金（单金色纪律：只上关键件）
WHITE = C('E8EEF6')

# 六元素 UI 口径临时色（v5 §9.2 口径示意，1027-2 定版后经色板单例一键换）
ELEMENTS = {
    'shenli':  ('神力', C('C9A227')), 'miemie': ('泯灭', C('8A6CB8')),
    'leihuo':  ('雷火', C('E06A3A')), 'jumu':   ('巨木', C('4E9E5F')),
    'gentu':   ('艮土', C('8A6A45')), 'xuanbing': ('玄冰', C('5AB8D4')),
}

def chamfer(x, y, w, h, c):
    """切角矩形多边形（棱角斜切形状语言，替代圆角）"""
    c = max(1, min(c, w // 2 - 1, h // 2 - 1))
    return [(x + c, y), (x + w - c, y), (x + w, y + c), (x + w, y + h - c),
            (x + w - c, y + h), (x + c, y + h), (x, y + h - c), (x, y + c)]

class Layer:
    """设计坐标画布：绘制按 K 超采样，done() 缩到目标倍率"""
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new('RGBA', (w * K, h * K), (0, 0, 0, 0))
    @property
    def d(self):
        return ImageDraw.Draw(self.img)
    def s(self, pts):
        return [(px * K, py * K) for px, py in pts]
    def done(self, scale=FINAL):
        return self.img.resize((int(self.w * scale), int(self.h * scale)), Image.LANCZOS)

def glow(layer, draw_fn, radius, alpha=1.0):
    """在副本上画形状→高斯模糊→叠回，做克制辉光"""
    lay = Image.new('RGBA', layer.img.size, (0, 0, 0, 0))
    draw_fn(_Proxy(lay))
    lay = lay.filter(ImageFilter.GaussianBlur(radius * K))
    if alpha < 1.0:
        lay.putalpha(lay.getchannel('A').point(lambda v: int(v * alpha)))
    layer.img.alpha_composite(lay)

class _Proxy:
    def __init__(self, img): self.img = img
    @property
    def d(self): return ImageDraw.Draw(self.img)
    def s(self, pts): return [(px * K, py * K) for px, py in pts]

def vgrad(w, h, top, bottom):
    """垂直渐变底图（设计坐标 × K）"""
    g = Image.linear_gradient('L').resize((w * K, h * K))
    a = Image.new('RGBA', (w * K, h * K), top)
    b = Image.new('RGBA', (w * K, h * K), bottom)
    return Image.composite(b, a, g)

# ---------------------------------------------------------------- 卡框 300x420
def gen_card(team, plate, recess):
    W, H = 300, 420
    L = Layer(W, H); d = L.d
    # 外板：切角 16
    outer = chamfer(1, 1, W - 2, H - 2, 16)
    d.polygon(L.s(outer), fill=plate)
    d.line(L.s(outer + [outer[0]]), fill=team, width=2 * K, joint='curve')
    # 内侧白发丝线（机构规程线）
    inner = chamfer(5, 5, W - 10, H - 10, 13)
    d.line(L.s(inner + [inner[0]]), fill=with_a(WHITE, 26), width=1 * K, joint='curve')
    # 顶部金登记片（协会机构感，全局唯一金）
    d.polygon(L.s([(18, 6), (58, 6), (52, 12), (18, 12)]), fill=GOLD)
    # 立绘窗：(10,10) 280x282，切角 10
    win = chamfer(10, 10, 280, 282, 10)
    d.polygon(L.s(win), fill=recess)
    d.line(L.s(win + [win[0]]), fill=with_a(team, 70), width=1 * K, joint='curve')
    # 窗角 L 刻度纹印
    tick = with_a(team, 150)
    for cx, cy, dx, dy in [(12, 12, 1, 1), (288, 12, -1, 1), (12, 290, 1, -1), (288, 290, -1, -1)]:
        d.line(L.s([(cx, cy + dy * 14), (cx, cy), (cx + dx * 14, cy)]), fill=tick, width=2 * K, joint='curve')
    # 名字牌：(20,302) 260x42，切角 8
    np_ = chamfer(20, 302, 260, 42, 8)
    d.polygon(L.s(np_), fill=C('16233A'))
    d.line(L.s(np_ + [np_[0]]), fill=with_a(WHITE, 20), width=1 * K, joint='curve')
    d.polygon(L.s([(28, 313), (38, 323), (28, 333)]), fill=GOLD)  # 金导向箭头
    d.line(L.s([(30, 340), (272, 340)]), fill=with_a(team, 60), width=1 * K)
    # 元灵小框：(20,354) 56x56，切角 8
    sp = chamfer(20, 354, 56, 56, 8)
    d.polygon(L.s(sp), fill=C('0A1220'))
    d.line(L.s(sp + [sp[0]]), fill=with_a(team, 120), width=1 * K, joint='curve')
    # 元素条：(86,366) 194x32
    el = chamfer(86, 366, 194, 32, 6)
    d.polygon(L.s(el), fill=C('10192B'))
    d.line(L.s(el + [el[0]]), fill=with_a(WHITE, 16), width=1 * K, joint='curve')
    return L.done()

# ---------------------------------------------------------------- 剪影 272x282
def gen_silhouette():
    W, H = 272, 282
    L = Layer(W, H); d = L.d
    body = C('DFE9F4')
    d.ellipse(L.s([(114, 22), (158, 66)]), fill=body)                    # 头
    d.rectangle(L.s([(128, 60), (144, 80)]), fill=body)                  # 颈
    d.polygon(L.s([(98, 80), (174, 80), (162, 170), (110, 170)]), fill=body)   # 躯干
    d.polygon(L.s([(98, 86), (76, 118), (86, 126), (110, 96)]), fill=body)     # 左上臂
    d.polygon(L.s([(76, 118), (64, 148), (74, 154), (88, 128)]), fill=body)    # 左前臂
    d.ellipse(L.s([(62, 148), (82, 166)]), fill=body)                    # 左手
    d.polygon(L.s([(174, 86), (206, 70), (212, 82), (182, 98)]), fill=body)    # 右上臂
    d.polygon(L.s([(206, 70), (232, 58), (238, 70), (214, 84)]), fill=body)    # 右前臂
    d.ellipse(L.s([(228, 52), (246, 70)]), fill=body)                    # 右手
    d.polygon(L.s([(108, 166), (164, 166), (172, 214), (138, 214), (136, 192), (134, 214), (100, 214)]), fill=body)  # 短裤
    d.polygon(L.s([(102, 212), (124, 212), (116, 262), (100, 260)]), fill=body)  # 左腿
    d.polygon(L.s([(148, 212), (170, 212), (172, 262), (156, 260)]), fill=body)  # 右腿
    d.polygon(L.s([(90, 262), (116, 262), (114, 272), (92, 272)]), fill=body)    # 左足
    d.polygon(L.s([(152, 262), (178, 262), (178, 272), (154, 272)]), fill=body)  # 右足
    return L.done()

def hexpts(cx, cy, r, rot=30):
    return [(cx + r * math.cos(math.radians(rot + 60 * i)),
             cy + r * math.sin(math.radians(rot + 60 * i))) for i in range(6)]

# ---------------------------------------------------------------- VS 中心件 240x170
def gen_emblem():
    W, H = 240, 170
    L = Layer(W, H); d = L.d
    # 背板：宽切角板
    back = chamfer(20, 25, 200, 120, 18)
    d.polygon(L.s(back), fill=C('0C1524', 225))
    d.line(L.s(back + [back[0]]), fill=with_a(GOLD, 180), width=2 * K, joint='curve')
    # 对峙括弧（面向两侧队伍；「VS」字样由实现用主题字体叠加，不在贴图烤字）
    d.line(L.s([(64, 62), (40, 85), (64, 108)]), fill=with_a(WHITE, 210), width=6 * K, joint='curve')
    d.line(L.s([(176, 62), (200, 85), (176, 108)]), fill=with_a(WHITE, 210), width=6 * K, joint='curve')
    # 核心右上电弧火花
    def arc(t):
        pts = [(150, 52), (162, 44), (156, 62), (170, 52)]
        t.d.line(t.s(pts), fill=C('BFE9FF', 220), width=2 * K, joint='curve')
    glow(L, arc, 3, 0.8)
    # 中央晶核：六边形（溯源之核母题）
    def core(t):
        t.d.polygon(t.s(hexpts(120, 85, 42)), outline=GOLD, width=2 * K)
        t.d.polygon(t.s(hexpts(120, 85, 26)), outline=C('BFE9FF', 200), width=1 * K)
    glow(L, core, 4, 0.7)
    d.polygon(L.s(hexpts(120, 85, 42)), fill=with_a(C('0A1424'), 200))
    d.polygon(L.s(hexpts(120, 85, 42)), outline=GOLD, width=2 * K)
    d.polygon(L.s(hexpts(120, 85, 26)), outline=C('BFE9FF', 200), width=1 * K)
    d.ellipse(L.s([(106, 71), (134, 99)]), fill=C('EAF6FF', 235))       # 核心亮斑
    d.ellipse(L.s([(112, 77), (128, 93)]), fill=C('FFFFFF', 255))
    return L.done()

# ---------------------------------------------------------------- 背景分色 1440x900
def gen_bg():
    W, H = 1440, 900
    # 渐变底图直接落到交付倍率（2x），后续叠层全部同尺寸
    base = vgrad(W, H, C('0A111E'), C('0E1B2E')).resize((W * FINAL, H * FINAL), Image.LANCZOS).convert('RGBA')
    # 对角分色叠层（左己方冷调 / 右敌方暖调，低透明度）
    ov = Layer(W, H)
    ov.d.polygon(ov.s([(0, 900), (0, 0), (760, 0), (640, 900)]), fill=with_a(C('3C78B4'), 26))
    base.alpha_composite(ov.done())
    ov2 = Layer(W, H)
    ov2.d.polygon(ov2.s([(760, 0), (1440, 0), (1440, 900), (640, 900)]), fill=with_a(C('B44A3C'), 26))
    base.alpha_composite(ov2.done())
    # 中缝金线（沿分割角）
    dd = ImageDraw.Draw(base)
    dd.line([(int(720 * FINAL), 0), (int(676 * FINAL), 900 * FINAL)],
            fill=with_a(GOLD, 80), width=2 * FINAL)
    # 星点（恒源星系氛围，稀疏）
    rnd = random.Random(7)
    for _ in range(110):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.choice([0.6, 0.8, 1.0, 1.4])
        a = rnd.randint(40, 150)
        dd.ellipse([(x * FINAL - r * FINAL, y * FINAL - r * FINAL),
                    (x * FINAL + r * FINAL, y * FINAL + r * FINAL)],
                   fill=(220, 235, 250, a))
    # 星云淡斑（源雾）
    neb = Image.new('RGBA', base.size, (0, 0, 0, 0))
    nd = ImageDraw.Draw(neb)
    for cx, cy, rx, ry, col in [(300, 200, 260, 140, (90, 110, 200, 16)),
                                (1150, 650, 300, 160, (180, 90, 70, 14)),
                                (760, 120, 220, 110, (140, 120, 200, 12))]:
        nd.ellipse([(cx * FINAL - rx * FINAL, cy * FINAL - ry * FINAL),
                    (cx * FINAL + rx * FINAL, cy * FINAL + ry * FINAL)], fill=col)
    neb = neb.filter(ImageFilter.GaussianBlur(60 * FINAL))
    base.alpha_composite(neb)
    # 暗角：alpha 叠加（不能 Image.composite 替换，会清掉底图像素）
    vg = Image.radial_gradient('L').resize(base.size)
    shade = Image.new('RGBA', base.size, (2, 4, 8, 255))
    shade.putalpha(vg.point(lambda v: int(v * 130 / 255)))
    base.alpha_composite(shade)
    return base

# ---------------------------------------------------------------- 加载条 480x44
SLOT_N, SLOT_W, SLOT_H, GAP, X0, Y0 = 6, 64, 26, 9, 24, 9
def gen_progress():
    W, H = 480, 44
    L = Layer(W, H); d = L.d
    # 两端斜切护轨
    d.line(L.s([(2, 34), (12, 10), (16, 10)]), fill=with_a(WHITE, 60), width=2 * K, joint='curve')
    d.line(L.s([(478, 34), (468, 10), (464, 10)]), fill=with_a(WHITE, 60), width=2 * K, joint='curve')
    for i in range(SLOT_N):
        x = X0 + i * (SLOT_W + GAP)
        p = chamfer(x, Y0, SLOT_W, SLOT_H, 5)
        d.polygon(L.s(p), fill=C('0A1424', 235))
        d.line(L.s(p + [p[0]]), fill=with_a(TEAM_ALLY, 55), width=1 * K, joint='curve')
        d.line(L.s([(x + 8, Y0 + 5), (x + SLOT_W - 8, Y0 + 5)]), fill=with_a(WHITE, 22), width=1 * K)
    return L.done()

def gen_slot_lit():
    W, H = SLOT_W, SLOT_H
    L = Layer(W, H); d = L.d
    g = Image.linear_gradient('L').rotate(90, expand=True).resize((W * K, H * K))
    a = Image.new('RGBA', (W * K, H * K), GOLD)
    b = Image.new('RGBA', (W * K, H * K), TEAM_ALLY)
    fill = Image.composite(b, a, g)
    mask = Image.new('L', (W * K, H * K), 0)
    outline = chamfer(1, 1, W - 2, H - 2, 5)
    ImageDraw.Draw(mask).polygon(L.s(outline), fill=255)
    L.img.paste(fill, (0, 0), mask)
    def rim(t):
        t.d.line(t.s(outline + [outline[0]]), fill=GOLD, width=2 * K, joint='curve')
    glow(L, rim, 3, 0.8)
    d.line(L.s(outline + [outline[0]]), fill=GOLD, width=2 * K, joint='curve')
    return L.done()

# ---------------------------------------------------------------- 主流程
def main():
    os.makedirs(ASSET_DIR, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    jobs = {
        'net_vs_cardframe_ally.png':      gen_card(TEAM_ALLY, C('0E1826', 238), C('05090F', 255)),
        'net_vs_cardframe_enemy.png':     gen_card(TEAM_ENEMY, C('1A0F12', 238), C('0B0608', 255)),
        'net_vs_portrait_silhouette.png': gen_silhouette(),
        'net_vs_emblem.png':              gen_emblem(),
        'net_vs_bg_split.png':            gen_bg(),
        'net_vs_progress.png':            gen_progress(),
        'net_vs_progress_slot_lit.png':   gen_slot_lit(),
    }
    report = {}
    for name, img in jobs.items():
        path = os.path.join(ASSET_DIR, name)
        img.save(path)
        prev = img.resize((img.width // FINAL, img.height // FINAL), Image.LANCZOS)
        if name.endswith('bg_split.png'):
            prev.convert('RGB').save(os.path.join(PREVIEW, name.replace('.png', '.jpg')), quality=82)
        else:
            prev.save(os.path.join(PREVIEW, name))
        report[name] = {'export': list(img.size), 'bytes': os.path.getsize(path)}
    # 预览用：六元素染色剪影（1x，仅供样张，非交付物）
    sil = Image.open(os.path.join(PREVIEW, 'net_vs_portrait_silhouette.png')).convert('RGBA')
    for key, (zh, col) in ELEMENTS.items():
        solid = Image.new('RGBA', sil.size, col)
        tinted = ImageChops.multiply(sil, solid)
        tinted.putalpha(sil.getchannel('A'))
        tinted.save(os.path.join(PREVIEW, f'preview_sil_{key}.png'))
    print(json.dumps(report, ensure_ascii=False, indent=1))
    print('design-spec:', json.dumps({
        'card': {'size': [300, 420], 'portrait_win': [10, 10, 280, 282],
                 'nameplate': [20, 302, 260, 42], 'spirit_slot': [20, 354, 56, 56],
                 'element_bar': [86, 366, 194, 32]},
        'progress': {'size': [480, 44], 'slots': SLOT_N, 'slot': [SLOT_W, SLOT_H],
                     'x0': X0, 'y0': Y0, 'gap': GAP},
        'emblem': [240, 170], 'bg': [1440, 900], 'silhouette': [272, 282],
    }, ensure_ascii=False))

if __name__ == '__main__':
    main()
