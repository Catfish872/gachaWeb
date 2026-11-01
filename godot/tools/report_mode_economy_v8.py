"""Generate auditable economic comparison from summary and paired route rows."""
import json,sys,pathlib,statistics as st
src=pathlib.Path(sys.argv[1]); raw=json.loads(src.read_text()); rows=raw['rows']
groups=json.loads(src.with_name(src.stem+'-summary.json').read_text())['groups']
a=['# 2.4 跨模式经济与继续深入验证','',f"共 {len(rows)} 次固定策略试验，执行错误 {len(raw['errors'])}；每个条件样本数在表中单列。源码哈希附于逐局原始数据。完成率描述这些固定策略与种子下的结果。",'', '## 统计口径','', '搜打撤全卖净估价为实际钱包变动，加结算后的仓库、待领取区、持久钥匙串全部可售资产，再扣装备护盾实际缺损的营地维修预留。持续经营净收益另外将未使用的采购钥匙保留为原成本资本，仅扣实际用掉钥匙的采购成本；免费掉落剩余钥匙仍按售价计。主表使用持续经营口径，全卖结果保留于逐局及汇总数据。失败仍保留已经回收的金币、寄存物与钥匙串。回收所得只进入钱包一次。钥匙采购按真实购买价扣款，实际开门消耗计数，剩余钥匙按可出售价格保留。整备组的红盾和60格包采购资本19000金币单列，三把区域钥匙初始周转资金450金币也独立记录，每局只计真实消耗。免费组可以拾取免费钥匙并开门。所有策略在遇到寄存站且净值为正时使用真实寄存接口。', '', '同队配对使用相同初始角色、命座和真实生成并升至25级的五星遗物；优选组每槽生成十二件、按固定评分择优。深渊以20层结束或战败，直付金币、遗物全卖估价、钻石和经验分别列示。经验授予量还受等级上限约束，满级角色实际经验增加为零。', '', '时间采用真实战斗动作数×0.85/4秒。每件物品搜索耗时按稀有度为0.45/0.65/0.95/1.35/2/2.8秒，另加0.38秒揭示驻留。快速/从容两种显式操作假设：搜打撤每战额外1.4/2.5秒、移动1/2.5秒、回响选择2/5秒、实际房间与拾取换装操作1.5/4秒、准备结算12/40秒；深渊每战1/2秒、真实选择购买离店2/5秒、准备结算12/40秒。每分钟回报以总收入除以总估计时长计算。该框架评估操作敏感性。', '', '路线固定为兴趣点优先；白绿纯出售物资在工坊、寄存站及尚要深入的首领出口按60%回收，最后撤离点保留全价出售。三幕策略沿前两幕真实成长继续，二幕策略独立停止于第二幕。两三幕边际表使用同种子成对终局净收益差，自动包含深入失败造成的损失。', '', '## 深渊基准','', '|队伍/难度|样本/完成|直付金币|遗物出售|钻石|每人授予经验|实际总经验|直付金币/分快/从容|含遗物金币/分快/从容|','|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for d in groups:
 if d['mode']=='abyss':a.append(f"|{d['profile']}/{d['risk']}|{d['n']}/{d['successes']}|{d['goldDirect']:.0f}|{d['relicSell']:.0f}|{d['diamonds']:.0f}|{d['xpAwardedPerCharacter']:.0f}|{d['xpAppliedTotal']:.0f}|{d['directRateFast']:.0f}/{d['directRateDeliberate']:.0f}|{d['rateFast']:.0f}/{d['rateDeliberate']:.0f}|")
a+=['','## 搜打撤终局回报','','|队伍/整备/撤离幕/回收|样本/完成|净估价|估计秒快/从容|金币/分快/从容|回收金币/次数|高占格房数|','|---|---:|---:|---:|---:|---:|---:|']
for d in groups:
 if d['mode']=='extraction':a.append(f"|{d['profile']}/{d['kit']}/{d['targetAct']}/{d['recycling']}|{d['n']}/{d['successes']}|{d['gold']:.0f}|{d['secondsFast']:.0f}/{d['secondsDeliberate']:.0f}|{d['rateFast']:.0f}/{d['rateDeliberate']:.0f}|{d['salvageGold']:.0f}/{d['salvageCount']:.2f}|{d['fullRooms']:.1f}|")
a+=['','高占格房间以首次搜完该房间时背包占用达到容量85%计数，描述空间压力；回收次数与金红发现量按实际路线记录。','','## 成对深入边际','','|队伍/整备/回收|第二幕净收益增量|第三幕净收益增量|三幕金发现1/2/3幕|三幕红发现1/2/3幕|','|---|---:|---:|---:|---:|']
for d in groups:
 if d['mode']!='extraction' or d['targetAct']!=3:continue
 same=lambda x:x['mode']=='extraction' and all(x[k]==d[k] for k in ['profile','risk','kit','recycling'])
 pair={x['targetAct']:x for x in groups if same(x)}
 fmt=lambda vs:'/'.join(f'{v:.2f}' for v in vs)
 a.append(f"|{d['profile']}/{d['kit']}/{d['recycling']}|{pair[2]['gold']-pair[1]['gold']:.0f}|{pair[3]['gold']-pair[2]['gold']:.0f}|{fmt(d['goldFound'])}|{fmt(d['redFound'])}|")
a+=['','后两幕金红发现均值以全部出发为分母，提前失败的路线后续发现为零。资产种类、钥匙采购与剩余、维修预留、逐幕出口估价、原始战斗动作和搜索时长均保留于逐局数据。']

if not any('goldLiquidation' in r for r in rows):
 a=[x.replace('主表使用持续经营口径，全卖结果保留于逐局及汇总数据。','本批校准主表采用期末全卖口径；未使用采购钥匙的资本口径在后续冻结验证单列。') for x in a]
if any(r.get('recyclingStrategy')=='cashout' for r in rows):
 a=[x.replace('白绿纯出售物资在工坊、寄存站及尚要深入的首领出口按60%回收，最后撤离点保留全价出售。','兑现续探策略在尚要深入的首领出口将全部纯出售物资、备用装备、超额补给按60%回收；按每格效果保留治疗、修理、能量、复苏各一件，重复功能共享保留物。已装备物保留，最后撤离点保留全价出售。') for x in a]
 a.insert(12,'补给策略按当前可观察状态执行：单名存活角色生命低于75%使用有效治疗，装备盾余量低于60%使用有效维修，队员倒下使用复苏，能量不高于40时补能，技能冷却至少2时使用清冷却补给；所有消耗经过实际模型接口。回收手选按每件0.35/0.9秒附加快速/从容操作敏感性。')
output=src.with_suffix('.md');output.write_text('\n'.join(a)+'\n');print(output)
