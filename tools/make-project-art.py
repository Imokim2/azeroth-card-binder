"""Render the project's existing card/diamond branding and labelled gallery placeholders.

Requires Pillow. These are code-drawn graphics, not game screenshots. Fonts are rendered,
never redistributed. Existing gallery images are preserved so real captures can replace them.
Run from any folder: python tools/make-project-art.py
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "media"
SCALE = 2
BG, PANEL, GOLD, INK, MUTED = "#141416", "#242023", "#d5b47a", "#f1e9dc", "#b5aca1"
FONT_DIRS = [Path("C:/Windows/Fonts"), Path("/usr/share/fonts/truetype/dejavu")]

def font(size, serif=False, bold=False):
    names = (["georgiab.ttf" if bold else "georgia.ttf", "DejaVuSerif.ttf"] if serif
             else ["segoeuib.ttf" if bold else "segoeui.ttf", "DejaVuSans.ttf"])
    for directory in FONT_DIRS:
        for name in names:
            if (directory / name).exists():
                return ImageFont.truetype(str(directory / name), round(size * SCALE))
    raise RuntimeError("Install Georgia/Segoe UI or DejaVu fonts before rendering.")

class Canvas:
    def __init__(self, w, h, bg=BG):
        self.image = Image.new("RGB", (w * SCALE, h * SCALE), bg)
        self.draw = ImageDraw.Draw(self.image)
    def box(self, rect, fill=PANEL, outline=None, radius=0, width=1):
        coords = tuple(round(x * SCALE) for x in rect)
        if radius:
            self.draw.rounded_rectangle(coords, radius=round(radius * SCALE), fill=fill, outline=outline, width=width * SCALE)
        else:
            self.draw.rectangle(coords, fill=fill, outline=outline, width=width * SCALE)
    def line(self, points, color=GOLD, width=1):
        self.draw.line([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=color, width=width * SCALE)
    def text(self, x, y, text, size=24, color=INK, serif=False, bold=False):
        self.draw.text((round(x*SCALE), round(y*SCALE)), text, font=font(size, serif, bold), fill=color)
    def diamond(self, x, y, radius, color=GOLD, fill=None):
        pts = [(x, y-radius), (x+radius, y), (x, y+radius), (x-radius, y), (x, y-radius)]
        if fill:
            self.draw.polygon([(round(a*SCALE), round(b*SCALE)) for a, b in pts[:-1]], fill=fill)
        self.line(pts, color, 2)
    def save(self, path, preserve=False):
        path = OUT / path
        if preserve and path.exists():
            print(f"kept {path.relative_to(ROOT)}")
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        self.image.resize((self.image.width // SCALE, self.image.height // SCALE), Image.Resampling.LANCZOS).save(path, optimize=True)
        print(f"wrote {path.relative_to(ROOT)}")

def card(w=180, h=270, accent=GOLD, front=False):
    c = Canvas(w, h, "#17191d")
    c.box((2,2,w-3,h-3), "#19212b", accent, 12, 2)
    c.box((9,9,w-10,h-10), "#19212b", "#65543a", 7)
    c.box((16,16,w-17,h-17), None, accent, 4)
    if front:
        c.box((23,29,w-24,h-84), "#27313b", "#6e8798", 3)
        # A neutral model marker; deliberately no invented character or game art.
        c.diamond(w/2, h*.35, w*.18, accent)
        c.line([(31,h-61),(w-31,h-61)], accent)
        c.line([(43,h-42),(w-43,h-42)], "#b7aa94", 3)
        c.line([(57,h-27),(w-57,h-27)], "#827b70", 2)
    else:
        c.diamond(w/2,h/2,w*.33,"#536e85")
        c.diamond(w/2,h/2,w*.23,accent)
        c.diamond(w/2,h/2,w*.10,accent,"#90713f")
        c.line([(w/2,29),(w/2,h*.25)],"#65543a")
        c.line([(w/2,h*.75),(w/2,h-30)],"#65543a")
    return c.image

def paste_card(c, x, y, w=180, h=270, angle=0, accent=GOLD, front=False):
    art = card(w,h,accent,front).convert("RGBA")
    art = art.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    c.image.paste(art, (round(x*SCALE-art.width/2),round(y*SCALE-art.height/2)), art)

def banner(w,h,social=False):
    c=Canvas(w,h)
    c.box((18,18,w-19,h-19),None,"#5a4935",12)
    c.line([(54,h-68),(w-54,h-68)],"#443a30")
    c.text(65,64 if not social else 111,"World of",52,GOLD,True)
    c.text(59,124 if not social else 171,"Warcards",103,INK,True)
    c.text(65,270 if not social else 330,"A card binder for",27,MUTED)
    c.text(65,310 if not social else 370,"World of Warcraft: Forever",27,MUTED)
    c.text(65,h-48,"worldofwarcards.co.uk",18,GOLD)
    cx,cy=w*.77,h*.48
    for offset,angle,accent in [(-70,18,"#6f879b"),(70,-18,"#8d78a7"),(0,0,GOLD)]:
        paste_card(c,cx+offset,cy,178,268,angle,accent)
    return c

banner(1440,460).save("banner.png")
banner(1280,640,True).save("social-preview.png")
logo=Canvas(400,400)
logo.box((8,8,391,391),None,"#65543a",32,2)
for offset,angle,accent in [(-52,17,"#6f879b"),(52,-17,"#8d78a7"),(0,0,GOLD)]:
    paste_card(logo,200+offset,200,146,224,angle,accent)
logo.save("project-icon.png")

def panel(title):
    c=Canvas(1280,720)
    c.text(48,34,title,44,INK,True)
    c.text(48,101,"World of Warcards",20,GOLD)
    c.box((936,53,1232,91),"#2a2520","#65543a",7)
    c.text(954,61,"SCREENSHOT PLACEHOLDER",16,GOLD)
    c.line([(48,643),(1232,643)],"#443a30")
    c.text(48,667,"Layout illustration · in-game screenshot to follow",21,MUTED)
    return c

c=panel("Your binder")
c.box((67,165,1213,608),"#35271d","#967344",16,2)
for x in [86,648]: c.box((x,185,x+544,588),"#ddc8a1","#a58858",10)
c.text(111,205,"Westfall",32,"#38291c",True)
for x in [221,465]:
    for y in [348,504]: paste_card(c,x,y,87,130,accent="#bfa06c",front=True)
c.text(675,208,"Selected card",25,"#38291c",True)
paste_card(c,841,420,163,245,accent="#85acc4",front=True)
c.box((956,300,1163,536),"#cfb78d","#a58858",6)
c.text(982,331,"RARE",22,"#365877")
c.text(982,400,"2 owned",24,"#493523")
c.text(982,447,"1 spare",24,"#493523")
c.save("gallery/binder.png",True)

c=panel("Opening a pack")
for i in range(5):
    paste_card(c,200+i*220,385,174,261,accent=[GOLD,GOLD,"#8fb8d2",GOLD,"#b596d2"][i],front=i in (2,4))
c.text(457,556,"Click a card to turn it over",26,MUTED)
c.save("gallery/packs.png",True)

c=panel("Trading and gifts")
for x,title in [(86,"Your offer"),(668,"Their offer")]:
    c.box((x,173,x+526,596),PANEL,"#766044",12)
    c.text(x+30,196,title,28,INK,True)
    paste_card(c,x+263,379,140,210,accent="#8fb8d2",front=True)
    c.box((x+140,513,x+386,565),"#2c4538","#75997e",6)
    c.text(x+215,524,"Accept",23,"#d4e8d4")
c.save("gallery/trading.png",True)

c=panel("Alternate cards")
for i,(title,accent) in enumerate([("Original",GOLD),("Alternate pose","#a28abf"),("Animated","#8fb8d2")]):
    paste_card(c,272+i*368,374,208,312,accent=accent,front=True)
    c.text(201+i*368,558,title,25,MUTED)
c.save("gallery/variants.png",True)

c=panel("The companion app")
c.box((138,163,1142,606),"#1c1b1e","#766044",14)
c.box((158,184,393,584),"#282329",None,9)
c.text(181,210,"Warcards",31,GOLD,True)
for i,name in enumerate(["Collection","Updates","Settings"]): c.text(181,291+i*62,name,23,INK if i==0 else MUTED)
c.text(435,204,"Your collection",32,INK,True)
c.box((435,264,1098,387),"#282329","#51463e",8)
c.text(462,283,"Binder connected",25,INK)
c.text(462,332,"Sync after a reload or logout",22,MUTED)
for i,label in enumerate(["Cards","Sets","Ranked"]):
    x=435+i*228
    c.box((x,414,x+207,505),"#282329","#51463e",8)
    c.text(x+25,438,label,23,GOLD)
c.box((859,531,1098,580),"#d5b47a",None,6)
c.text(892,540,"Sync collection",22,"#241c14",bold=True)
c.save("gallery/companion.png",True)

c=panel("Achievements and titles")
c.box((109,172,1171,608),PANEL,"#766044",12)
for i,(label,value) in enumerate([("Cards collected",.78),("Sets completed",.55),("Cards traded",.34)]):
    y=209+i*117
    c.diamond(161,y+21,19,GOLD)
    c.text(212,y-2,label,28,INK,True)
    c.box((212,y+50,1117,y+61),"#393437",None,5)
    c.box((212,y+50,212+905*value,y+61),"#a8905e",None,5)
c.save("gallery/achievements.png",True)
