# -*- coding: utf-8 -*-
"""联机播报角标族+弱网图标 v1 生成器（程序化矢量，第二批）。

依据：美术规划/联机01移交_VS角色卡与播报图标.md 需求 2/3（D11/S9）
路线：主人 2026-10-27 批「程序化矢量」；色板同 VS 卡组（语义色示意，1027-2 定版后走 UiPalette）。
产出：
  assets/icons/ui/net_badge_*.png / net_icon_weaknet_*.png   交付件（2x）
  <会话可视化目录>/vs_v1_preview/net_badge_*                  预览拷贝（1x，非交付物）
文案对照（运行时由实现拼 Label，贴图不烤字）：
  afk=「挂机中·AI托管」 offline=「掉线·AI托管」 host=「房主转移」
  captain=「队长转让」 forfeit=「判负出局」 return=「已回归」
  weaknet_warn=RTT 高 weaknet_danger=丢包/严重弱网
"""
import os, math, json
from PIL import Image, ImageDraw, ImageFilter

ROOT = r"E:\项目储存\决竞球battle-ball"
ASSET_DIR = os.path.join(ROOT, "assets", "icons", "ui")
VIZ = r"C:\Users\Lenovo\.zcode\v2\visualizations\970e3e78308f9f8ede57e1cae25e98a10085c22c22d22288114ca613e8661312"
PREVIEW = os.path.join(VIZ, "vs_v1_preview")

FINAL = 2
K = 4
def KW(v):
    return max(1, int(round(v * K)))

def C(hexstr, a=255):
    h = hexstr.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

def with_a(c, a):
    return (c[0], c[1], c[2], a)

AMBER = C('D9A94F')   # 警示（挂机/弱网黄）
EMBER = C('FF6B4A')   # 危险（掉线/判负/弱网红，与敌方队色同源）
ICE   = C('6FD3FF')   # 信息（房主/队长转移）
GREEN = C('5ABF88')   # 正向（回归）
PLATE = C('0E1826', 235)
WHITE = C('E8EEF6')

