// 商城界面 UI
window.GG = window.GG || {};
window.GG.ShopUI = (function () {
    const ShopSys = () => window.GG.ShopSystem;
    const ShopData = () => window.GG.ShopData;
    const UI = () => window.GG.UIManager;

    function init() { render(); }

    function render() {
        const page = document.getElementById('page-shop');
        if (!page) return;
        page.innerHTML = '';

        const container = document.createElement('div');
        container.style.padding = '14px';

        // 顶部说明
        container.innerHTML = `
      <h2 style="font-size:1rem;font-weight:700;margin-bottom:4px">💎 充值商城</h2>
      <p style="font-size:0.72rem;color:#94a3b8;margin-bottom:16px">点击即可直接获得，体验氪金爽感！</p>
      <div class="shop-section-title">🎁 充值档位</div>
      <div class="recharge-grid" id="recharge-grid"></div>
      <div class="shop-section-title" style="margin-top:8px">🛒 道具商店</div>
      <div id="item-shop-list"></div>`;
        page.appendChild(container);

        _renderRecharge();
        _renderItemShop();
    }

    function _renderRecharge() {
        const grid = document.getElementById('recharge-grid');
        if (!grid) return;
        ShopData().rechargeItems.forEach(item => {
            const card = document.createElement('div');
            card.className = 'recharge-card';
            card.style.setProperty('--card-color', item.color || '#7c3aed');
            card.innerHTML = `
        ${item.badge ? `<div class="recharge-badge">${item.badge}</div>` : ''}
        <div class="recharge-icon">${item.icon}</div>
        <div class="recharge-info">
          <div class="recharge-name">${item.name}</div>
          <div class="recharge-rewards">
            ${item.rewards.map(r => `<span class="recharge-reward-tag">${r.label}</span>`).join('')}
          </div>
        </div>
        <div class="recharge-price">${item.priceDisplay}</div>`;
            card.addEventListener('click', () => {
                const result = ShopSys().purchaseRecharge(item.id);
                if (result.success) {
                    UI().updateResourceBar();
                    // 显示获得动画
                    _showPurchaseEffect(card, item.rewards);
                    UI().showToast(`已获得 ${item.name}！`, 'success');
                } else {
                    UI().showToast(result.error, 'error');
                }
            });
            grid.appendChild(card);
        });
    }

    function _renderItemShop() {
        const list = document.getElementById('item-shop-list');
        if (!list) return;
        ShopData().itemShop.forEach(item => {
            const card = document.createElement('div');
            card.className = 'recharge-card';
            card.style.setProperty('--card-color', '#7c3aed');
            card.innerHTML = `
        <div class="recharge-icon">${item.icon}</div>
        <div class="recharge-info">
          <div class="recharge-name">${item.name}</div>
          <div class="recharge-rewards">
            ${item.rewards.map(r => `<span class="recharge-reward-tag">${r.label}</span>`).join('')}
          </div>
        </div>
        <div class="recharge-price" style="font-size:0.9rem">🪙<br>${item.price.toLocaleString()}</div>`;
            card.addEventListener('click', () => {
                const result = ShopSys().purchaseItem(item.id);
                if (result.success) {
                    UI().updateResourceBar();
                    _showPurchaseEffect(card, item.rewards);
                    UI().showToast(`购买成功！`, 'success');
                } else {
                    UI().showToast(result.error, 'error');
                }
            });
            list.appendChild(card);
        });

        // 碎片商店预留
        const comingSoon = document.createElement('div');
        comingSoon.style.cssText = 'text-align:center;padding:20px;color:#475569;font-size:0.8rem';
        comingSoon.innerHTML = '🔒 碎片商店 · 即将开放';
        list.appendChild(comingSoon);
    }

    function _showPurchaseEffect(card, rewards) {
        // 简单的按下弹起效果
        card.style.transform = 'scale(0.96)';
        setTimeout(() => card.style.transform = '', 200);
        // 飘字效果：用动画显示获得内容
        rewards.forEach((r, i) => {
            setTimeout(() => {
                window.GG.BattleAnimator?.spawnFloatText?.(card, `+${r.amount} ${r.type === 'diamonds' ? '💎' : r.type === 'stamina' ? '⚡' : '🪙'}`, 'heal');
            }, i * 200);
        });
    }

    return { init, render };
})();
