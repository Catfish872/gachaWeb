// 技能数据表 — 所有技能的静态配置
// 新技能只需在此添加条目，并在 SkillSystem 中注册效果函数
window.GG = window.GG || {};
window.GG.SkillData = {

    // ========== 焰龙·卡尔迪 ==========
    'kaldi_normal': {
        id: 'kaldi_normal', name: '炎牙斩', icon: '🔥',
        type: 'normal', element: 'fire', cooldown: 0, energyGain: 15,
        description: '以炎龙牙斩击单体目标，造成火属性伤害。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.20 }],
        animation: 'slash',
    },
    'kaldi_skill': {
        id: 'kaldi_skill', name: '龙炎爆裂', icon: '💥',
        type: 'skill', element: 'fire', cooldown: 3, energyGain: 20,
        description: '释放龙焰波，对全体敌人造成火属性伤害，并有80%概率使随机一名敌人陷入【燃烧】。',
        effects: [
            { type: 'damage', target: 'all', multiplier: 0.75 },
            { type: 'status', target: 'random_enemy', statusId: 'burn', chance: 0.80, duration: 2 },
        ],
        animation: 'explosion',
    },
    'kaldi_ult': {
        id: 'kaldi_ult', name: '天焰龙破', icon: '🐉',
        type: 'ultimate', element: 'fire', energyCost: 100, energyGain: 0,
        description: '化身炎龙，对全体敌人造成巨大火属性伤害，并使所有敌人陷入【燃烧】。',
        effects: [
            { type: 'damage', target: 'all', multiplier: 2.50 },
            { type: 'status', target: 'all_enemies', statusId: 'burn', chance: 1.0, duration: 3 },
        ],
        animation: 'mega_fire',
    },

    // ========== 霜语·艾拉 ==========
    'ayla_normal': {
        id: 'ayla_normal', name: '冰棱刺', icon: '❄️',
        type: 'normal', element: 'water', cooldown: 0, energyGain: 15,
        description: '以冰棱击刺单体目标，造成水属性伤害。',
        effects: [{ type: 'damage', target: 'single', multiplier: 0.90 }],
        animation: 'ice',
    },
    'ayla_skill': {
        id: 'ayla_skill', name: '极寒封印', icon: '🌊',
        type: 'skill', element: 'water', cooldown: 3, energyGain: 20,
        description: '以冰寒之力封印单体敌人，造成水属性伤害并使其陷入【冰冻】（跳过下一行动）。',
        effects: [
            { type: 'damage', target: 'single', multiplier: 1.0 },
            { type: 'status', target: 'single_enemy', statusId: 'freeze', chance: 1.0, duration: 1 },
        ],
        animation: 'ice',
    },
    'ayla_ult': {
        id: 'ayla_ult', name: '极光治愈', icon: '✨',
        type: 'ultimate', element: 'water', energyCost: 100, energyGain: 0,
        description: '引导极光能量，为所有队友大量恢复生命值，并赋予【再生】效果。',
        effects: [
            { type: 'heal', target: 'all_allies', multiplier: 1.80 },
            { type: 'status', target: 'all_allies', statusId: 'regen', chance: 1.0, duration: 3 },
        ],
        animation: 'aurora',
    },

    // ========== 雷霆·格斯 ==========
    'gus_normal': {
        id: 'gus_normal', name: '雷矛突刺', icon: '⚡',
        type: 'normal', element: 'thunder', cooldown: 0, energyGain: 15,
        description: '以雷矛突刺单体目标，造成雷属性伤害。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.10 }],
        animation: 'thunder',
    },
    'gus_skill': {
        id: 'gus_skill', name: '连锁闪电', icon: '🌩️',
        type: 'skill', element: 'thunder', cooldown: 2, energyGain: 20,
        description: '释放连锁闪电，对最多3名敌人造成雷属性伤害（每跳衰减15%）。',
        effects: [{ type: 'damage', target: 'chain3', multiplier: 0.85, chainDecay: 0.15 }],
        animation: 'chain_lightning',
    },
    'gus_ult': {
        id: 'gus_ult', name: '雷霆裁决', icon: '⚡',
        type: 'ultimate', element: 'thunder', energyCost: 100, energyGain: 0,
        description: '雷霆降临，对全体敌人造成巨量雷属性伤害，并使其速度降低30%（持续2回合）。',
        effects: [
            { type: 'damage', target: 'all', multiplier: 2.0 },
            { type: 'status', target: 'all_enemies', statusId: 'spd_down', chance: 1.0, duration: 2, value: 0.3 },
        ],
        animation: 'mega_thunder',
    },

    // ========== 碧叶·夏娜 ==========
    'shana_normal': {
        id: 'shana_normal', name: '自然之枝', icon: '🌿',
        type: 'normal', element: 'wind', cooldown: 0, energyGain: 15,
        description: '以自然之力攻击单体目标，造成风属性伤害。',
        effects: [{ type: 'damage', target: 'single', multiplier: 0.90 }],
        animation: 'wind',
    },
    'shana_skill': {
        id: 'shana_skill', name: '绿意回春', icon: '💚',
        type: 'skill', element: 'wind', cooldown: 2, energyGain: 20,
        description: '以治愈之风抚慰生命值最低的队友，大量恢复其HP并赋予【再生】。',
        effects: [
            { type: 'heal', target: 'lowest_hp_ally', multiplier: 1.50 },
            { type: 'status', target: 'lowest_hp_ally', statusId: 'regen', chance: 1.0, duration: 2 },
        ],
        animation: 'heal',
    },
    'shana_ult': {
        id: 'shana_ult', name: '森林庇护', icon: '🌳',
        type: 'ultimate', element: 'wind', energyCost: 100, energyGain: 0,
        description: '唤醒古老森林的护盾，为所有队友恢复HP并赋予护盾（可吸收伤害）。',
        effects: [
            { type: 'heal', target: 'all_allies', multiplier: 1.20 },
            { type: 'status', target: 'all_allies', statusId: 'shield', chance: 1.0, duration: 2, value: 0.3 },
        ],
        animation: 'forest_shield',
    },

    // ========== 铁壁·洛恩 ==========
    'lorin_normal': {
        id: 'lorin_normal', name: '盾击', icon: '🛡️',
        type: 'normal', element: 'water', cooldown: 0, energyGain: 15,
        description: '以战盾猛击单体目标，造成水属性伤害，有15%概率使其【眩晕】1回合。',
        effects: [
            { type: 'damage', target: 'single', multiplier: 0.85 },
            { type: 'status', target: 'single_enemy', statusId: 'stun', chance: 0.15, duration: 1 },
        ],
        animation: 'shield_bash',
    },
    'lorin_skill': {
        id: 'lorin_skill', name: '铁壁防御', icon: '🔵',
        type: 'skill', element: 'water', cooldown: 3, energyGain: 15,
        description: '进入防御姿态，为自身施加强力护盾，并使所有敌人的攻击目标转向自身（嘲讽）。',
        effects: [
            { type: 'status', target: 'self', statusId: 'shield', chance: 1.0, duration: 2, value: 0.5 },
            { type: 'status', target: 'self', statusId: 'taunt', chance: 1.0, duration: 2 },
        ],
        animation: 'shield_up',
    },
    'lorin_ult': {
        id: 'lorin_ult', name: '绝对要塞', icon: '🏰',
        type: 'ultimate', element: 'water', energyCost: 100, energyGain: 0,
        description: '化身移动要塞，为全队施加护盾，并使自身进入【无敌】状态持续1回合。',
        effects: [
            { type: 'status', target: 'all_allies', statusId: 'shield', chance: 1.0, duration: 3, value: 0.4 },
            { type: 'status', target: 'self', statusId: 'invincible', chance: 1.0, duration: 1 },
        ],
        animation: 'mega_shield',
    },

    // ========== 赤炎·冈（3星） ==========
    'ember_normal': {
        id: 'ember_normal', name: '火爪', icon: '🔥',
        type: 'normal', element: 'fire', cooldown: 0, energyGain: 15,
        description: '以火焰爪击单体目标。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.10 }],
        animation: 'slash',
    },
    'ember_skill': {
        id: 'ember_skill', name: '爆炎踢', icon: '🦵',
        type: 'skill', element: 'fire', cooldown: 2, energyGain: 20,
        description: '强力火焰踢击单体，并必定附加【燃烧】。',
        effects: [
            { type: 'damage', target: 'single', multiplier: 1.30 },
            { type: 'status', target: 'single_enemy', statusId: 'burn', chance: 1.0, duration: 2 },
        ],
        animation: 'explosion',
    },
    'ember_ult': {
        id: 'ember_ult', name: '业火风暴', icon: '🌋',
        type: 'ultimate', element: 'fire', energyCost: 100, energyGain: 0,
        description: '引发业火，对全体敌人造成大量火属性伤害。',
        effects: [{ type: 'damage', target: 'all', multiplier: 1.80 }],
        animation: 'mega_fire',
    },

    // ========== 流风·泽菲（3星） ==========
    'zeph_normal': {
        id: 'zeph_normal', name: '风刃', icon: '🌿',
        type: 'normal', element: 'wind', cooldown: 0, energyGain: 15,
        description: '以风刃斩击单体目标。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.0 }],
        animation: 'wind',
    },
    'zeph_skill': {
        id: 'zeph_skill', name: '疾风突袭', icon: '💨',
        type: 'skill', element: 'wind', cooldown: 2, energyGain: 20,
        description: '疾风突袭单体目标，造成伤害并降低其速度30%（持续2回合）。',
        effects: [
            { type: 'damage', target: 'single', multiplier: 1.20 },
            { type: 'status', target: 'single_enemy', statusId: 'spd_down', chance: 1.0, duration: 2, value: 0.3 },
        ],
        animation: 'wind',
    },
    'zeph_ult': {
        id: 'zeph_ult', name: '龙卷斩', icon: '🌪️',
        type: 'ultimate', element: 'wind', energyCost: 100, energyGain: 0,
        description: '掀起龙卷风，对全体敌人造成风属性伤害。',
        effects: [{ type: 'damage', target: 'all', multiplier: 1.50 }],
        animation: 'tornado',
    },

    // ========== 雷击·博（3星） ==========
    'bolt_normal': {
        id: 'bolt_normal', name: '电弧箭', icon: '⚡',
        type: 'normal', element: 'thunder', cooldown: 0, energyGain: 15,
        description: '射出带电箭矢攻击单体目标。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.10 }],
        animation: 'thunder',
    },
    'bolt_skill': {
        id: 'bolt_skill', name: '穿刺电击', icon: '🎯',
        type: 'skill', element: 'thunder', cooldown: 2, energyGain: 20,
        description: '射出穿刺电击，无视目标40%防御，造成雷属性伤害。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.20, defPierce: 0.4 }],
        animation: 'thunder',
    },
    'bolt_ult': {
        id: 'bolt_ult', name: '电磁爆发', icon: '💥',
        type: 'ultimate', element: 'thunder', energyCost: 100, energyGain: 0,
        description: '引发电磁爆发，对全体敌人造成雷属性伤害并使其陷入【感电】。',
        effects: [
            { type: 'damage', target: 'all', multiplier: 1.60 },
            { type: 'status', target: 'all_enemies', statusId: 'electrify', chance: 0.8, duration: 2 },
        ],
        animation: 'mega_thunder',
    },

    // ========== 水流·塔德（3星） ==========
    'tide_normal': {
        id: 'tide_normal', name: '水拳', icon: '💧',
        type: 'normal', element: 'water', cooldown: 0, energyGain: 15,
        description: '以水拳击打单体目标。',
        effects: [{ type: 'damage', target: 'single', multiplier: 0.90 }],
        animation: 'ice',
    },
    'tide_skill': {
        id: 'tide_skill', name: '潮汐屏障', icon: '🛡️',
        type: 'skill', element: 'water', cooldown: 3, energyGain: 15,
        description: '以海水为盾，为自身和HP最低的队友施加护盾。',
        effects: [
            { type: 'status', target: 'self', statusId: 'shield', chance: 1.0, duration: 2, value: 0.4 },
            { type: 'status', target: 'lowest_hp_ally', statusId: 'shield', chance: 1.0, duration: 2, value: 0.3 },
        ],
        animation: 'shield_up',
    },
    'tide_ult': {
        id: 'tide_ult', name: '巨浪冲击', icon: '🌊',
        type: 'ultimate', element: 'water', energyCost: 100, energyGain: 0,
        description: '掀起滔天巨浪，对全体敌人造成水属性伤害。',
        effects: [{ type: 'damage', target: 'all', multiplier: 1.40 }],
        animation: 'mega_water',
    },

    // ========== 炎息·辛德（3星） ==========
    'cinder_normal': {
        id: 'cinder_normal', name: '灰烬弹', icon: '🔥',
        type: 'normal', element: 'fire', cooldown: 0, energyGain: 15,
        description: '投掷灰烬弹攻击单体目标。',
        effects: [{ type: 'damage', target: 'single', multiplier: 1.0 }],
        animation: 'slash',
    },
    'cinder_skill': {
        id: 'cinder_skill', name: '爆灰术', icon: '☁️',
        type: 'skill', element: 'fire', cooldown: 2, energyGain: 20,
        description: '引爆灰烬，造成伤害并叠加2层【燃烧】到目标上。',
        effects: [
            { type: 'damage', target: 'single', multiplier: 1.10 },
            { type: 'status', target: 'single_enemy', statusId: 'burn', chance: 1.0, duration: 3 },
        ],
        animation: 'explosion',
    },
    'cinder_ult': {
        id: 'cinder_ult', name: '灰烬柱', icon: '🌋',
        type: 'ultimate', element: 'fire', energyCost: 100, energyGain: 0,
        description: '召唤灰烬柱，对全体敌人造成大量火属性伤害，并强制燃烧所有目标。',
        effects: [
            { type: 'damage', target: 'all', multiplier: 1.90 },
            { type: 'status', target: 'all_enemies', statusId: 'burn', chance: 1.0, duration: 2 },
        ],
        animation: 'mega_fire',
    },

    // ========== 扩展预留 ==========
    // 新技能直接在此添加，然后在 SkillSystem.js 的 effectHandlers 中注册特殊效果函数
};
