// 体力系统 — 基于真实时间自动恢复
window.GG = window.GG || {};
window.GG.StaminaSystem = (function () {
    const MAX_STAMINA = 100;
    const RECOVERY_RATE_MS = 6 * 60 * 1000; // 每6分钟恢复1点（实际游戏节奏）
    let _tickInterval = null;

    const S = window.GG.SaveSystem;
    const EB = window.GG.EventBus;

    // 根据时间差计算并填入体力
    function recoverStamina() {
        const save = S.get();
        if (!save) return;
        const now = Date.now();
        const lastUpdate = save.resources.staminaLastUpdate || now;
        const elapsed = now - lastUpdate;
        const recovered = Math.floor(elapsed / RECOVERY_RATE_MS);
        if (recovered <= 0) return;

        const current = save.resources.stamina;
        if (current >= MAX_STAMINA) {
            save.resources.staminaLastUpdate = now; // 重置计时（满体力不累计）
            S.save();
            return;
        }

        const newStamina = Math.min(current + recovered, MAX_STAMINA);
        save.resources.stamina = newStamina;
        save.resources.staminaLastUpdate = lastUpdate + recovered * RECOVERY_RATE_MS;
        S.save();
        if (recovered > 0) EB.emit('resource:changed', 'stamina', newStamina);
    }

    return {
        MAX_STAMINA,
        RECOVERY_RATE_MS,

        // 初始化（游戏启动时调用）
        init() {
            recoverStamina(); // 先补算离线体力
            _tickInterval = setInterval(() => {
                recoverStamina();
                EB.emit('stamina:tick');
            }, 10000); // 每10秒检查一次（节省性能）
        },

        // 获取当前体力
        getCurrent() {
            recoverStamina(); // 读取前先结算
            return S.getResource('stamina');
        },

        // 获取最大体力
        getMax() { return MAX_STAMINA; },

        // 消耗体力（返回是否成功）
        consume(amount) {
            recoverStamina();
            const current = this.getCurrent();
            if (current < amount) return false;
            S.setResource('stamina', current - amount);
            S.save();
            return true;
        },

        // 添加体力（充值/道具等）
        add(amount) {
            const current = S.getResource('stamina');
            const newVal = Math.min(current + amount, MAX_STAMINA + 200); // 溢出上限
            S.setResource('stamina', newVal);
        },

        // 获取距离下一点体力恢复的剩余毫秒数
        getTimeToNextRecover() {
            const save = S.get();
            if (!save) return 0;
            if (save.resources.stamina >= MAX_STAMINA) return 0;
            const elapsed = Date.now() - (save.resources.staminaLastUpdate || Date.now());
            const remaining = RECOVERY_RATE_MS - (elapsed % RECOVERY_RATE_MS);
            return remaining;
        },

        // 格式化剩余时间为字符串（如 "05:32"）
        formatTimeToRecover() {
            const ms = this.getTimeToNextRecover();
            if (ms <= 0) return '已满';
            const mins = Math.floor(ms / 60000);
            const secs = Math.floor((ms % 60000) / 1000);
            return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
        },

        destroy() {
            if (_tickInterval) clearInterval(_tickInterval);
        },
    };
})();
