// 敌人数据表 — 所有敌人的静态配置
// 新敌人类型直接在此处添加
window.GG = window.GG || {};
window.GG.EnemyData = {

    // ===== 第一章敌人 =====
    'wolf': {
        id: 'wolf', name: '荒野狼', icon: '🐺',
        type: 'normal', element: 'wind',
        baseStats: { hp: 380, atk: 45, def: 20, spd: 90 },
        skills: ['wolf_bite', 'wolf_howl'],
        aiPattern: 'aggressive', // aggressive / defensive / random / boss
        drops: { gold: [15, 30], exp: 10 },
        color: '#94a3b8',
    },
    'goblin': {
        id: 'goblin', name: '哥布林战士', icon: '👺',
        type: 'normal', element: 'wind',
        baseStats: { hp: 350, atk: 50, def: 25, spd: 85 },
        skills: ['goblin_slash', 'goblin_throw'],
        aiPattern: 'random',
        drops: { gold: [20, 35], exp: 12 },
        color: '#84cc16',
    },
    'fire_imp': {
        id: 'fire_imp', name: '烈火精灵', icon: '😈',
        type: 'normal', element: 'fire',
        baseStats: { hp: 300, atk: 60, def: 15, spd: 100 },
        skills: ['imp_fireball', 'imp_burn'],
        aiPattern: 'aggressive',
        drops: { gold: [25, 40], exp: 15 },
        color: '#ef4444',
    },
    'stone_golem': {
        id: 'stone_golem', name: '岩石傀儡', icon: '🗿',
        type: 'elite', element: 'wind',
        baseStats: { hp: 800, atk: 65, def: 80, spd: 60 },
        skills: ['golem_slam', 'golem_guard', 'golem_quake'],
        aiPattern: 'defensive',
        drops: { gold: [50, 80], exp: 40 },
        color: '#a8a29e',
        shield: 0, // 护甲值（破甲机制）
    },
    'boss_flame_lord': {
        id: 'boss_flame_lord', name: '炎王·阿格尼斯', icon: '🔥',
        type: 'boss', element: 'fire',
        baseStats: { hp: 4000, atk: 120, def: 60, spd: 85 },
        skills: ['boss_slash', 'boss_fireball', 'boss_meteor_rain', 'boss_enrage'],
        aiPattern: 'boss',
        phaseThreshold: 0.5, // 50%HP时触发第二阶段
        phase2Skills: ['boss_meteor_rain', 'boss_enrage'],
        drops: { gold: [200, 300], exp: 200 },
        color: '#dc2626',
        isBoss: true,
    },

    // ===== 第二章敌人 =====
    'ice_wolf': {
        id: 'ice_wolf', name: '冰霜雪狼', icon: '🐺',
        type: 'normal', element: 'water',
        baseStats: { hp: 500, atk: 70, def: 35, spd: 95 },
        skills: ['wolf_bite', 'ice_wolf_freeze'],
        aiPattern: 'aggressive',
        drops: { gold: [30, 50], exp: 25 },
        color: '#93c5fd',
    },
    'thunder_hawk': {
        id: 'thunder_hawk', name: '雷鹰', icon: '🦅',
        type: 'normal', element: 'thunder',
        baseStats: { hp: 420, atk: 80, def: 25, spd: 115 },
        skills: ['hawk_dive', 'hawk_thunder'],
        aiPattern: 'aggressive',
        drops: { gold: [30, 50], exp: 28 },
        color: '#fde047',
    },
    'dark_knight': {
        id: 'dark_knight', name: '黑暗骑士', icon: '⚔️',
        type: 'elite', element: 'wind',
        baseStats: { hp: 1200, atk: 90, def: 100, spd: 75 },
        skills: ['dk_slash', 'dk_shield', 'dk_deathblow'],
        aiPattern: 'defensive',
        drops: { gold: [80, 130], exp: 80 },
        color: '#6366f1',
    },
    'boss_storm_witch': {
        id: 'boss_storm_witch', name: '暴风女巫·薇薇安', icon: '🧙‍♀️',
        type: 'boss', element: 'thunder',
        baseStats: { hp: 5500, atk: 140, def: 55, spd: 105 },
        skills: ['witch_bolt', 'witch_aoe', 'witch_summon', 'witch_storm'],
        aiPattern: 'boss',
        phaseThreshold: 0.4,
        phase2Skills: ['witch_storm', 'witch_aoe'],
        drops: { gold: [350, 500], exp: 350 },
        color: '#a855f7',
        isBoss: true,
    },

    // ===== 敌人技能定义 =====
};

