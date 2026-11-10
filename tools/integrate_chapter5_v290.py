"""Apply only approved chapter-five content, preserving all unrelated catalog data."""
from pathlib import Path
import copy, hashlib, json
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/release_v290/story'
draft = json.loads((SOURCE / 'chapter5_dialogue_draft.json').read_text())
plan = json.loads((SOURCE / 'chapter5_integration_plan.json').read_text())
assert hashlib.sha256((SOURCE / 'chapter5_review.md').read_bytes()).hexdigest() == draft['sourceSha256'] == plan['narrativeSourceSha256']
path = ROOT / 'godot/data/catalog.json'
catalog = json.loads(path.read_text())
before = copy.deepcopy(catalog)
chapter = copy.deepcopy(plan['chapter'])
chapter['description'] = '雷雨封住了城门，与莱莎、维珂和伊芙走进旧街，寻找封城的缘由，接回仍在等待的人。'
for index, stage in enumerate(chapter['stages'], 1):
    elite, boss = stage.get('isElite', False), stage.get('isBoss', False)
    stage['staminaCost'] = 12 if elite or boss else 10
    stage['rewards'] = {'gold': [250 + index * 8, 290 + index * 8], 'exp': 490 + index * 20}
    stage['firstClearRewards'] = {'diamonds': 250 if boss else 160 if elite else 70}
    if index in (3, 6, 16):
        stage['firstClearRelic'] = {'rarity': 5, 'slotId': {3:'helmet',6:'necklace',16:'necklace'}[index], 'setId': {3:'storm_armor',6:'storm_tracer',16:'storm_shelter'}[index]}
catalog['StageData']['chapters'] = [ch for ch in catalog['StageData']['chapters'] if ch['id'] != 'ch5'] + [chapter]
for section in ['DialogueData', 'DialogueMeta']:
    for key in list(catalog[section]):
        if key.startswith('ch5_'): del catalog[section][key]
    catalog[section].update(draft[section])
# Prove the apply is confined to the approved namespace.
for value in [catalog, before]:
    value_check = copy.deepcopy(value)
    value_check['StageData']['chapters'] = [ch for ch in value_check['StageData']['chapters'] if ch['id'] != 'ch5']
    for section in ['DialogueData', 'DialogueMeta']:
        value_check[section] = {k:v for k,v in value_check[section].items() if not k.startswith('ch5_')}
    if value is catalog: unchanged = value_check
    else: assert unchanged == value_check
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
print('Applied 16 stages, 40 approved scenes; all non-ch5 catalog data preserved.')
