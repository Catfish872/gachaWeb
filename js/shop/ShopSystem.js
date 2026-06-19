// 商城系统 — 充值和道具购买逻辑
window.GG = window.GG || {};
window.GG.ShopSystem = (function () {
    const S = () => window.GG.SaveSystem;
    const EB = () => window.GG.EventBus;
    const ShopData = () => window.GG.ShopData;

    // 购买充值档位（直接到账，模拟氪金）
    function purchaseRecharge(itemId) {
        const item = ShopData().rechargeItems.find(i => i.id === itemId);
        if (!item) return { success: false, error: '商品不存在' };

        const save = S().get();
        item.rewards.forEach(reward => {
            switch (reward.type) {
                case 'diamonds':
                    S().modifyResource('diamonds', reward.amount);
                    break;
                case 'stamina': {
                    const cur = save.resources.stamina;
                    const max = window.GG.StaminaSystem.MAX_STAMINA;
                    S().setResource('stamina', Math.min(cur + reward.amount, max + 200));
                    break;
                }
                case 'gold':
                    S().modifyResource('gold', reward.amount);
                    break;
            }
        });

        EB().emit('shop:purchased', 'recharge', itemId, item.rewards);
        return { success: true, item, rewards: item.rewards };
    }

    // 购买道具商店（扣金币）
    function purchaseItem(itemId) {
        const item = ShopData().itemShop.find(i => i.id === itemId);
        if (!item) return { success: false, error: '商品不存在' };
        if (!S().modifyResource('gold', -item.price)) {
            return { success: false, error: '金币不足' };
        }
        item.rewards.forEach(reward => {
            if (reward.type === 'diamonds') S().modifyResource('diamonds', reward.amount);
            if (reward.type === 'stamina') S().modifyResource('stamina', reward.amount);
            if (reward.type === 'gold') S().modifyResource('gold', reward.amount);
        });
        EB().emit('shop:purchased', 'item', itemId, item.rewards);
        return { success: true, item, rewards: item.rewards };
    }

    // 预留接口：碎片商店（未来实现）
    function purchaseFragment(itemId) {
        console.log('[ShopSystem] 碎片商店功能预留，尚未实现:', itemId);
        return { success: false, error: '功能即将开放' };
    }

    return { purchaseRecharge, purchaseItem, purchaseFragment };
})();
