// 角色数据表 — 所有角色的静态配置
// 新角色只需在此对象中添加新条目，无需修改其他代码
window.GG = window.GG || {};
window.GG.CharacterData = {

    'kaldi': {
        id: 'kaldi', name: '焰龙·卡尔迪', title: '不灭炎焰', rarity: 5,
        element: 'fire', role: 'dps',
        baseStats: { hp: 1200, atk: 185, def: 75, spd: 98, cri: 0.18, criDmg: 1.65 },
        growthRate: { hp: 120, atk: 9, def: 4, spd: 0 }, // 每级成长值
        skills: ['kaldi_normal', 'kaldi_skill', 'kaldi_ult'],
        passiveId: 'kaldi_passive',
        passiveDesc: '受到伤害后，若自身处于燃烧状态，攻击力额外提升20%',
        synergyIds: ['fire_duo'],
        description: '来自炎脉山脉的龙裔战士，体内流淌着远古火龙的血脉。',
        flavorText: '"烈焰不灭，我亦永恒。"',
        color: '#ef4444', colorDark: '#7f1d1d',
        image: 'assets/characters/kaldi.png',
    },

    'ayla': {
        id: 'ayla', name: '霜语·艾拉', title: '冰原圣女', rarity: 5,
        element: 'water', role: 'support',
        baseStats: { hp: 1050, atk: 155, def: 95, spd: 106, cri: 0.12, criDmg: 1.5 },
        growthRate: { hp: 100, atk: 7, def: 5, spd: 0 },
        skills: ['ayla_normal', 'ayla_skill', 'ayla_ult'],
        passiveId: 'ayla_passive',
        passiveDesc: '每回合开始，为生命值最低的队友恢复 ATK×40% 的生命值',
        synergyIds: ['water_duo'],
        description: '冰封北境的天才治愈师，以冰霜之力封印伤口、疗愈灵魂。',
        flavorText: '"冰冻，有时是最温柔的救赎。"',
        color: '#3b82f6', colorDark: '#1e3a8a',
        image: 'assets/characters/ayla.png',
    },

    'gus': {
        id: 'gus', name: '雷霆·格斯', title: '雷暴骑士', rarity: 4,
        element: 'thunder', role: 'dps',
        baseStats: { hp: 1000, atk: 165, def: 85, spd: 103, cri: 0.20, criDmg: 1.60 },
        growthRate: { hp: 95, atk: 8, def: 4, spd: 0 },
        skills: ['gus_normal', 'gus_skill', 'gus_ult'],
        passiveId: 'gus_passive',
        passiveDesc: '暴击攻击额外获得 5 点能量',
        synergyIds: ['thunder_duo'],
        description: '驾驭闪电的铁骑勇士，战场上速战速决的先锋。',
        flavorText: '"战斗在雷鸣结束前就应该终止。"',
        color: '#eab308', colorDark: '#713f12',
        image: null,
    },

    'shana': {
        id: 'shana', name: '碧叶·夏娜', title: '森之守护者', rarity: 4,
        element: 'wind', role: 'healer',
        baseStats: { hp: 1100, atk: 130, def: 100, spd: 112, cri: 0.10, criDmg: 1.5 },
        growthRate: { hp: 105, atk: 6, def: 5, spd: 0 },
        skills: ['shana_normal', 'shana_skill', 'shana_ult'],
        passiveId: 'shana_passive',
        passiveDesc: '每次治愈行动后，为自身恢复治愈量的 15%',
        synergyIds: ['wind_duo'],
        description: '精灵森林的祭司，以自然之力抚慰战友的伤痛。',
        flavorText: '"万物皆有愈合之道。"',
        color: '#22c55e', colorDark: '#14532d',
        image: null,
    },

    'lorin': {
        id: 'lorin', name: '铁壁·洛恩', title: '绝对防线', rarity: 4,
        element: 'water', role: 'tank',
        baseStats: { hp: 1500, atk: 110, def: 160, spd: 88, cri: 0.08, criDmg: 1.5 },
        growthRate: { hp: 150, atk: 5, def: 8, spd: 0 },
        skills: ['lorin_normal', 'lorin_skill', 'lorin_ult'],
        passiveId: 'lorin_passive',
        passiveDesc: '受到伤害时，若 HP > 50%，有 30% 概率格挡（减少 50% 伤害）',
        synergyIds: ['water_duo'],
        description: '锻钢般意志的守护骑士，以自身为盾护卫全队。',
        flavorText: '"只要我还站着，你们就倒不下。"',
        color: '#60a5fa', colorDark: '#1e40af',
        image: null,
    },

    'ember': {
        id: 'ember', name: '赤炎·冈', title: '火蜥蜴战士', rarity: 3,
        element: 'fire', role: 'dps',
        baseStats: { hp: 850, atk: 140, def: 65, spd: 95, cri: 0.15, criDmg: 1.5 },
        growthRate: { hp: 80, atk: 7, def: 3, spd: 0 },
        skills: ['ember_normal', 'ember_skill', 'ember_ult'],
        passiveId: 'ember_passive',
        passiveDesc: '普攻命中时有 25% 概率触发【燃烧】',
        synergyIds: ['fire_duo'],
        description: '来自火山脚下的猎人，以速闪突袭著称的刺客。',
        flavorText: '"快准狠，就是我的哲学。"',
        color: '#f87171', colorDark: '#7f1d1d',
        image: null,
    },

    'zeph': {
        id: 'zeph', name: '流风·泽菲', title: '天际游侠', rarity: 3,
        element: 'wind', role: 'support',
        baseStats: { hp: 800, atk: 120, def: 70, spd: 115, cri: 0.12, criDmg: 1.5 },
        growthRate: { hp: 75, atk: 6, def: 3, spd: 0 },
        skills: ['zeph_normal', 'zeph_skill', 'zeph_ult'],
        passiveId: 'zeph_passive',
        passiveDesc: '自身速度超过场上平均速度时，攻击力 +15%',
        synergyIds: ['wind_duo'],
        description: '浪迹天涯的风系游侠，以速度与灵动著称。',
        flavorText: '"风比你先到达终点。"',
        color: '#86efac', colorDark: '#14532d',
        image: null,
    },

    'bolt': {
        id: 'bolt', name: '雷击·博', title: '电磁弓手', rarity: 3,
        element: 'thunder', role: 'dps',
        baseStats: { hp: 780, atk: 145, def: 60, spd: 100, cri: 0.18, criDmg: 1.55 },
        growthRate: { hp: 73, atk: 7, def: 3, spd: 0 },
        skills: ['bolt_normal', 'bolt_skill', 'bolt_ult'],
        passiveId: 'bolt_passive',
        passiveDesc: '暴击时，对目标施加【感电】状态（持续 1 回合）',
        synergyIds: ['thunder_duo'],
        description: '操控闪电箭矢的神射手，精准与爆发并存。',
        flavorText: '"我的箭，永远跟着电流走。"',
        color: '#fde047', colorDark: '#713f12',
        image: null,
    },

    'tide': {
        id: 'tide', name: '水流·塔德', title: '潮汐守卫', rarity: 3,
        element: 'water', role: 'tank',
        baseStats: { hp: 1100, atk: 100, def: 130, spd: 85, cri: 0.08, criDmg: 1.5 },
        growthRate: { hp: 105, atk: 5, def: 6, spd: 0 },
        skills: ['tide_normal', 'tide_skill', 'tide_ult'],
        passiveId: 'tide_passive',
        passiveDesc: '每回合结束时，自身回复最大 HP 的 3%',
        synergyIds: ['water_duo'],
        description: '海神庙的虔诚守卫，以海浪般的韧性承受一切冲击。',
        flavorText: '"浪来了，就接着。"',
        color: '#93c5fd', colorDark: '#1e3a8a',
        image: null,
    },

    'cinder': {
        id: 'cinder', name: '炎息·辛德', title: '余烬法师', rarity: 3,
        element: 'fire', role: 'dps',
        baseStats: { hp: 820, atk: 150, def: 55, spd: 92, cri: 0.14, criDmg: 1.60 },
        growthRate: { hp: 77, atk: 8, def: 3, spd: 0 },
        skills: ['cinder_normal', 'cinder_skill', 'cinder_ult'],
        passiveId: 'cinder_passive',
        passiveDesc: '技能命中已【燃烧】目标时，额外造成 40% 伤害',
        synergyIds: ['fire_duo'],
        description: '灰烬之中重生的火焰魔法师，以余烬烧尽一切。',
        flavorText: '"烬，比火焰更持久。"',
        color: '#fb923c', colorDark: '#7c2d12',
        image: null,
    },

    // ========== 扩展预留 ==========
    // 新角色直接在此处添加数据对象，无需修改其他任何文件
};

// 元素名称映射
window.GG.ElementNames = {
    fire: '🔥 火', water: '💧 水', wind: '🌿 风', thunder: '⚡ 雷'
};

// 职业名称映射
window.GG.RoleNames = {
    dps: '输出', tank: '坦克', healer: '治愈', support: '辅助'
};

// 稀有度配置
window.GG.RarityConfig = {
    5: { label: '五星', color: '#f59e0b', stars: '★★★★★', glowColor: 'rgba(245,158,11,0.5)' },
    4: { label: '四星', color: '#a855f7', stars: '★★★★☆', glowColor: 'rgba(168,85,247,0.5)' },
    3: { label: '三星', color: '#6b7280', stars: '★★★☆☆', glowColor: 'rgba(107,114,128,0.3)' },
};
