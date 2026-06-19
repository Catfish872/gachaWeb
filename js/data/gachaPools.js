// 卡池配置表
// 新卡池直接在此添加对象，无需修改抽卡逻辑
window.GG = window.GG || {};
window.GG.GachaPoolData = {

    // 当前开放的卡池列表（UI显示顺序）
    activePools: ['standard', 'limited_kaldi'],

    pools: {
        'standard': {
            id: 'standard',
            name: '群星降临',
            subtitle: '常驻祈愿',
            type: 'standard',
            banner: '🌟',
            costPerPull: 160, // 星尘晶/抽
            currency: 'diamonds',
            description: '常驻卡池，包含全部常驻角色',
            endTime: null, // null = 永久开放
            // 稀有度概率
            rates: { 5: 0.016, 4: 0.15, 3: 0.834 },
            // 保底设置
            pity: { soft: 73, hard: 90, softIncrease: 0.06 },
            // 大保底（限定池专用，常驻池无此概念）
            guaranteedFeatured: false,
            // 五星概率一半是 featured，一半是常驻
            featuredRate5: 0.5,
            featuredRate4: 0.5,
            // 角色池
            featured5: ['kaldi', 'ayla'],
            pool5: ['kaldi', 'ayla'],
            featured4: ['gus', 'shana', 'lorin'],
            pool4: ['gus', 'shana', 'lorin'],
            pool3: ['ember', 'zeph', 'bolt', 'tide', 'cinder'],
            color: '#7c3aed',
            gradientFrom: '#1e1b4b', gradientTo: '#312e81',
        },

        'limited_kaldi': {
            id: 'limited_kaldi',
            name: '炎龙觉醒',
            subtitle: '限定祈愿 · 焰龙·卡尔迪',
            type: 'limited',
            banner: '🐉',
            costPerPull: 160,
            currency: 'diamonds',
            description: '限定卡池！焰龙·卡尔迪概率提升！50%概率为UP角色，若未获得UP则下次必出。',
            endTime: null, // 模拟游戏：不过期
            rates: { 5: 0.016, 4: 0.15, 3: 0.834 },
            pity: { soft: 73, hard: 90, softIncrease: 0.06 },
            guaranteedFeatured: true, // 大保底开关
            featuredRate5: 0.5, // 五星时50%是UP
            featuredRate4: 0.5, // 四星时50%是UP
            featured5: ['kaldi'], // UP五星
            pool5: ['kaldi', 'ayla'], // 全部可能五星（仅5星角色）
            featured4: ['gus', 'shana'], // UP四星
            pool4: ['gus', 'shana', 'lorin'],
            pool3: ['ember', 'zeph', 'bolt', 'tide', 'cinder'],
            color: '#dc2626',
            gradientFrom: '#450a0a', gradientTo: '#7f1d1d',
        },

        // ========== 限定/武器池扩展预留 ==========
        // 新卡池模板：
        // 'new_pool_id': { id, name, subtitle, type:'limited', banner, costPerPull:160, ... }
    },
};
