import json,pathlib
root=pathlib.Path(__file__).resolve().parents[1];d=json.loads((root/'data/extraction.json').read_text());e=d['lootEconomy'];checks=0
assert e['riskGoldWeight']==1.05 and e['riskRedWeight']==.065;checks+=1
script=(root/'scripts/extraction_model.gd').read_text()
assert 'get("riskGoldWeight", 1.05)' in script and 'get("riskRedWeight", 0.065)' in script;checks+=1
for k,value,buy,legacy in [('energy_crystal',60,150,30),('repair_core',80,240,48),('revival_phoenix',100,300,60),('ration_4',90,240,48),('ration_5',150,340,68)]:
 item=d['items'][k];assert item['value']==value and item['buyPrice']==buy and item['v7Value']==legacy;checks+=1
 assert value*max(e['riskAppraisalMultiplier'])<buy;checks+=1
for base in d['rarityWeightsByAct']:
 for q in range(3):
  for boss in [False,True]:
   sequence=[]
   for risk in range(6):
    w=base.copy()
    for i,color in [(3,'Purple'),(4,'Gold'),(5,'Red')]:w[i]+=q*e['quality'+color+'Weight']+risk*e['risk'+color+'Weight']
    if boss:w[4]+=e['bossGoldWeight'];w[5]+=e['bossRedWeight']
    sequence.append((w[4]/sum(w),w[5]/sum(w),(w[4]+w[5])/sum(w)))
   assert all(all(b[j]>=a[j] for j in range(3)) for a,b in zip(sequence,sequence[1:]));checks+=1
print(f'ECONOMY V278 STATIC: {checks} checks, 0 failures; exact normalization, no sampling')