// 敌人技能（简化版，内嵌在这里）
window.GG.EnemySkillData = {
    'wolf_bite': { name: '撕咬', effects: [{ type: 'damage', target: 'single', multiplier: 1.1 }] },
    'wolf_howl': { name: '嚎叫', effects: [{ type: 'status', target: 'all_enemies', statusId: 'atk_up', duration: 2, value: 0.2 }] },
    'goblin_slash': { name: '乱砍', effects: [{ type: 'damage', target: 'single', multiplier: 1.0 }] },
    'goblin_throw': { name: '投石', effects: [{ type: 'damage', target: 'random', multiplier: 0.8 }] },
    'imp_fireball': { name: '火球', effects: [{ type: 'damage', target: 'single', multiplier: 1.2, element: 'fire' }] },
    'imp_burn': { name: '点火', effects: [{ type: 'status', target: 'random', statusId: 'burn', duration: 2 }] },
    'golem_slam': { name: '重击', effects: [{ type: 'damage', target: 'single', multiplier: 1.4 }] },
    'golem_guard': { name: '石化防御', effects: [{ type: 'status', target: 'self', statusId: 'def_up', duration: 2, value: 0.4 }] },
    'golem_quake': { name: '地震', effects: [{ type: 'damage', target: 'all', multiplier: 0.7 }] },
    'boss_slash': { name: '炎刃斩', effects: [{ type: 'damage', target: 'single', multiplier: 1.3, element: 'fire' }] },
    'boss_fireball': { name: '炎王火球', effects: [{ type: 'damage', target: 'all', multiplier: 0.8, element: 'fire' }] },
    'boss_meteor_rain': { name: '陨石雨', effects: [{ type: 'damage', target: 'all', multiplier: 1.2, element: 'fire' }] },
    'boss_enrage': { name: '狂怒', effects: [{ type: 'status', target: 'self', statusId: 'atk_up', duration: 3, value: 0.5 }] },
    'ice_wolf_freeze': { name: '冰爪', effects: [{ type: 'damage', target: 'single', multiplier: 1.0 }, { type: 'status', target: 'single_enemy', statusId: 'freeze', duration: 1, chance: 0.4 }] },
    'hawk_dive': { name: '俯冲', effects: [{ type: 'damage', target: 'single', multiplier: 1.2 }] },
    'hawk_thunder': { name: '雷翔', effects: [{ type: 'damage', target: 'random', multiplier: 1.0, element: 'thunder' }] },
    'dk_slash': { name: '暗刃', effects: [{ type: 'damage', target: 'single', multiplier: 1.2 }] },
    'dk_shield': { name: '黑暗护盾', cooldown: 2, effects: [{ type: 'status', target: 'self', statusId: 'shield', duration: 2, value: 0.1 }] },
    'dk_deathblow': { name: '死亡之击', effects: [{ type: 'damage', target: 'single', multiplier: 2.0 }] },
    'witch_bolt': { name: '闪电箭', effects: [{ type: 'damage', target: 'single', multiplier: 1.3, element: 'thunder' }] },
    'witch_aoe': { name: '雷暴回旋', effects: [{ type: 'damage', target: 'all', multiplier: 0.9, element: 'thunder' }] },
    'witch_summon': { name: '召唤雷灵', effects: [{ type: 'status', target: 'self', statusId: 'atk_up', duration: 2, value: 0.3 }] },
    'witch_storm': { name: '终极风暴', effects: [{ type: 'damage', target: 'all', multiplier: 1.5, element: 'thunder' }, { type: 'status', target: 'all_enemies', statusId: 'spd_down', duration: 2, value: 0.3 }] },
};
