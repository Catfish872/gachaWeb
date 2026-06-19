// 遗物数据 — 部位定义、词条池、套装配置
window.GG = window.GG || {};

// === 遗物部位定义 ===
window.GG.RelicSlots = [
    { id: 'helmet', name: '头盔', icon: '🪖' },
    { id: 'chest', name: '胸甲', icon: '🛡️' },
    { id: 'belt', name: '腰带', icon: '🔘' },
    { id: 'boots', name: '靴子', icon: '👟' },
    { id: 'necklace', name: '项链', icon: '📿' },
];

// === 主词条候选（按部位）===
window.GG.RelicMainStatPool = {
    helmet: [{ stat: 'hp_flat', name: 'HP', base: 500, perLevel: 80 }],
    chest: [{ stat: 'atk_flat', name: 'ATK', base: 50, perLevel: 8 }],
    belt: [
        { stat: 'def_flat', name: 'DEF', base: 40, perLevel: 6 },
        { stat: 'atk_pct', name: 'ATK%', base: 0.06, perLevel: 0.008 },
    ],
    boots: [
        { stat: 'spd', name: 'SPD', base: 6, perLevel: 0.8 },
        { stat: 'hp_pct', name: 'HP%', base: 0.06, perLevel: 0.008 },
    ],
    necklace: [
        { stat: 'cri_rate', name: '暴击率', base: 0.05, perLevel: 0.006 },
        { stat: 'cri_dmg', name: '爆伤', base: 0.08, perLevel: 0.012 },
        { stat: 'hp_pct', name: 'HP%', base: 0.06, perLevel: 0.008 },
    ],
};

// === 副词条池 ===
window.GG.RelicSubStatPool = [
    { stat: 'atk_pct', name: 'ATK%', range: [0.030, 0.055] },
    { stat: 'def_pct', name: 'DEF%', range: [0.035, 0.060] },
    { stat: 'hp_pct', name: 'HP%', range: [0.035, 0.060] },
    { stat: 'spd', name: 'SPD', range: [2, 5] },
    { stat: 'cri_rate', name: '暴击率', range: [0.025, 0.045] },
    { stat: 'cri_dmg', name: '爆伤', range: [0.040, 0.070] },
    { stat: 'energy_rate', name: '能量恢复', range: [0.04, 0.08] },
    { stat: 'atk_flat', name: 'ATK', range: [15, 35] },
    { stat: 'def_flat', name: 'DEF', range: [12, 28] },
];

// === 稀有度：初始副词条数量、颜色 ===
window.GG.RelicRarityConfig = {
    5: { label: '五星', color: '#f59e0b', glowColor: 'rgba(245,158,11,0.4)', initSubStats: 4, dropWeight: 15 },
    4: { label: '四星', color: '#a855f7', glowColor: 'rgba(168,85,247,0.3)', initSubStats: 3, dropWeight: 35 },
    3: { label: '三星', color: '#6b7280', glowColor: 'rgba(107,114,128,0.2)', initSubStats: 2, dropWeight: 50 },
};

// === 强化费用表 (level 0→1, 1→2, ...) ===
// 目标：0->25 总强化花费精确为 8000
// 采用线性曲线：cost = 80 + level * 20（level:0..24，末段单次560）
window.GG.relicUpgradeCost = (level) => 80 + level * 20;

// === 遗物套装（未来扩展用，现在仅做数据预留）===
window.GG.RelicSets = {
    // 'flame_warrior': {
    //     name: '炎武者套装',
    //     set2: '火属性伤害+10%',
    //     set4: '终极技能必定暴击',
    // },
};
