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

    rogue: {
        rewardFloorsInCycle: [3, 6, 9],
        focusMin: 0.15,
        focusMax: 0.45,
        focusGainOnPick: 0.10,
        rarityWeights: {
            white: 62,
            blue: 30,
            gold: 8,
        },
        rarityMeta: {
            white: { label: '白', color: '#e5e7eb', icon: '◇' },
            blue: { label: '蓝', color: '#60a5fa', icon: '◆' },
            gold: { label: '金', color: '#fbbf24', icon: '✦' },
        },
        rewards: [
            { id: 'common_atk_white', pool: 'common', rarity: 'white', name: '磨砺锋刃', icon: '⚔️', target: '全队', description: '本局深渊中，全队攻击力提高 8%。', effects: [{ type: 'stat', stat: 'atkMult', value: 0.08 }] },
            { id: 'common_hp_white', pool: 'common', rarity: 'white', name: '坚韧体魄', icon: '❤️', target: '全队', description: '本局深渊中，全队最大生命提高 10%。', effects: [{ type: 'stat', stat: 'maxHpMult', value: 0.10 }] },
            { id: 'common_def_white', pool: 'common', rarity: 'white', name: '临战护甲', icon: '🛡️', target: '全队', description: '本局深渊中，全队防御力提高 10%。', effects: [{ type: 'stat', stat: 'defMult', value: 0.10 }] },
            { id: 'common_energy_white', pool: 'common', rarity: 'white', name: '微光回路', icon: '🔋', target: '全队', description: '本局深渊中，非终结技获得的能量提高 15%。', effects: [{ type: 'energyGainMult', value: 0.15 }] },
            { id: 'common_crit_blue', pool: 'common', rarity: 'blue', name: '精准校准', icon: '🎯', target: '全队', description: '本局深渊中，全队暴击率提高 8%，暴击伤害提高 15%。', effects: [{ type: 'stat', stat: 'criAdd', value: 0.08 }, { type: 'stat', stat: 'criDmgAdd', value: 0.15 }] },
            { id: 'common_open_shield_blue', pool: 'common', rarity: 'blue', name: '位面护膜', icon: '🛡️', target: '全队', description: '每场深渊战斗开始时，全队获得 2 回合护盾。', effects: [{ type: 'battleStartStatus', statusId: 'shield', duration: 2, value: 0.22 }] },
            { id: 'common_victory_heal_blue', pool: 'common', rarity: 'blue', name: '战后整备', icon: '🏕️', target: '全队', description: '每次深渊胜利后，存活角色恢复 18% 最大生命。', effects: [{ type: 'victoryHealPct', value: 0.18 }] },
            { id: 'common_open_energy_gold', pool: 'common', rarity: 'gold', name: '星核预热', icon: '🌟', target: '全队', description: '每场深渊战斗开始时，全队获得 35 点能量。', effects: [{ type: 'battleStartEnergy', value: 35 }] },
            { id: 'common_guard_gold', pool: 'common', rarity: 'gold', name: '裂隙庇护', icon: '💠', target: '全队', description: '本局深渊中，全队受到的直接伤害降低 10%。', effects: [{ type: 'damageTakenMult', value: -0.10 }] },
            { id: 'common_overdrive_gold', pool: 'common', rarity: 'gold', name: '超频矩阵', icon: '⚡', target: '全队', description: '本局深渊中，全队攻击力提高 18%，速度提高 8%。', effects: [{ type: 'stat', stat: 'atkMult', value: 0.18 }, { type: 'stat', stat: 'spdMult', value: 0.08 }] },

            { id: 'kaldi_burn_amp_white', pool: 'character', characterId: 'kaldi', rarity: 'white', name: '余烬辨识', icon: '🔥', target: '燃烧构筑', description: '全队攻击燃烧目标时，造成的直接伤害提高 14%。', effects: [{ type: 'damageVsStatus', statusId: 'burn', value: 0.14 }] },
            { id: 'kaldi_burn_spread_blue', pool: 'character', characterId: 'kaldi', rarity: 'blue', name: '龙炎蔓延', icon: '💥', target: '燃烧构筑', description: '全队造成火属性伤害后，有 35% 概率使目标燃烧 2 回合。', effects: [{ type: 'applyStatusAfterDamage', element: 'fire', statusId: 'burn', duration: 2, chance: 0.35 }] },
            { id: 'kaldi_ult_burn_blue', pool: 'character', characterId: 'kaldi', rarity: 'blue', name: '终焰回响', icon: '🐉', target: '终结技', description: '全队终结技伤害提高 18%；若目标燃烧，额外再提高 12%。', effects: [{ type: 'skillTypeDamage', skillType: 'ultimate', value: 0.18 }, { type: 'skillTypeDamageVsStatus', skillType: 'ultimate', statusId: 'burn', value: 0.12 }] },
            { id: 'kaldi_burn_execute_gold', pool: 'character', characterId: 'kaldi', rarity: 'gold', name: '不灭炎心', icon: '🔥', target: '燃烧构筑', description: '全队命中燃烧目标后，追加一次攻击力 20% 的真实火属性伤害（无视防御）。每次技能每个目标触发一次。', effects: [{ type: 'extraDamageVsStatus', statusId: 'burn', multiplier: 0.2, element: 'fire', trueDamage: true }] },
            { id: 'kaldi_start_burn_gold', pool: 'character', characterId: 'kaldi', rarity: 'gold', name: '焚界开幕', icon: '🌋', target: '开场压制', description: '每场深渊战斗开始时，所有敌人陷入燃烧 3 回合。', effects: [{ type: 'enemyBattleStartStatus', statusId: 'burn', duration: 3 }] },

            { id: 'ayla_heal_amp_white', pool: 'character', characterId: 'ayla', rarity: 'white', name: '霜语祷文', icon: '✨', target: '治疗构筑', description: '全队造成的治疗量提高 16%。', effects: [{ type: 'healMult', value: 0.16 }] },
            { id: 'ayla_regen_guard_blue', pool: 'character', characterId: 'ayla', rarity: 'blue', name: '极光余辉', icon: '💚', target: '再生构筑', description: '处于再生的我方单位受到的直接伤害降低 15%。', effects: [{ type: 'damageTakenWhileStatus', statusId: 'regen', value: -0.15 }] },
            { id: 'ayla_freeze_break_blue', pool: 'character', characterId: 'ayla', rarity: 'blue', name: '碎冰棱镜', icon: '❄️', target: '冻结构筑', description: '全队攻击冰冻目标时，直接伤害提高 22%。', effects: [{ type: 'damageVsStatus', statusId: 'freeze', value: 0.22 }] },
            { id: 'ayla_heal_regen_gold', pool: 'character', characterId: 'ayla', rarity: 'gold', name: '圣女回声', icon: '🌌', target: '治疗构筑', description: '全队每次治疗后，为治疗目标附加 2 回合再生。', effects: [{ type: 'statusAfterHeal', statusId: 'regen', duration: 2 }] },
            { id: 'ayla_open_freeze_gold', pool: 'character', characterId: 'ayla', rarity: 'gold', name: '永霜帷幕', icon: '🧊', target: '控场构筑', description: '每场深渊战斗开始时，随机 1 名敌人冰冻 1 回合，全队攻击冻结目标时额外获得 15 点能量。', effects: [{ type: 'enemyBattleStartStatus', statusId: 'freeze', duration: 1, count: 1 }, { type: 'energyOnHitStatus', statusId: 'freeze', value: 15 }] },
        ],
    },

    // 属性无限膨胀公式
    // 参数含义：floor - 当前层数, baseStats - 敌人原书面属性
    calcInflatedStats: function (floor, enemyId) {
        // 核心公式：50层前只做线性成长；50层后才开始计入削弱后的指数成长。
        // 这样前中期不会被指数膨胀压死，高层仍保留长期爬塔压力。

        const linearFactor = 1 + (floor - 1) * 0.33; // 线性成长保留，保证层数推进仍有压力
        const exponentFloor = Math.max(0, floor - 50);
        const expFactor = Math.pow(1.042, exponentFloor); // 指数成长从50层后开始，略高于前版 1.035，但仍显著低于旧版 1.105

        let multiplier = (linearFactor * 0.70 + expFactor * 0.30);

        // 随机波动系数（当前层数的变数）
        // 比如某些层怪物攻击奇高，某些层血量奇厚，由一个伪随机数控制偏向
        // 用层数+怪物ID做种子产生稳定性伪随机
        const salt = floor * (enemyId.charCodeAt(0) || 1);
        const randFloat = (Math.sin(salt) + 1) / 2; // 0~1

        // HP 波动倍率: 0.86 ~ 1.22
        const hpMod = 0.86 + randFloat * 0.36;
        // ATK 额外成长更高，避免奖励后无限平推；指数压力同样从50层后才开始。
        const atkMod = 0.92 + (1 - randFloat) * 0.48;
        const atkPressure = 1 + Math.max(0, floor - 1) * 0.025 + Math.pow(1.011, exponentFloor) - 1;
        // 防御中等提高
        const defPressure = 1 + Math.max(0, floor - 1) * 0.012;
        // SPD 温和增长（防完全没法出手）
        const spdMultiplier = 1 + (floor - 1) * 0.035;

        return {
            hpMod: multiplier * hpMod,
            atkMod: multiplier * atkMod * atkPressure,
            defMod: multiplier * defPressure,
            spdMod: spdMultiplier,
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
