"""Export the existing card-and-diamond brand as small website icons (Pillow required)."""
import base64
from io import BytesIO
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
S = 4
image = Image.new("RGBA", (64*S, 64*S), "#141416")
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((S,S,63*S,63*S), radius=13*S, fill="#141416", outline="#65543a", width=S)
for angle, color in [(14,"#6f879b"),(-14,"#8d78a7"),(0,"#d5b47a")]:
    card = Image.new("RGBA", (64*S,64*S))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((18*S,9*S,46*S,55*S),radius=4*S,fill="#19212b",outline=color,width=2*S)
    d.rounded_rectangle((21*S,12*S,43*S,52*S),radius=2*S,outline="#65543a",width=S)
    d.polygon([(32*S,23*S),(41*S,32*S),(32*S,41*S),(23*S,32*S)],outline=color,width=2*S)
    d.polygon([(32*S,28*S),(36*S,32*S),(32*S,36*S),(28*S,32*S)],fill="#a38042")
    card=card.rotate(angle,Image.Resampling.BICUBIC)
    image.alpha_composite(card)

ico=BytesIO()
image.save(ico,format="ICO",sizes=[(16,16),(32,32),(48,48)])
apple=BytesIO()
image.resize((180,180),Image.Resampling.LANCZOS).save(apple,format="PNG",optimize=True)
svg='''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect x="1" y="1" width="62" height="62" rx="13" fill="#141416" stroke="#65543a"/><g fill="#19212b" stroke-width="2"><rect x="18" y="9" width="28" height="46" rx="4" stroke="#6f879b" transform="rotate(-14 32 32)"/><rect x="18" y="9" width="28" height="46" rx="4" stroke="#8d78a7" transform="rotate(14 32 32)"/><rect x="18" y="9" width="28" height="46" rx="4" stroke="#d5b47a"/></g><rect x="21" y="12" width="22" height="40" rx="2" fill="none" stroke="#65543a"/><path d="m32 23 9 9-9 9-9-9Z" fill="none" stroke="#d5b47a" stroke-width="2"/><path d="m32 28 4 4-4 4-4-4Z" fill="#a38042"/></svg>'''
data={"svg":svg,"ico":base64.b64encode(ico.getvalue()).decode(),"apple":base64.b64encode(apple.getvalue()).decode()}
(ROOT/'server/src/siteIcons.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
image.resize((256,256),Image.Resampling.LANCZOS).save(ROOT/'docs/media/site-icon.png',optimize=True)
print('Wrote website icon bundle and docs/media/site-icon.png')
