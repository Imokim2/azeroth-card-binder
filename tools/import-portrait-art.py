"""Convert a selected finished painting to a client-compatible texture; no repainting."""
import argparse
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('name', choices=['Snow', 'Desert', 'Swamp', 'Ruins', 'Volcano', 'Coast'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
target = root / 'AzerothCardBinder' / 'Art' / 'Scenery' / (args.name + '.tga')
target.parent.mkdir(parents=True, exist_ok=True)
Image.open(args.source).convert('RGB').resize((512, 512), Image.Resampling.LANCZOS).save(target, compression=None)
print(target.relative_to(root))
