import json,pathlib,statistics as st,sys
p=pathlib.Path(sys.argv[1]);raw=json.loads(p.read_text());s=json.loads(p.with_name(p.stem+'-summary.json').read_text());ds=s['groups'];rows=raw['rows'];n=lambda v:'—' if v is None else f'{v:.0f}'
a=['# 2.4.1 寄送与驻守机制经济复核','',f"共 {len(rows)} 条真实路线、{sum(r['battles'] for r in rows)} 场战斗；执行和独立现金账本、空间占用审计发现 {len(s['errors'])} 项错误。种子从 {raw['seedBase']} 起，每个队伍和风险条件独立采样。行为源码与数据哈希在运行前后比对，并保存在逐局数据中。",'', '## 试验口径','', '三幕搜打撤使用红色护盾与60格背包，固定可见地图路线策略，先按当前生命、能量、护盾和复苏需要使用补给，再搜索、拾取和比较价值。寄存站和各幕首领箱搜完后，以真实接口自动预览最高总售价的3×3空间打包，确认后发送实际物品；每处一次、费用50金币，终幕也执行一次以覆盖终点寄送。终幕直接撤离可节省该次50金币与寄送操作时间。途中寄送只转移物品，金币只在本局结束后实际领取并出售时计入。仓库与待领取区全部经真实出售接口变现，钥匙也实际出售；原先采购且未消耗的钥匙按成本保留的经营口径通过单独资本调整列示。', '', '净金币扣除消耗钥匙、寄送费用及护盾维修预留。红盾与背包19000金币前置资本、三把钥匙450金币周转资金单列。角色、命座、合法生成并强化至25级的五星遗物与2.4参考队伍一致；优选组每槽生成十二件择优，初始与成长队保留无遗物状态。所有战斗使用实际模型，新增驻守战的伤害、经验、祝福成长、补给消耗均随结算生效。最高价值自动寄送可以选择补给和备用装具，玩家保留补给的操作会形成不同的生存与收益取舍。', '', '深渊前三档通关上限50层，第四档“无尽”在本试验主动观察至50层。每10层当日首次奖励保留675、1000、1350、1625钻；同日重复里程碑只补未领取部分，满营地新增记忆在局外经真实1:1兑换。每日钻石和含新增记忆兑换的总钻石分开比较。直接金币保持0，经验与新增遗物分解估值单列。满营地的549记忆历史投资单列，未满营地保留记忆资源。', '', '快速与从容耗时为敏感性假设：真实战斗步数×0.85/4秒，按稀有度搜索时间加0.38秒揭示停留；战斗过场、移动、祝福选择、寄送选择、仓库领取出售另加操作时长。它们描述估计人类操作时间，与模拟程序执行时间分开。', '', '## 搜打撤三幕收入','', '|队伍/风险|完成/出发|全部出发净金币|完整通关净金币|实际清算净金币/全部|失败净金币|经验总量/局|', '|---|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{d['profile']}/{d['risk']}|{d['completed']}/{d['n']}|{n(d['gold'])}|{n(d['completeMean_gold'])}|{n(d['goldLiquidation'])}|{n(d['failedMean_gold'])}|{n(d['xpAppliedTotal'])}|")
a+=['','完整通关均值使用成功通过三幕的路线。全部出发均值包含失败与途中终止。实际清算口径把未用采购钥匙一并按售价出售；经营口径将这部分未用资本按原采购成本保留。','','## 深渊每日奖励与同强度通关基准','','|队伍/深渊→搜打撤|完整50层每日钻石|含记忆总钻石|搜打撤完整净金币|每日钻/金币×0.1|总钻/金币×0.1|','|---|---:|---:|---:|---:|---:|']
for c in s['comparisons']:
 daily='—' if c['dailyRatio'] is None else f"{c['dailyRatio']:.3f}倍";total='—' if c['totalRatio'] is None else f"{c['totalRatio']:.3f}倍"
 a.append(f"|{c['profile']}/{c['abyssRisk']}→{c['raidRisk']}|{n(c['abyssDaily'])}|{n(c['abyssTotal'])}|{n(c['raidFullGold'])}|{daily}|{total}|")
a+=['','完整通关金币的95%自助法区间来自组内10000次重采样，描述固定策略下掉落和完成样本的波动：']
for c in s['comparisons']:
 if c.get('fullGoldBootstrap95'):
  lo,hi=c['fullGoldBootstrap95'];rlo,rhi=c['totalRatioBootstrap95'];a.append(f"{c['profile']}/风险{c['raidRisk']}：金币均值区间{lo:.0f}～{hi:.0f}，含记忆总钻比例区间{rlo:.2f}～{rhi:.2f}倍。")
a+=['','## 驻守增加的战斗与补给','','|队伍/风险|每局总战斗|驻守战斗|已进入可驻守服务节点|实际驻守比例|驻守/其余战斗|驻守经验/角色|补给使用/局|','|---|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{d['profile']}/{d['risk']}|{d['battles']:.2f}|{d['guardBattles']:.2f}|{d['guardServiceVisits']:.2f}|{d['guardServiceRate']:.1%}|{d['guardAdditionalToOrdinaryRate']:.1%}|{d['guardXP']:.1f}|{d['suppliesUsed']:.2f}|")
a+=['','驻守比例以实际到达的五类服务节点为分母，配置概率为每次首次进入15%。驻守/其余战斗描述同条已观察路线中额外驻守遭遇的占比；路线、生存及随机数会相互影响，这一列与关闭驻守的配对反事实试验含义不同。','','## 寄送保留资产与背包压力','','|队伍/风险|寄送次数/局|每包占格|每包售价|寄送总售价/局|失败已寄送售价|首幕首领寄送前→后格数|首次接近满包白绿格数/总格|白绿价值|','|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{d['profile']}/{d['risk']}|{d['parcelCount']:.2f}|{d['parcelMeanCells']:.2f}|{d['parcelMeanValue']:.0f}|{d['parcelValue']:.0f}|{n(d['failedMean_parcelValue'])}|{d['firstBossBeforeCells']:.1f}→{d['firstBossAfterCells']:.1f}|{d['firstFullWhiteGreenCells']:.1f}/{d['firstFullMeanCells']:.1f}|{d['firstFullWhiteGreenValue']:.0f}|")
a+=['','首轮接近满包时，白绿纯出售战利品占格及售价分别为：']
for d in ds:
 if d['mode']=='extraction':a.append(f"{d['profile']}/风险{d['risk']}：{d['firstFullLowRarityLootCells']:.1f}格、{d['firstFullLowRarityLootValue']:.0f}金币；{d['firstFullAct1Fraction']:.0%}路线在首幕已接近满包。")
a+=['','每包最多9格，逐个物品审计坐标、旋转、重叠、实际移除占格与唯一物品编号。已寄送价值全部在局外实际出售，死亡后仍保留；仍在背包与已装备的本局物品承受撤离风险。首次接近满包定义为达到背包85%容量，白绿格数含可用补给与装具，实际纯出售物品分项保存在逐局数据。','','## 深渊连续首轮与同日重复','','|队伍/风险/营地/次序|完成/出发|平均层数|每日钻|记忆|实际兑换钻|新增遗物估值|实际经验总量|','|---|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='abyss':a.append(f"|{d['profile']}/{d['risk']}/{d['camp']}/{d['attempt']}|{d['completed']}/{d['n']}|{d['floors']:.1f}|{n(d['dailyDiamonds'])}|{n(d['memoryEarned'])}|{n(d['memoryConverted'])}|{n(d['relicSell'])}|{n(d['xpAppliedTotal'])}|")
a+=['','## 参数与验证边界','','钥匙采购价150、普通战利品售价系数1.75、三幕估价系数[1,1.25,1.6]均沿用当前生产配置。此次工具只调用实际游戏接口执行路线，未向生产模型或数据写入经济调整。固定自动策略的成功率代表该策略在这些种子下的结果；本报告同时保留完整通关样本量、失败收益、原始物品及现金账本，供独立复核。']
p.with_suffix('.md').write_text('\n'.join(a)+'\n');print(p.with_suffix('.md'))
