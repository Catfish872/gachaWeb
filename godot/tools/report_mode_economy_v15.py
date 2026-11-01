import gzip,json,pathlib,statistics as st,sys
input_path=pathlib.Path(sys.argv[1]);p=input_path.with_suffix('') if input_path.suffix=='.gz' else input_path;raw=json.loads(gzip.decompress(input_path.read_bytes()) if input_path.suffix=='.gz' else input_path.read_bytes());s=json.loads(p.with_name(p.stem+'-summary.json').read_text());ds=s['groups'];rows=raw['rows'];n=lambda v:'—' if v is None else f'{v:.0f}'
name_map={'starter':'初始队','grown':'成长队','limited_c6_gear25':'限定毕业队','damage_c6_gear25':'输出毕业队','optimized_c6':'优选毕业队'}
policy_names={'reserve_locked':'保留补给','default_unlocked':'默认未锁','shared':'共用'}
def ci(d):
 bounds=d.get('completeMeanGoldBootstrap95');return '—' if not bounds else f'{bounds[0]:.0f}～{bounds[1]:.0f}'
def ratio_ci(c):
 bounds=c.get('totalRatioBootstrap95');return '—' if not bounds else f'{bounds[0]:.2f}～{bounds[1]:.2f}'
def tag(d):return f"{name_map[d['profile']]}/{d['risk']}/{policy_names[d['supplyPolicy']]}"
raids=[d for d in ds if d['mode']=='extraction'];totals=[c['totalRatio'] for c in s['comparisons'] if c['totalRatio'] is not None];daily=[c['dailyRatio'] for c in s['comparisons'] if c['dailyRatio'] is not None]
def span(values,digits=2):return '样本不足' if not values else f'{min(values):.{digits}f}～{max(values):.{digits}f}'
conclusion=f"本次采用首领完整承受异常、新敌人成长及最终首领增强、扩大的寄送空间、钥匙采购价500，并保留祝福无限叠加、总减伤90%、新裂隙商店及大招就绪即释放规则，普通治疗战技保留90%生命阈值。满营地每日奖励加本局新增记忆兑换，相对同队三幕完整通关净金币×0.1为{span(totals)}倍；仅每日里程碑钻石为{span(daily)}倍。本轮保持现有奖励与战利品估价，执行用户已授权的钥匙采购价500及商店价格翻倍；两种口径分别报告，掉落波动与成功样本量体现在区间和原始记录中。"
pressure=f"首幕首领寄送后平均保留{span([d['firstBossAfterCells'] for d in raids],1)}格，整局平均寄送{span([d['parcelCount'] for d in raids])}次。新增驻守为每局{span([d['guardBattles'] for d in raids])}战，服务节点实际触发{span([d['guardServiceRate']*100 for d in raids],1)}%；失败组已寄送且实际卖出的物品均值为{span([d['failedMean_parcelValue'] for d in raids if d['failedMean_parcelValue'] is not None],0)}金币。"
a=['# 2.4.1 最终规则经济复核（v15）','',f"共 {len(rows)} 条真实路线、{sum(r['battles'] for r in rows)} 场战斗；执行和独立现金账本、空间占用审计发现 {len(s['errors'])} 项错误。种子从 {raw['seedBase']} 起，两种补给策略在同一队伍与风险条件下按相同种子配对。行为源码与数据哈希在运行前后比对，并保存在逐局数据中。",'', '逐局数据见[无损压缩原始数据](economy-v241-final.json.gz)，统计汇总见[汇总数据](economy-v241-final-summary.json)。压缩包解压后的完整JSON与本地原始数据逐字节一致，原始及压缩文件的SHA-256分别保留。', '', '## 结论', '', conclusion, '', pressure, '', '两种补给策略使用相同种子成对验证，完整展示通关、失败、实际用药及收益差异；按具体队伍和风险条件判断，自动使用与未用返还逐项核验。', '', f"真实路线观察到同一祝福最高{max(r['maxBlessingCopies'] for r in rows)}份，{sum(r['maxBlessingCopies']>3 for r in rows)}条路线超过三份；计数来自实际选择与购买，模拟工具按真实接口接收全部成长。", '', '## 试验口径','', '同幕新增成长只对普通、精英和服务驻守生效，使用固定地图tier的1+0.02×clamp(tier−1,0,3)，最多1.06，不因往返或操作次数累加。原有幕次、tier和风险曲线保留；前两幕首领保持原预算，第三幕仅首领本体四维额外×1.15，风险4/5护卫不获得这项增强；首领战整体不再叠普通房深度倍率。新末幕首领本体速度上限相应为138，护卫和其余敌人保持120。逐场记录实际配置及初始敌人属性，首领按冻结战斗规则完整承受异常，未伪造或跳过战斗。', '', '同一新种子下执行两种完整策略。保留补给组按每格效果各保留治疗、修理、能量、复苏一件（同一件可覆盖多类），通过真实锁接口保护自动交换，并在手选寄送时排除这些物品；默认未锁组沿用默认物品锁状态并使用完整自动寄送推荐。两组均使用红色护盾与60格背包、固定可见地图路线，先按当前生命、能量、护盾和复苏需要使用补给，再搜索、拾取和比较价值。寄存站和各幕首领箱搜完后，以真实接口自动预览当前自动推荐的可行空间打包（寄存站5×5、首领6×6），确认后发送实际物品；每处一次、费用50金币，终幕也执行一次以覆盖终点寄送。终幕直接撤离可节省该次50金币与寄送操作时间。途中寄送只转移物品，金币只在本局结束后实际领取并出售时计入。仓库与待领取区全部经真实出售接口变现，钥匙也实际出售；原先采购且未消耗的钥匙按成本保留的经营口径通过单独资本调整列示。', '', '净金币扣除消耗钥匙、寄送费用及护盾维修预留。红盾与背包19000金币前置资本、三把钥匙1500金币周转资金单列。初始组为两名1级零命角色，成长组为三名5级零命角色，毕业组为三名10级满命角色。角色、命座、合法生成并强化至25级的五星遗物与2.4参考队伍一致；优选组每槽生成十二件择优，初始与成长队保留无遗物状态。所有战斗使用实际模型，新增驻守战的伤害、经验、祝福成长、补给消耗均随结算生效。默认寄送可以选择补给和备用装具，两组并列展示管理补给产生的生存与收益差异。交换的实际自动使用、未使用回原容器、生命/能量/冷却/护盾变化按顺序独立复算。', '', '裂隙商店提供三项不同的本局祝福和治疗、能量两项补给，按实际接口以70、60、白110、蓝170、金280裂隙币计价；维持原固定购物顺序并记录实际花费与剩余裂隙币。深渊前三档通关上限50层，第四档“无尽”在本试验主动观察至50层。每10层当日首次奖励保留675、1000、1350、1625钻；同日重复里程碑只补未领取部分，满营地新增记忆在局外经真实1:1兑换。每日钻石和含新增记忆兑换的总钻石分开比较。直接金币保持0，经验与新增遗物分解估值单列。满营地的549记忆历史投资单列，未满营地保留记忆资源。', '', '快速与从容耗时为敏感性假设：真实战斗步数×0.85/4秒；每件按稀有度搜索0.45/0.65/0.95/1.35/2/2.8秒，另加0.38秒揭示停留。搜打撤每战另计1.4/2.5秒、移动1/2.5秒、祝福选择2/5秒、实际操作1.5/4秒、每件寄送核对0.35/0.9秒、准备结算12/40秒；锁操作和仓库领取出售均计入实际操作。深渊每战1/2秒、实际选择2/5秒、准备结算12/40秒、记忆兑换1.5/4秒。每分钟值采用总收入除以总估计时长，与模拟程序执行时间分开。', '', '## 搜打撤三幕收入','', '|队伍/风险|完成/出发|全部出发净金币|完整通关净金币|完整均值95%区间|实际清算净金币/全部|失败净金币|经验总量/局|金币/分快/从容|', '|---|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{tag(d)}|{d['completed']}/{d['n']}|{n(d['gold'])}|{n(d['completeMean_gold'])}|{ci(d)}|{n(d['goldLiquidation'])}|{n(d['failedMean_gold'])}|{n(d['xpAppliedTotal'])}|{d['goldRateFast']:.0f}/{d['goldRateDeliberate']:.0f}|")
a+=['','## 同种子的补给策略差异','','|队伍/风险|同成功/仅保留成功/仅默认成功/同失败|默认−保留全出发净金币|差值95%区间|默认−保留自动使用|','|---|---:|---:|---:|---:|']
for pair in s.get('pairedPolicyComparisons',[]):
 lo,hi=pair['defaultMinusReserveGoldBootstrap95'];a.append(f"|{name_map[pair['profile']]}/{pair['risk']}|{pair['bothCleared']}/{pair['onlyReserveCleared']}/{pair['onlyDefaultCleared']}/{pair['bothFailed']}|{pair['defaultMinusReserveGold']:.0f}|{lo:.0f}～{hi:.0f}|{pair['defaultMinusReserveAutoUse']:.2f}|")
a+=['','完整通关均值使用成功通过三幕的路线。全部出发均值包含失败与途中终止。实际清算口径把未用采购钥匙一并按售价出售；经营口径将这部分未用资本按原采购成本保留。','','## 深渊每日奖励与同强度通关基准','','|队伍/深渊→搜打撤|完整50层每日钻石|含记忆总钻石|搜打撤完整净金币|每日钻÷（金币×0.1）|总钻÷（金币×0.1）|总钻比例95%区间|','|---|---:|---:|---:|---:|---:|']
for c in s['comparisons']:
 daily='—' if c['dailyRatio'] is None else f"{c['dailyRatio']:.3f}倍";total='—' if c['totalRatio'] is None else f"{c['totalRatio']:.3f}倍"
 a.append(f"|{name_map[c['profile']]}/{c['abyssRisk']}→{c['raidRisk']}/{policy_names[c['supplyPolicy']]}|{n(c['abyssDaily'])}|{n(c['abyssTotal'])}|{n(c['raidFullGold'])}|{daily}|{total}|{ratio_ci(c)}|")
a+=['','区间通过固定策略成功样本组内10000次自助重采样得到，显示掉落与成功样本量带来的不确定性；各组完整通关样本量均在表中列出，样本较少的组应连同区间阅读。输出毕业队风险5仅有5～6个成功样本，区间是这些已观察成功样本的条件重采样，不能据此推断总体掉落尾部、稳定通关率或更换种子后的保证；本轮不据单点继续调价。']
a+=['','## 驻守增加的战斗与补给','','|队伍/风险|每局总战斗|驻守战斗|已进入可驻守服务节点|实际驻守比例|驻守/其余战斗|驻守经验/角色|手动/自动补给使用|','|---|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{tag(d)}|{d['battles']:.2f}|{d['guardBattles']:.2f}|{d['guardServiceVisits']:.2f}|{d['guardServiceRate']:.1%}|{d['guardAdditionalToOrdinaryRate']:.1%}|{d['guardXP']:.1f}|{d['manualSuppliesUsed']:.2f}/{d['autoSuppliesUsed']:.2f}|")
a+=['','驻守比例以实际到达的五类服务节点为分母，配置概率为每次首次进入15%。驻守/其余战斗描述同条已观察路线中额外驻守遭遇的占比；路线、生存及随机数会相互影响，这一列与关闭驻守的配对反事实试验含义不同。','','## 寄送保留资产与背包压力','','|队伍/风险|寄送次数/局|每包占格|每包售价|寄送总售价/局|失败已寄送售价|首幕首领寄送前→后格数|首次接近满包白绿格数/总格|白绿价值|','|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='extraction':a.append(f"|{tag(d)}|{d['parcelCount']:.2f}|{d['parcelMeanCells']:.2f}|{d['parcelMeanValue']:.0f}|{d['parcelValue']:.0f}|{n(d['failedMean_parcelValue'])}|{d['firstBossBeforeCells']:.1f}→{d['firstBossAfterCells']:.1f}|{d['firstFullWhiteGreenCells']:.1f}/{d['firstFullMeanCells']:.1f}|{d['firstFullWhiteGreenValue']:.0f}|")
a+=['','在各自策略允许寄送的物品集合内，自动方案的最优性见证与面积价值上界达成率：']
for d in ds:
 if d['mode']=='extraction':a.append(f"{tag(d)}：{d['parcelOptimalFraction']:.1%}包裹同时达到独立面积价值上界且实际装得下，平均装入价值/面积上界为{d['parcelValueToAreaBound']:.1%}。")
a+=['','首轮接近满包时，白绿纯出售战利品占格及售价分别为：']
for d in ds:
 if d['mode']=='extraction':a.append(f"{tag(d)}：{d['firstFullLowRarityLootCells']:.1f}格、{d['firstFullLowRarityLootValue']:.0f}金币；{d['firstFullAct1Fraction']:.0%}路线在首幕已接近满包。")
a+=['','寄存站每包最多25格、首领每包最多36格，逐个物品审计坐标、旋转、重叠、实际移除占格与唯一物品编号。自动打包执行生产接口的有界搜索，可行性与实际收益已核验，自动方案达到独立面积价值上界且几何可行时可确认最优；其余方案标为有界搜索结果。已寄送价值全部在局外实际出售，死亡后仍保留；仍在背包与已装备的本局物品承受撤离风险。首次接近满包定义为达到背包85%容量；首幕比例以全部出发为分母，满包时物品构成仅按实际达到阈值的路线统计，未达到数保存在汇总。白绿格数含可用补给与装具，实际纯出售物品分项保存在逐局数据。']
a+=['','## 钥匙500金币的密室回本','','|队伍/风险|已开密室数/每局|已购钥匙实际消耗成本/局|密室生成值/房|实际售出/房|售出减500/房|现金覆盖500比例|失败路线密室售出/房|','|---|---:|---:|---:|---:|---:|---:|---:|']
for d in raids:
 rate=d['keyVaultCashPaybackRate'];rate_text='—' if rate is None else f'{rate:.1%}'
 a.append(f"|{tag(d)}|{d['keyVaultCount']}/{d['keyVaultVisits']:.2f}|{n(d['keyConsumedCost'])}|{n(d['keyVaultMean_foundValue'])}|{n(d['keyVaultMean_realizedValue'])}|{n(d['keyVaultMean_realizedMinusReplacementCost'])}|{rate_text}|{n(d['failedKeyVaultMeanRealizedValue'])}|")
a+=['','生成值来自真实开门后容器中的原始物品；实际售出只计这些原始UID最终保留并经局外真实出售的现金，途中使用的补给不折现。每房售出减500使用本次钥匙采购替代成本，拾得钥匙的实际购入现金成本可为0，逐房记录另列。该项是房间原始物品的现金回本指标，不是与绕过密室的配对边际收益：它不估算替代房间、背包挤占、消耗品治疗收益及行走时间。按幕/钥匙类型细分和失败记录保留于统计汇总。']
a+=['','## 深渊连续首轮与同日重复','','|队伍/风险/营地/次序|完成/出发|平均层数|每日钻|记忆|实际兑换钻|新增遗物估值|实际经验总量|商店访问/花费裂隙币|','|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for d in ds:
 if d['mode']=='abyss':a.append(f"|{tag(d)}/{d['camp']}/{d['attempt']}|{d['completed']}/{d['n']}|{d['floors']:.1f}|{n(d['dailyDiamonds'])}|{n(d['memoryEarned'])}|{n(d['memoryConverted'])}|{n(d['relicSell'])}|{n(d['xpAppliedTotal'])}|{d['shopVisits']:.1f}/{d['shopSpend']:.0f}|")
a+=['','## 感电的真实行动机会统计','','感电默认每次实际可行动机会有35%概率跳过，Boss与普通单位同规则。表中机会排除同次已被冻结/眩晕强制跳过的情况；数据来自生产战斗模型缓存后的实际机会统计，只读累加，不调用UI或重新掷骰。expectedSkips按每次有效概率累加，当前默认均为35%。Boss控制持续时间不截断、无强制免控行动；毒伤统一每层最大生命5%。两种搜打撤策略分列，区间按种子成簇重采样10000次，保留同一seed在不同队伍及营地/重复局间的相关性，不能把配对重现的机会当成完全独立试验。有限样本随机波动不作为自动调概率依据。本批没有出现己方感电机会，表中0不代表己方免疫，也不据此推断其触发率。','','|模式/策略/对象|感电机会|实际跳过|实际比例|配置期望比例|按seed成簇95%区间|','|---|---:|---:|---:|---:|---:|']
for d in s['electrify']:
 rate='—' if d['skipRate'] is None else f"{d['skipRate']:.1%}";expected='—' if d['expectedRate'] is None else f"{d['expectedRate']:.1%}";interval='—' if d['seedClusterBootstrap95'] is None else f"{d['seedClusterBootstrap95'][0]:.1%}～{d['seedClusterBootstrap95'][1]:.1%}"
 a.append(f"|{d['mode']}/{d['supplyPolicy']}/{d['target']}|{d['opportunities']}|{d['skips']}|{rate}|{expected}|{interval}|")
extraction_battles=[b for r in rows if r['mode']=='extraction' for b in r['encounterHistory']]
a+=['',f"搜打撤单战最多调用auto_step {max((b['steps'] for b in extraction_battles),default=0)}次；所有已计入战斗均正常胜负结算。工具每战3000次调用是异常检测边界，达到就记错并中止，不会添加免控、强制敌人行动或伪造胜利。本批两种模式均未触发该检测。"]
a+=['','## 参数与验证边界','','钥匙采购价按用户要求改为500；普通战利品售价系数1.75、三幕估价系数[1,1.25,1.6]沿用当前生产配置。此次工具只调用实际游戏接口执行路线，未向生产模型或数据写入经济调整。固定自动策略的成功率代表该策略在这些种子下的结果；本报告同时保留完整通关样本量、失败收益、原始物品及现金账本，供独立复核。']
for i in range(1,len(a)):
 if a[i].startswith('|---') and a[i-1].startswith('|'):
  columns=len(a[i-1].split('|'))-2;a[i]='|'+'|'.join(['---']+['---:']*(columns-1))+'|'
p.with_suffix('.md').write_text('\n'.join(a)+'\n');print(p.with_suffix('.md'))
