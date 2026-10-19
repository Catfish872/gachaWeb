// Rebuild static data and baseline stat fixtures from the unmodified sibling web source.
const fs=require('node:fs'), vm=require('node:vm'), path=require('node:path');
const root=path.resolve(__dirname,'..'), source=path.resolve(process.argv[2]||path.join(root,'../gachaWeb'));
const state={ownedCharacters:{},relics:[]};
const ctx={window:{GG:{}},console,Math}; vm.createContext(ctx);
function run(p){vm.runInContext(fs.readFileSync(path.join(source,'js',p),'utf8'),ctx);}
for(const f of fs.readdirSync(path.join(source,'js/data')).filter(x=>x.endsWith('.js')))run('data/'+f);
fs.writeFileSync(path.join(root,'data/catalog.json'),JSON.stringify(ctx.window.GG,null,2));
ctx.window.GG.SaveSystem={get:()=>state,save:()=>{}};ctx.window.GG.EventBus={emit:()=>{}};
for(const f of ['CharacterProgression','ConstellationSystem','RelicSystem','CharacterStats'])run('character/'+f+'.js');
const cases=[];
for(const id of Object.keys(ctx.window.GG.CharacterData))for(const level of [1,5,10])for(const constellation of [0,6]){
 state.ownedCharacters[id]={level,exp:0,shards:0,constellation,awakening:0,equippedRelics:{}};
 cases.push({id,level,constellation,stats:ctx.window.GG.CharacterStats.computeStats(id,level,0)});
}
fs.writeFileSync(path.join(root,'tests/fixtures/original-stats.json'),JSON.stringify(cases,null,2));
console.log(`Exported catalog and ${cases.length} original-stat cases`);
