// 深渊塔数据与怪物生成规则
window.GG = window.GG || {};
window.GG.AbyssData = {
    // 基础配置
    resetDiamondCost: 100,
    dailyFreeResets: 1,

    // 深渊掉落（必掉）
    rewards: {
        gold: [150, 300], // 基础金币，随层数增加
        exp: 200,         // 基础经验
        relicRarity: [4, 5], // 层数越高，5星概率越大，第10层开始只掉5星
    },

    // 敌人模板池（普通/精英/BOSS）
    pools: {
        normal: ['wolf', 'goblin', 'fire_imp', 'ice_wolf', 'dark_knight'],
        elite: ['stone_golem', 'thunder_hawk'],
        boss: ['boss_flame_lord', 'boss_storm_witch']
    },

    // 属性无限膨胀公式
    // 参数含义：floor - 当前层数, baseStats - 敌人原书面属性
    calcInflatedStats: function (floor, enemyId) {
        // 核心公式：基于层数指数+线性混合膨胀，加入一定随机波动（75%~125%）
        // 前期（1-10层）线性增长明显，后期（几十层）指数增长带来绝对压制

        const linearFactor = 1 + (floor - 1) * 0.25; // 每层增加25%基础属性
        const expFactor = Math.pow(1.08, floor - 1); // 每层复利增加8%

        let multiplier = (linearFactor * 0.6 + expFactor * 0.4);

        // 随机波动系数（当前层数的变数）
        // 比如某些层怪物攻击奇高，某些层血量奇厚，由一个伪随机数控制偏向
        // 用层数+怪物ID做种子产生稳定性伪随机
        const salt = floor * (enemyId.charCodeAt(0) || 1);
        const randFloat = (Math.sin(salt) + 1) / 2; // 0~1

        // HP 波动倍率: 0.8 ~ 1.2
        const hpMod = 0.8 + randFloat * 0.4;
        // ATK 波动倍率: (1 - randFloat) 反向补偿
        const atkMod = 0.8 + (1 - randFloat) * 0.4;
        // SPD 增长较慢（防完全没法出手）
        const spdMultiplier = 1 + (floor - 1) * 0.05;

        return {
            hpMod: multiplier * hpMod,
            atkMod: multiplier * atkMod,
            defMod: multiplier,    // 防御直接套用综合倍率
            spdMod: spdMultiplier, // 速度缓慢增长
            scaleMult: multiplier  // 综合强度评级
        };
    },

    // 动态生成深渊某层配置
    generateStageConfig: function (floor) {
        const isBossFloor = floor % 10 === 0;
        const isEliteFloor = floor > 1 && floor % 5 === 0 && !isBossFloor;

        let enemyPool = this.pools.normal;
        let count = 2 + Math.floor(Math.random() * 2); // 2~3只怪

        if (isBossFloor) {
            enemyPool = this.pools.boss;
            count = 1; // 单体BOSS
        } else if (isEliteFloor) {
            enemyPool = this.pools.elite;
            count = 1 + Math.floor(Math.random() * 2); // 1~2只精英
        } else if (floor > 20) {
            // 后期杂兵层也可能混入精英
            enemyPool = this.pools.normal.concat(this.pools.elite);
        }

        // 随机抽取
        const enemies = [];
        for (let i = 0; i < count; i++) {
            const eid = enemyPool[Math.floor(Math.random() * enemyPool.length)];
            enemies.push(eid);
        }

        return {
            id: `abyss_floor_${floor}`,
            name: `深渊 第 ${floor} 层`,
            isAbyss: true,
            floor: floor,
            staminaCost: 0, // 深渊不消耗通常体力
            isBoss: isBossFloor,
            isElite: isEliteFloor,
            enemies: enemies, // 放在第一层，适配 initBattle 获取
            // 奖励在 BattleEngine / AbyssSystem 动态计算
            rewards: null
        };
    }
};
