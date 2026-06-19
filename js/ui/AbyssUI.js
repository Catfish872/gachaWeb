// 深渊主界面与流程控制
window.GG = window.GG || {};
window.GG.AbyssUI = (function () {
    const AS = () => window.GG.AbyssSystem;
    const GE = () => window.GG.GameEngine;
    const S = () => window.GG.SaveSystem;
    const EB = () => window.GG.EventBus;

    let _binded = false;

    function open() {
        const page = document.getElementById('page-abyss');
        if (!page) return;
        page.style.display = 'block';

        if (!_binded) {
            _bindEvents();
            _binded = true;
        }
        _render();
    }

    function close() {
        const page = document.getElementById('page-abyss');
        if (page) page.style.display = 'none';
    }

    function _render() {
        const page = document.getElementById('page-abyss');
        if (!page) return;
        const prog = AS().getProgress();
        const save = S().get();
        const diamonds = save.resources?.diamonds || 0;
        const isSuspended = !!prog.savedPartyState; // 有暂存状态即“挑战进行中”

        page.innerHTML = `
        <div class="abyss-container">
            <div class="abyss-header">
                <h2>🌀 虚空之塔</h2>
                <div class="abyss-record">历史最高：<strong>${prog.maxFloor || 0}</strong> 层</div>
            </div>
            <div class="abyss-main-panel">
                <div class="abyss-current-floor">
                    <div class="label">当前挑战领域</div>
                    <div class="value">第 <span>${prog.currentFloor}</span> 层</div>
                </div>
                <div class="abyss-desc">
                    无尽的维度撕裂挑战，敌方强度将进行无限的量子膨胀。<br/>通关后角色状态自动截取，无法恢复基础生命与技能矩阵冷却。<br/>
                    <strong>突破屏障必获得 4星/5星 极品遗物！</strong>
                </div>
                <div class="abyss-actions">
                    ${isSuspended ? `
                        <button class="abyss-btn-start" onclick="window.GG.AbyssUI.handleStart()">
                            <span style="font-size:1.5rem">⚙️</span> 继续挑战记录
                        </button>
                    ` : `
                        <button class="abyss-btn-start" onclick="window.GG.AbyssUI.handleStart()">
                            <span style="font-size:1.5rem">⚔️</span> 开启深渊位面
                        </button>
                    `}
                    
                    <div class="abyss-reset-box">
                        <button class="abyss-btn-reset" onclick="window.GG.AbyssUI.handleReset()">
                            🔄 坍缩进度至第1层 
                            <small>(${AS().canFreeReset() ? '<span style="color:#22c55e">今日免费</span>' : '100 💎'})</small>
                        </button>
                    </div>
                </div>
            </div>
        </div>`;
    }

    function _handleStart() {
        const result = GE().enterAbyssLayer();
        if (result.success) {
            // 关闭主界面并打开战斗界面
            window.GG.UIManager.showPage('stages'); // 退到后台
            const stageConfig = window.GG.AbyssData.generateStageConfig(AS().getProgress().currentFloor);
            window.GG.BattleUI.open(stageConfig.id, true);
        } else {
            window.GG.UIManager.showToast(result.error, 'error');
        }
    }

    function _handleReset() {
        const useDiamonds = !AS().canFreeReset();
        if (useDiamonds) {
            const cost = window.GG.AbyssData.resetDiamondCost || 100;
            const diamonds = S().get().resources?.diamonds || 0;
            if (diamonds < cost) {
                window.GG.UIManager.showToast('钻石不足，无法重置进度', 'error');
                return;
            }
            // 自定义美化确认弹窗
            const overlay = document.createElement('div');
            overlay.className = 'modal-overlay';
            overlay.innerHTML = `
                <div class="abyss-modal-content">
                    <div class="abyss-modal-icon">⚠️</div>
                    <h3 class="abyss-modal-title">重置深渊领域</h3>
                    <p class="abyss-modal-desc">此操作将放弃当前所有进度记录与角色状态，重新坍缩至第 1 层。<br>今日免费重置次数已耗尽，需使用星尘晶。</p>
                    <div class="abyss-modal-cost">${cost} 💎</div>
                    <div class="abyss-modal-actions" style="margin-top:20px">
                        <button class="abyss-btn-cancel" id="abyss-reset-cancel">暂不重置</button>
                        <button class="abyss-btn-confirm" id="abyss-reset-confirm">确认重置</button>
                    </div>
                </div>`;
            document.body.appendChild(overlay);

            overlay.querySelector('#abyss-reset-cancel').onclick = () => overlay.remove();
            overlay.querySelector('#abyss-reset-confirm').onclick = () => {
                overlay.remove();
                _executeReset(true);
            };
        } else {
            _executeReset(false);
        }
    }

    function _executeReset(useDiamonds) {
        const res = AS().reset(useDiamonds);
        if (res.success) {
            window.GG.UIManager.showToast('深渊进度已重置，队伍状态已恢复', 'success');
            _render();
        } else {
            window.GG.UIManager.showToast(res.error, 'error');
        }
    }

    function _bindEvents() {
        // ... (预留事件订阅空间)
    }

    return { open, close, handleStart: _handleStart, handleReset: _handleReset };
})();
