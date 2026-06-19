// 关卡数据表
// 新章节/关卡：直接在此添加配置即可
window.GG = window.GG || {};
window.GG.StageData = {
    chapters: [
        {
            id: 'ch1', name: '第一章：流火荒原', description: '传说中的荒野，野兽横行，冒险者的起点。',
            unlocked: true,
            stages: [
                { id: 'ch1_1', name: '1-1 荒野入口', staminaCost: 6, waves: [{ enemies: ['wolf', 'wolf'] }], rewards: { gold: [30, 50], exp: 20, diamonds: 0 }, firstClearRewards: { diamonds: 15 } },
                { id: 'ch1_2', name: '1-2 哥布林营地', staminaCost: 6, waves: [{ enemies: ['goblin', 'wolf'] }], rewards: { gold: [35, 55], exp: 25 }, firstClearRewards: { diamonds: 15 } },
                { id: 'ch1_3', name: '1-3 烈火森林', staminaCost: 6, waves: [{ enemies: ['fire_imp', 'goblin'] }], rewards: { gold: [40, 60], exp: 30 }, firstClearRewards: { diamonds: 15 } },
                { id: 'ch1_4', name: '1-4 岩石峡谷(精英)', staminaCost: 8, waves: [{ enemies: ['stone_golem'] }], rewards: { gold: [60, 90], exp: 50 }, firstClearRewards: { diamonds: 30 }, isElite: true },
                { id: 'ch1_5', name: '1-5 炎王的领地(BOSS)', staminaCost: 10, waves: [{ enemies: ['boss_flame_lord'] }], rewards: { gold: [150, 200], exp: 150 }, firstClearRewards: { diamonds: 60 }, isBoss: true },
            ]
        },
        {
            id: 'ch2', name: '第二章：冰霜雪原', description: '极寒之地，暴风雪掩盖了一切，危机四伏。',
            unlocked: false, unlockCondition: 'ch1_5',
            stages: [
                { id: 'ch2_1', name: '2-1 冰封平原', staminaCost: 8, waves: [{ enemies: ['ice_wolf', 'ice_wolf'] }], rewards: { gold: [60, 90], exp: 45 }, firstClearRewards: { diamonds: 20 } },
                { id: 'ch2_2', name: '2-2 雷鹰巢穴', staminaCost: 8, waves: [{ enemies: ['thunder_hawk', 'thunder_hawk'] }], rewards: { gold: [65, 95], exp: 50 }, firstClearRewards: { diamonds: 20 } },
                { id: 'ch2_3', name: '2-3 黑暗要塞', staminaCost: 8, waves: [{ enemies: ['ice_wolf', 'dark_knight'] }], rewards: { gold: [70, 100], exp: 55 }, firstClearRewards: { diamonds: 20 } },
                { id: 'ch2_4', name: '2-4 女巫的祭坛(精英)', staminaCost: 10, waves: [{ enemies: ['dark_knight', 'thunder_hawk'] }], rewards: { gold: [100, 150], exp: 100 }, firstClearRewards: { diamonds: 40 }, isElite: true },
                { id: 'ch2_5', name: '2-5 风暴女巫(BOSS)', staminaCost: 12, waves: [{ enemies: ['boss_storm_witch'] }], rewards: { gold: [250, 350], exp: 300 }, firstClearRewards: { diamonds: 80 }, isBoss: true },
            ]
        },
        // ========== 未来章节扩展预留 ==========
        // 直接添加新章节对象到此数组即可
    ],

    // 深渊塔预留接口（本期不实现，保留数据结构）
    dungeonTower: {
        enabled: false,
        floors: [], // 每层配置，未来填充
    },
};
