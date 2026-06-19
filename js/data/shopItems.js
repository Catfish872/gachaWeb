// 商城商品配置表
// 新商品直接在此添加，无需修改其他代码
window.GG = window.GG || {};
window.GG.ShopData = {

    // 充值档位（模拟氪金，点击即得）
    rechargeItems: [
        {
            id: 'recharge_traveler', name: '旅者补给', price: '¥6',
            priceDisplay: '¥6', badge: '首充推荐',
            icon: '🎒', color: '#22c55e',
            description: '适合初探旅途的探险家',
            rewards: [
                { type: 'diamonds', amount: 60, label: '💎 星尘晶 ×60' },
                { type: 'stamina', amount: 60, label: '⚡ 体力 ×60' },
            ],
        },
        {
            id: 'recharge_monthly', name: '冒险月卡', price: '¥30',
            priceDisplay: '¥30', badge: '超值',
            icon: '📅', color: '#3b82f6',
            description: '月卡特权，出行的必备之选',
            rewards: [
                { type: 'diamonds', amount: 300, label: '💎 星尘晶 ×300' },
                { type: 'stamina', amount: 300, label: '⚡ 体力 ×300' },
            ],
        },
        {
            id: 'recharge_hero', name: '英雄礼包', price: '¥68',
            priceDisplay: '¥68', badge: '热门',
            icon: '⚔️', color: '#f59e0b',
            description: '为英雄而备的战斗补给',
            rewards: [
                { type: 'diamonds', amount: 680, label: '💎 星尘晶 ×680' },
                { type: 'stamina', amount: 680, label: '⚡ 体力 ×680' },
                { type: 'gold', amount: 50000, label: '🪙 金币 ×50,000' },
            ],
        },
        {
            id: 'recharge_legend', name: '传说巨擘', price: '¥128',
            priceDisplay: '¥128', badge: '',
            icon: '👑', color: '#a855f7',
            description: '传说级别的恢宏馈赠',
            rewards: [
                { type: 'diamonds', amount: 1280, label: '💎 星尘晶 ×1,280' },
                { type: 'stamina', amount: 1280, label: '⚡ 体力 ×1,280' },
                { type: 'gold', amount: 150000, label: '🪙 金币 ×150,000' },
            ],
        },
        {
            id: 'recharge_supreme', name: '至尊套餐', price: '¥328',
            priceDisplay: '¥328', badge: '最划算',
            icon: '💎', color: '#ec4899',
            description: '最顶级的旅者馈赠，无与伦比',
            rewards: [
                { type: 'diamonds', amount: 3280, label: '💎 星尘晶 ×3,280' },
                { type: 'stamina', amount: 3280, label: '⚡ 体力 ×3,280' },
                { type: 'gold', amount: 500000, label: '🪙 金币 ×500,000' },
            ],
        },
    ],

    // 道具商店（用金币购买）
    itemShop: [
        {
            id: 'buy_stamina_60', name: '体力水晶', icon: '⚡',
            price: 5000, currency: 'gold',
            rewards: [{ type: 'stamina', amount: 60, label: '⚡ 体力 ×60' }],
            stock: -1, // -1 = 无限
        },
        {
            id: 'buy_diamonds_500', name: '星尘宝箱', icon: '💎',
            price: 5000, currency: 'gold',
            rewards: [{ type: 'diamonds', amount: 500, label: '💎 星尘晶 ×500' }],
            stock: -1,
        },
    ],

    // 碎片商店（预留接口）
    fragmentShop: {
        enabled: false,
        items: [],
    },
};
