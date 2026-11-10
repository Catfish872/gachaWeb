"""Read-only checks for the integrated approved narrative and content contracts."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
source=root/'docs/release_v290/story'
c=json.loads((root/'godot/data/catalog.json').read_text())
d=json.loads((source/'chapter5_dialogue_draft.json').read_text())
p=json.loads((source/'chapter5_integration_plan.json').read_text())
assert hashlib.sha256((source/'chapter5_review.md').read_bytes()).hexdigest()==d['sourceSha256']==p['narrativeSourceSha256']
chapter=next(ch for ch in c['StageData']['chapters'] if ch['id']=='ch5')
assert chapter['unlockCondition']=='ch4_12' and chapter['unlocked'] is False
assert len(chapter['stages'])==16
routes=[];assets=set()
for section in ['DialogueData','DialogueMeta']:
 assert {k:v for k,v in c[section].items() if k.startswith('ch5_')}==d[section]
for stage in chapter['stages']:
 routes.extend([stage['id']+'_pre',*stage['postDialogueKeys']])
 assert stage['staminaCost'] in (10,12)
 assert stage['firstClearRewards']['diamonds'] in (70,160,250)
 assert len(stage['rewards']['gold'])==2 and stage['rewards']['exp']>0
 for wave in stage['waves']:
  assert all(enemy in c['EnemyData'] for enemy in wave['enemies'])
 if 'firstClearRelic' in stage:assert stage['firstClearRelic']['setId'] in c['RelicSets']
 assets.add(stage['background'])
assert routes==p['sceneOrder'] and len(set(routes))==40
assert chapter['stages'][-1]['waves'][0]['enemies']==['sealer_core','boss_city_sealer','sealer_ward']
for key,lines in d['DialogueData'].items():
 for line in lines:
  assert line.get('portrait')!='raisa_armor'
  if line.get('portrait'):assert line['portrait'] in c['CharacterData']
  if line['speaker'] not in [*c['CharacterData'],'narrator','traveler']:assert line.get('speakerName')
 for field in ['background','illustration']:
  if d['DialogueMeta'][key].get(field):assets.add(d['DialogueMeta'][key][field])
for path in assets:assert (root/'godot'/path.removeprefix('res://')).is_file(),path
result={'result':'PASS','scenes':40,'dialogueEntries':sum(map(len,d['DialogueData'].values())),'stages':16,'artAssets':len(assets),'approvedSourceSha256':d['sourceSha256'],'firstClearDiamonds':sum(s['firstClearRewards']['diamonds'] for s in chapter['stages']),'fullChapterStamina':sum(s['staminaCost'] for s in chapter['stages'])}
print(json.dumps(result,ensure_ascii=False,indent=2))
