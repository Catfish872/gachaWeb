"""Build the portable CJK font from full Noto Sans SC; include GB2312 and all game text."""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
import sys
root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
font=TTFont(source, fontNumber=2) if source.suffix=='.ttc' else TTFont(source)
original_chars=set(font.getBestCmap())
chars=set(range(0x20,0x250))
for a in range(0xa1,0xf8):
 for b in range(0xa1,0xff):
  try:chars.update(map(ord,bytes([a,b]).decode('gb2312')))
  except UnicodeDecodeError:pass
for folder in ['scripts','data']:
 for p in (root/folder).rglob('*'):
  if p.suffix in ['.gd','.json']:chars.update(map(ord,p.read_text()))
opts=subset.Options();opts.layout_features=['*'];opts.name_IDs=['*'];opts.name_legacy=True
worker=subset.Subsetter(options=opts);worker.populate(unicodes=chars);worker.subset(font)
for record in font['name'].names:
 if record.nameID in [1,4,6,16]:
  text='VoidRiftCJKSubset' if record.nameID==6 else 'Void Rift CJK Subset'
  record.string=text.encode(record.getEncoding(),errors='replace')
target=root/'assets/fonts/NotoSansSC.otf';font.save(target)
cmap=font.getBestCmap();missing=[]
fallback=TTFont(root/'assets/fonts/NotoSansSymbols2-Regular.ttf').getBestCmap()
for p in (root/'data').glob('*.json'):
 for c in set(p.read_text()):
  if not c.isspace() and ord(c) in original_chars and ord(c) not in cmap and ord(c) not in fallback:missing.append(c)
print('font bytes',target.stat().st_size,'codepoints',len(cmap),'source-font glyphs lost',sorted(set(missing)))
assert not missing
