const fs=require('node:fs'), vm=require('node:vm'), path=require('node:path');
const root=path.resolve(__dirname,'..'),src=path.resolve(process.argv[2]||path.join(root,'../gachaWeb')); const store=new Map();
const ctx={window:{GG:{}},console,Math,Date,localStorage:{getItem:k=>store.get(k)||null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)}};
vm.createContext(ctx);function run(p){vm.runInContext(fs.readFileSync(path.join(src,'js',p),'utf8'),ctx);}
for(const f of fs.readdirSync(path.join(src,'js/data')).filter(x=>x.endsWith('.js')))run('data/'+f);
ctx.window.GG.EventBus={emit:()=>{}};
for(const p of ['character/CharacterProgression','core/SaveSystem','character/RelicSystem'])run(p+'.js');
const GG=ctx.window.GG;GG.SaveSystem.load('slot1');const state=GG.SaveSystem.get();
state.resources.diamonds=4321;state.resources.gold=123456;state.ownedCharacters.kaldi={level:7,exp:80,shards:50,constellation:3,awakening:0,equippedRelics:{}};state.team=['kaldi','ember','zeph'];
state.stageProgress.ch1_1={cleared:true,stars:3,bestTurns:6};state.dialogueSeen.ch1_1_pre=true;state.chapterGiftClaimed.ch1={claimed:true,charId:'kaldi',date:Date.now()};
const relic=GG.RelicSystem.generate(5,'helmet');GG.RelicSystem.addToInventory(relic);GG.RelicSystem.equip('kaldi',relic.uid);GG.RelicSystem.upgrade(relic.uid);
GG.SaveSystem.save();fs.writeFileSync(path.join(root,'tests/fixtures/web-save-v3.json'),JSON.stringify(state,null,2));
fs.writeFileSync(path.join(root,'tests/fixtures/web-save-export.json'),JSON.stringify({game:'void-rift-gacha',schema:3,slotId:'slot1',exportedAt:Date.now(),data:state},null,2)); console.log('Created real web save fixture',relic.uid);
