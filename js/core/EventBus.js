// 全局事件总线 — 发布/订阅模式
// 用于模块间解耦通信，未来扩展多人/远程时可适配为网络事件
window.GG = window.GG || {};
window.GG.EventBus = (function () {
    const listeners = {};

    return {
        // 订阅事件
        on(event, callback, context = null) {
            if (!listeners[event]) listeners[event] = [];
            listeners[event].push({ callback, context });
        },
        // 取消订阅
        off(event, callback) {
            if (!listeners[event]) return;
            listeners[event] = listeners[event].filter(l => l.callback !== callback);
        },
        // 发布事件
        emit(event, ...args) {
            if (!listeners[event]) return;
            listeners[event].forEach(l => {
                try {
                    l.callback.apply(l.context, args);
                } catch (err) {
                    console.error(`[EventBus] 事件监听执行失败: ${event}`, err);
                }
            });
        },
        // 一次性订阅
        once(event, callback) {
            const wrapper = (...args) => { callback(...args); this.off(event, wrapper); };
            this.on(event, wrapper);
        },
        // 清除所有事件（预留：切换场景时调用）
        clear(event) {
            if (event) { delete listeners[event]; }
            else { Object.keys(listeners).forEach(k => delete listeners[k]); }
        },
        // 调试：列出所有监听器
        debug() { return Object.keys(listeners).map(k => ({ event: k, count: listeners[k].length })); },
    };
})();
