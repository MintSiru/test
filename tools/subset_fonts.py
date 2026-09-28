"""Galmuri 폰트에서 게임에 쓰지 않는 한자·일본어 가나를 빼서 웹 첫 로딩을 줄인다.

사용: pip install fonttools && python3 tools/subset_fonts.py <원본 폰트 폴더>
원본(https://github.com/quiple/galmuri 릴리스)의 Galmuri11.ttf, Galmuri11-Bold.ttf, Galmuri9.ttf 를
game/assets/fonts/ 에 서브셋으로 저장한다. 한글 11,172자·라틴·기호는 모두 남긴다. (OFL: 예약 글꼴 이름 없음)
"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

DROP = [(0x3040, 0x30FF), (0x31F0, 0x31FF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF), (0xFF65, 0xFF9F)]
OUT = os.path.join(os.path.dirname(__file__), '..', 'game', 'assets', 'fonts')

src_dir = sys.argv[1] if len(sys.argv) > 1 else OUT
for name in ['Galmuri11', 'Galmuri11-Bold', 'Galmuri9']:
    src = os.path.join(src_dir, name + '.ttf')
    font = TTFont(src)
    keep = [cp for cp in font.getBestCmap() if not any(a <= cp <= b for a, b in DROP)]
    opts = subset.Options()
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    opts.glyph_names = True
    opts.legacy_kern = True
    opts.hinting = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=keep)
    sub.subset(font)
    dst = os.path.join(OUT, name + '.ttf')
    font.save(dst)
    print(name, os.path.getsize(src), '->', os.path.getsize(dst))
