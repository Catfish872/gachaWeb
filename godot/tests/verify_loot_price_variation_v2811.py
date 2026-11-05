"""Check fixed appraisals against v2.8.10 for every production loot pool."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'data/extraction.json').read_text())
old = json.loads((ROOT / 'tests/fixtures/loot-prices-v2810.json').read_text())
items = data['items']
pools = {
    'ordinary': [], 'hospital': ['补给', '疗愈用品'],
    'workshop': ['符文构件', '遗迹装置', '工具', '零件', '装备', '整备'],
    'shrine': ['古物', '王室遗物', '奇珍', '秘传典籍'],
    'vault': ['珠宝', '贵金属', '王室遗物', '奇珍', '遗迹珍藏'],
    'tools': ['工具', '零件', '整备', '装备'],
}
changed = 0
for key, value in old.items():
    item = items[key]
    assert item['kind'] in ['loot', 'equipment', 'utility', 'consumable']
    if 'buyPrice' in item: assert item['value'] < item['buyPrice'], key
    assert isinstance(item['value'], int) and item['value'] > 0
    assert abs(item['value'] - value) <= max(1, int(value * .10)), key
    changed += item['value'] != value
assert changed >= 120
means = []
for theme in ['', *data['environmentThemes']]:
    variants = {v['variantOf']: k for k, v in items.items()
                if v.get('environmentTheme') == theme and 'variantOf' in v}
    for rarity in range(6):
        base = [k for k, v in items.items() if v['rarity'] == rarity and 'variantOf' not in v]
        for name, categories in pools.items():
            preferred = [k for k in base if items[k].get('category') in categories
                         or any(c in categories for c in items[k].get('lootCategories', []))]
            pool = preferred or base
            before = after = total = 0
            for key in pool:
                weight = items[key].get('dropWeight', 1)
                actual = variants.get(key, key)
                before += old.get(actual, items[actual]['value']) * weight
                after += items[actual]['value'] * weight
                total += weight
            assert abs(before - after) < 1e-8, (theme, rarity, name, before, after)
            means.append({'theme': theme or 'default', 'rarity': rarity, 'pool': name,
                          'before': before / total, 'after': after / total})
# Equal means in every rarity imply equal expectations under every unchanged
# act, rank, quality, boss bonus and guaranteed-rarity distribution.
print(f'LOOT_PRICE_VARIATION: {changed} changed items; {len(means)} weighted pools identical')
if __name__ == '__main__':
    out = ROOT / 'validation/v2811-loot'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'weighted-pools.json').write_text(json.dumps(means, ensure_ascii=False, indent=2) + '\n')
