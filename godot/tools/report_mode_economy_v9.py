import json,sys,pathlib,statistics as st
p=pathlib.Path(sys.argv[1]);j=json.loads(p.read_text());summary=json.loads(p.with_name(p.stem+'-summary.json').read_text());ds=summary['groups'];rows=j['rows']
a=['# 2.4 无限深渊与搜打撤经济验证','',f"共 {len(rows)} 次固定策略试验，独立账本与源码核验错误 {len(summary['errors'])}。深渊每次试验以50层为明确观察终点，到达后主动结束；游戏本身继续向无限层延伸。逐局数据保留11项行为源码、数据和工具的SHA-256。",'', '## 结算口径','', '搜打撤参照一次真实三幕完整通关：红盾与60格包、前两幕首领箱搜完后兑现续探、终幕全价带出。已兑现金币、寄存、待领取和持久钥匙真实入账，失败损失保留；角色经验通过战斗结算实际发放并按模型在后续战斗生效。净收益扣钥匙真实消耗、寄存费和护盾维修预留；未用采购钥匙保留原成本资本，另存期末全部卖出的净估价。红盾与包19000金币、三把钥匙450金币周转资金单列。', '', '兑现策略保留已装备物，并按每格效果保留治疗、维修、能量、复苏各一件，余下战利品、备用装具与过量补给通过实际手选回收接口按60%兑现。治疗、修理、复苏和补能依当前可观察状态使用；路线和取舍规则预先固定。所有队伍采用真实角色与命座；三支毕业队使用合法生成并升级的五星25级遗物，优选组每槽十二件择优，初始与成长队保留无遗物设定。', '', '深渊直接金币为零，新掉落遗物按真实分解价单列，旧有遗物排除于本局收入。每日首次10层里程碑奖励按难度固定为675、1000、1350、1625星尘晶，无层数上限；跨难度同里程碑补较高差额，每天北京时间早6点刷新。满记忆营地组通过真实升级接口建立，历史营地投资549记忆单列；每局结束后才通过真实1:1兑换接口将新记忆变成星尘晶。未满组保留记忆成长资源。', '', '第一次和同日再次挑战连续发生于同一账号状态。第一次尚未到达的里程碑可在第二次继续首次领取；已经领取的同档里程碑重复奖励为零。第二次的角色等级保留第一次正常成长，因此重复组描述实际连续游玩。', '', '时间为显式敏感性估计：真实战斗动作数×0.85/4秒。搜索每件按稀有度0.45/0.65/0.95/1.35/2/2.8秒，另加0.38秒揭示驻留。快速/从容假设中，搜打撤每战额外1.4/2.5秒、移动1/2.5秒、回响选择2/5秒、实际操作1.5/4秒、每件回收手选0.35/0.9秒、准备结算12/40秒；深渊每战1/2秒、实际选择2/5秒、准备结算12/40秒、记忆兑换1.5/4秒。每分钟值为总收入除以总估计时长，与CPU执行时间分开。', '', '## 搜打撤真实出发与完成收入','', '|队伍/风险|完成/出发|全部出发净金币|通关净金币|实际经验总量/局|金币/分快/从容|','|---|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{d['profile']}/{d['risk']}|{d['completed']}/{d['n']}|{d['gold']:.0f}|{d['completeMean_gold'] or 0:.0f}|{d['xpAppliedTotal']:.0f}|{d['goldRateFast']:.0f}/{d['goldRateDeliberate']:.0f}|")
a+=['','“通关净金币”采用完成三幕样本的均值，匹配用户的通关收益参考；“全部出发净金币”保留死亡与提前结束。固定自动策略的完成数用于比较该策略表现。','','## 深渊50层与重复挑战','','|队伍/风险/营地/次序|50层完成/出发|平均到达层|日奖钻石|新增记忆|实际兑记忆钻|新遗物分解金币|实际经验总量|','|---|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='abyss':a.append(f"|{d['profile']}/{d['risk']}/{d['camp']}/{d['attempt']}|{d['completed']}/{d['n']}|{d['floors']:.1f}|{d['dailyDiamonds']:.0f}|{d['memoryEarned']:.0f}|{d['memoryConverted']:.0f}|{d['relicSell']:.0f}|{d['xpAppliedTotal']:.0f}|")
a+=['','## 满营地首次50层总钻与同队搜打撤参考','','深渊0、1、2、3档分别映射搜打撤0、2、4、5档。总钻石含每日奖励及本次实际兑换的新增记忆，重复记忆收入独立展示。','','|队伍/深渊→搜打撤|完整50层总钻|搜打撤通关净金币|总钻/(净金币×0.1)|','|---|---:|---:|---:|']
for d in ds:
 if d['mode']!='abyss' or d['camp']!='maxed' or d['attempt']!='first':continue
 raid=next(x for x in ds if x['mode']=='extraction' and x['profile']==d['profile'] and x['risk']==d['raidReferenceRisk'])
 if not raid['completeMean_gold'] or not d['completeMean_diamonds']:ratio='样本内完整通关不足'
 else:ratio=f"{d['completeMean_diamonds']/(raid['completeMean_gold']*.1):.3f}倍"
 a.append(f"|{d['profile']}/{d['risk']}→{d['raidReferenceRisk']}|{d['completeMean_diamonds'] or 0:.0f}|{raid['completeMean_gold'] or 0:.0f}|{ratio}|")
a+=['','校准目标约2至3倍适用于预先选定的常规参考队伍及风险映射。完整通关样本数同时披露，以便识别高风险小样本的掉落波动。首次奖励和重复可兑换记忆分别计量，经验与遗物保持独立资源。']
a+=['','## 背包空间、兑现和高品质发现','','|队伍/风险|首幕兑现前→后占格|平均回收金币/次数|失败路线净金币|金色纯战利品发现一/二/三幕|红色纯战利品发现一/二/三幕|','|---|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']!='extraction':continue
 rs=[r for r in rows if r['mode']=='extraction' and r['profile']==d['profile'] and r['risk']==d['risk']]
 before=[r['firstActExitBag']['cells'] for r in rs if r['firstActExitBag']]
 after=[h['remainingCells'] for r in rs for h in r['salvageHistory'] if h['act']==1]
 dead=[r for r in rs if not r['success']]
 dead_text=f"{st.mean(r['gold'] for r in dead):.0f}" if dead else '该样本全部完成'
 find=lambda key:'/'.join(f"{st.mean(r[key][act] for r in rs):.2f}" for act in range(3))
 a.append(f"|{d['profile']}/{d['risk']}|{st.mean(before):.1f}→{st.mean(after):.1f}|{st.mean(r['salvageGold'] for r in rs):.0f}/{st.mean(r['salvageCount'] for r in rs):.2f}|{dead_text}|{find('goldLootFound')}|{find('redLootFound')}|")
a+=['','占格前后采用实际到达首幕出口并执行兑现的路线；高品质发现以全部出发为分母，提前失败后续幕记零，且仅统计纯出售战利品，装具和药品的金红色发现另存原始数据。第三幕仍有失败压力，途中兑现和寄存已形成真实保留收益。三幕策略的通关净值与失败期望同时展示；50层是每日钻石校准点，完整游戏可继续深入。']
p.with_suffix('.md').write_text('\n'.join(a)+'\n');print(p.with_suffix('.md'))
