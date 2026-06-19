// 命座数据 — 每角色6阶命座效果定义
// 通用效果由 ConstellationSystem 自动计算，此文件存放个性化覆盖
window.GG = window.GG || {};

// === 命座碎片消耗表（按稀有度）===
window.GG.ConstellationCost = {
    5: [25, 25, 25, 25, 25, 25],   // 每阶需 25 碎片（5星重复每次25碎片）
    4: [20, 20, 20, 20, 20, 20],   // 每阶需 20 碎片（4星重复每次5碎片）
    3: [5, 5, 5, 5, 5, 5],   // 每阶需  5 碎片（3星重复每次1碎片）
};

// === 通用命座效果描述（所有角色均适用）===
window.GG.ConstellationGeneric = [
    { level: 1, label: '锋芒初现', desc: '普通攻击造成的伤害提升 15%', buff: { normalDmgBonus: 0.15 } },
    { level: 2, label: '技艺精进', desc: '战技冷却缩短 1 回合（最低不低于 1 回合）', buff: { skillCdReduce: 1 } },
    { level: 3, label: '战技强化', desc: '战技造成的伤害提升 20%', buff: { skillDmgBonus: 0.20 } },
    { level: 4, label: '坚韧之躯', desc: '最大 HP 提升 15%，防御力提升 10%', buff: { hpPercent: 0.15, defPercent: 0.10 } },
    { level: 5, label: '必杀临界', desc: '终极技能造成的伤害提升 30%', buff: { ultDmgBonus: 0.30 } },
    { level: 6, label: '命运之星', desc: '（角色专属）', buff: {} },
];

// === C6 专属效果（每角色不同）===
window.GG.ConstellationC6 = {
    'kaldi': {
        label: '不灭炎心',
        desc: '终极技能命中已【燃烧】目标时，额外造成 ATK×80% 的火属性伤害。',
        buff: { c6_type: 'on_ult_hit_burned', c6_bonus: 0.80 }
    },
    'ayla': {
        label: '极寒圣典',
        desc: '每次治愈行动后，为全队施加 1 层【再生】效果，持续 1 回合。',
        buff: { c6_type: 'heal_spreads_regen' }
    },
    'gus': {
        label: '雷霆极意',
        desc: '暴击后，有 40% 概率对同一目标追加一次普攻伤害（不消耗行动次数）。',
        buff: { c6_type: 'crit_chain_attack', c6_chance: 0.40 }
    },
    'shana': {
        label: '永恒绿意',
        desc: '战技/终极技能治愈量超过目标最大 HP 时，溢出部分转化为护盾（持续 1 回合）。',
        buff: { c6_type: 'overheal_shield' }
    },
    'lorin': {
        label: '绝对防壁',
        desc: '护盾存在时，受到单次大于最大 HP 30% 的伤害时，自动触发【无敌】1 回合（每场战斗限 1 次）。',
        buff: { c6_type: 'damage_nullify_once' }
    },
    'ember': {
        label: '烈焰共鸣',
        desc: '普攻触发【燃烧】的概率提升至 60%，并使概率生效时额外获得 10 点能量。',
        buff: { c6_type: 'burn_chance_up', c6_burnChance: 0.60, c6_energy: 10 }
    },
    'zeph': {
        label: '风之加护',
        desc: '自身速度超过场均时，每回合为队友中速度最低者施加 1 层【攻强】（持续 1 回合）。',
        buff: { c6_type: 'speed_buff_ally' }
    },
    'bolt': {
        label: '感电连锁',
        desc: '对已有【感电】状态的目标造成伤害时，伤害额外提升 35%。',
        buff: { c6_type: 'electrify_bonus', c6_bonus: 0.35 }
    },
    'tide': {
        label: '潮汐壁垒',
        desc: '回合结束时 HP 恢复，提升至最大 HP 的 6%（原被动加倍）。',
        buff: { c6_type: 'passive_enhance', c6_regenRate: 0.06 }
    },
    'cinder': {
        label: '灰中永焰',
        desc: '技能对已燃烧目标的额外伤害提升至 70%（原被动 40%）。',
        buff: { c6_type: 'passive_enhance', c6_burnBonus: 0.70 }
    },
};