def chamfer(x, y, w, h, c):
    c = max(1, min(c, w // 2 - 1, h // 2 - 1))
    return [(x + c, y), (x + w - c, y), (x + w, y + c), (x + w, y + h - c),
            (x + w - c, y + h), (x + c, y + h), (x, y + h - c), (x, y + c)]

class Layer:
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

def badge(accent, motif):
    """28x28 角标：暗板切角+语义色描边+几何母题（母题回调在设计坐标作画）"""
    L = Layer(28, 28); d = L.d
    p = chamfer(1, 1, 26, 26, 6)
    d.polygon(L.s(p), fill=PLATE)
    d.line(L.s(p + [p[0]]), fill=with_a(accent, 160), width=KW(1), joint='curve')
    motif(L.d, L)
    return L.done()

def m_afk(d, L):
    """沙漏（超时→托管），amber"""
    d.line(L.s([(9, 7), (19, 7)]), fill=AMBER, width=KW(2))
    d.line(L.s([(9, 21), (19, 21)]), fill=AMBER, width=KW(2))
    d.line(L.s([(9.5, 8.5), (14, 14), (18.5, 8.5)]), fill=with_a(AMBER, 220), width=KW(2), joint='curve')
    d.line(L.s([(9.5, 19.5), (14, 14), (18.5, 19.5)]), fill=with_a(AMBER, 140), width=KW(2), joint='curve')
    d.ellipse(L.s([(12.8, 16.2), (15.2, 18.6)]), fill=AMBER)  # 落沙

def m_offline(d, L):
    """断链双 C（连接断开），ember——两半链环沿对角线分离"""
    d.arc(L.s_bbox(10, 10, 5.5), 40, 320, fill=EMBER, width=KW(2.6))
    d.arc(L.s_bbox(18, 18, 5.5), 220, 500, fill=with_a(EMBER, 230), width=KW(2.6))

def m_host(d, L):
    """三尖冠（房主）+双向移位箭头，ice"""
    d.polygon(L.s([(8, 12), (8, 17.5), (20, 17.5), (20, 12),
                   (16.5, 14.5), (14, 9.5), (11.5, 14.5)]), fill=ICE)
    d.rectangle(L.s([(8, 19), (20, 20.5)]), fill=ICE)
    d.line(L.s([(9.5, 23.5), (18.5, 23.5)]), fill=with_a(ICE, 200), width=KW(1.5))
    d.polygon(L.s([(8, 22.2), (9.5, 23.5), (8, 24.8)]), fill=with_a(ICE, 200))
    d.polygon(L.s([(20, 22.2), (18.5, 23.5), (20, 24.8)]), fill=with_a(ICE, 200))

def m_captain(d, L):
    """双袖标-chevron（队长）+转让箭头，ice"""
    d.line(L.s([(9, 18), (14, 13), (19, 18)]), fill=ICE, width=KW(2.5), joint='curve')
    d.line(L.s([(9, 12.5), (14, 7.5), (19, 12.5)]), fill=with_a(ICE, 220), width=KW(2.5), joint='curve')
    d.line(L.s([(9.5, 23), (18.5, 23)]), fill=with_a(ICE, 200), width=KW(1.5))
    d.polygon(L.s([(8, 21.7), (9.5, 23), (8, 24.3)]), fill=with_a(ICE, 200))
    d.polygon(L.s([(20, 21.7), (18.5, 23), (20, 24.3)]), fill=with_a(ICE, 200))

def m_forfeit(d, L):
    """八边禁出斜杠，ember"""
    cx, cy, r = 14, 14, 8.5
    pts = [(cx + r * math.cos(math.radians(22.5 + 45 * i)),
            cy + r * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]
    d.line(L.s(pts + [pts[0]]), fill=EMBER, width=KW(2), joint='curve')
    d.line(L.s([(8.8, 19.2), (19.2, 8.8)]), fill=EMBER, width=KW(2.5))

def m_return(d, L):
    """回环箭头（回归/重连夺回），green"""
    d.arc(L.s_bbox(14, 14, 8), -40, 235, fill=GREEN, width=KW(2.5))
    ax, ay = 14 + 8 * math.cos(math.radians(-40)), 14 + 8 * math.sin(math.radians(-40))
    d.polygon(L.s([(ax + 3.4, ay - 0.6), (ax - 1.6, ay - 3.2), (ax - 0.6, ay + 2.8)]), fill=GREEN)

def weaknet(danger):
    """24x24 弱网：信号三格同形异色——warn 顶格空芯衰减(amber)，danger 全实芯(ember)"""
    L = Layer(24, 24); d = L.d
    col = EMBER if danger else AMBER
    d.rectangle(L.s([(3, 16), (6.5, 21)]), fill=col)
    d.rectangle(L.s([(9, 12), (12.5, 21)]), fill=col)
    if danger:
        d.rectangle(L.s([(15, 8), (18.5, 21)]), fill=col)
    else:
        d.rectangle(L.s([(15, 8), (18.5, 21)]), fill=with_a(col, 95))  # 顶格半透明=信号衰减
    return L.done()

# Layer 补充：圆形 bbox 助手（arc 用）
def s_bbox(self, cx, cy, r):
    return [(cx - r) * K, (cy - r) * K, (cx + r) * K, (cy + r) * K]
Layer.s_bbox = s_bbox

def main():
    os.makedirs(ASSET_DIR, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    jobs = {
        'net_badge_afk.png':            badge(AMBER, m_afk),
        'net_badge_offline.png':        badge(EMBER, m_offline),
        'net_badge_host.png':           badge(ICE, m_host),
        'net_badge_captain.png':        badge(ICE, m_captain),
        'net_badge_forfeit.png':        badge(EMBER, m_forfeit),
        'net_badge_return.png':         badge(GREEN, m_return),
        'net_icon_weaknet_warn.png':    weaknet(False),
        'net_icon_weaknet_danger.png':  weaknet(True),
    }
    report = {}
    for name, img in jobs.items():
        path = os.path.join(ASSET_DIR, name)
        img.save(path)
        prev = img.resize((img.width // FINAL, img.height // FINAL), Image.LANCZOS)
        prev.save(os.path.join(PREVIEW, name))
        report[name] = {'export': list(img.size), 'bytes': os.path.getsize(path)}
    print(json.dumps(report, ensure_ascii=False, indent=1))

if __name__ == '__main__':
    main()
