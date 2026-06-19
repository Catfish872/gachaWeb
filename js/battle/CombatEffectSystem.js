// 战斗效果系统 — 统一处理命座/被动/专属效果的触发管线
window.GG = window.GG || {};
window.GG.CombatEffectSystem = (function () {
    const handlers = {};

    function _arr(trigger) {
        if (!handlers[trigger]) handlers[trigger] = [];
        return handlers[trigger];
    }

    // 注册处理器
    // config: { id, priority, predicate(ctx), handler(ctx) }
    function register(trigger, config) {
        if (!trigger || !config || typeof config.handler !== 'function') return;
        const list = _arr(trigger);
        list.push({
            id: config.id || `effect_${trigger}_${Date.now()}_${Math.random().toString(36).slice(2)}`,
            priority: Number.isFinite(config.priority) ? config.priority : 100,
            predicate: config.predicate,
            handler: config.handler,
        });
        list.sort((a, b) => a.priority - b.priority);
    }

    function emit(trigger, ctx = {}) {
        const list = handlers[trigger];
        if (!list || !list.length) return ctx;
        list.forEach(item => {
            try {
                if (item.predicate && !item.predicate(ctx)) return;
                item.handler(ctx);
            } catch (err) {
                console.error(`[CombatEffectSystem] 处理器执行失败: ${trigger}/${item.id}`, err);
            }
        });
        return ctx;
    }

    function getConstellationLevel(unit) {
        if (!unit?.isAlly) return 0;
        return window.GG.ConstellationSystem?.getLevel?.(unit.id) || 0;
    }

    function getConstellationBonuses(unit) {
        if (!unit?.isAlly) return {};
        return window.GG.ConstellationSystem?.getBonuses?.(unit.id) || {};
    }

    function hasC6Type(unit, c6Type) {
        if (!unit?.isAlly) return false;
        const bonuses = getConstellationBonuses(unit);
        return bonuses?.custom?.c6_type === c6Type;
    }

    function getC6Value(unit, key, fallback = 0) {
        if (!unit?.isAlly) return fallback;
        const bonuses = getConstellationBonuses(unit);
        return bonuses?.custom?.[key] ?? fallback;
    }

    return {
        register,
        emit,
        getConstellationLevel,
        getConstellationBonuses,
        hasC6Type,
        getC6Value,
    };
})();
