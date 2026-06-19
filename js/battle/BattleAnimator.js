// 战斗动画控制器 — 驱动所有 CSS 动画
window.GG = window.GG || {};
window.GG.BattleAnimator = (function () {
    const EB = () => window.GG.EventBus;
    const BE = () => window.GG.BattleEngine;

    function _speed() {
        return Math.max(1, BE()?.getBattleSpeed?.() || 1);
    }

    function _scaled(ms, min = 40) {
        return Math.max(min, Math.floor(ms / _speed()));
    }

    // 在指定元素上触发 CSS 动画 class（动画结束后自动移除）
    function pulse(el, className, duration = 600) {
        if (!el) return;
        el.classList.remove(className);
        void el.offsetWidth; // 强制重排
        el.classList.add(className);
        el.style.animationDuration = `${_scaled(duration)}ms`;
        setTimeout(() => {
            el.classList.remove(className);
            el.style.animationDuration = '';
        }, _scaled(duration));
    }

    // 生成飘字（伤害数字）
    function spawnFloatText(anchorEl, text, type = 'normal') {
        if (!anchorEl) return;
        const rect = anchorEl.getBoundingClientRect();
        const div = document.createElement('div');
        div.className = `damage-float ${type}`;
        div.textContent = text;
        // 随机偏移防止重叠
        const offsetX = -20 + Math.random() * 40;
        div.style.cssText = `left:${rect.left + rect.width / 2 + offsetX}px; top:${rect.top + 10}px; position:fixed;`;
        document.body.appendChild(div);
        const baseDuration = type === 'crit' ? 1400 : 1200;
        div.style.animationDuration = `${_scaled(baseDuration)}ms`;
        setTimeout(() => div.remove(), _scaled(baseDuration + 200));
    }

    // 生成元素粒子
    function spawnParticles(anchorEl, element, count = 6) {
        if (!anchorEl) return;
        const rect = anchorEl.getBoundingClientRect();
        for (let i = 0; i < count; i++) {
            const p = document.createElement('div');
            p.className = `particle ${element}`;
            const x = rect.left + Math.random() * rect.width;
            const y = rect.top + 10 + Math.random() * 20;
            const delay = (Math.random() * 0.3) / _speed();
            const size = 6 + Math.random() * 6;
            p.style.cssText = `left:${x}px; top:${y}px; position:fixed; width:${size}px; height:${size}px; animation-delay:${delay}s; animation-duration:${_scaled(800)}ms;`;
            document.body.appendChild(p);
            setTimeout(() => p.remove(), _scaled(1000) + delay * 1000);
        }
    }

    // 必杀技全屏闪光
    function triggerUltimate(element) {
        const overlay = document.createElement('div');
        overlay.className = `ultimate-flash-overlay ${element}-ult`;
        document.body.appendChild(overlay);
        const battleScreen = document.getElementById('battle-screen');
        if (battleScreen) pulse(battleScreen, 'screen-shaking', 500);
        overlay.style.animationDuration = `${_scaled(800)}ms`;
        setTimeout(() => overlay.remove(), _scaled(900));
    }

    // 处理战斗动画队列
    function playAnimation(anim, elementsMap) {
        const casterId = anim.casterId;
        const targetId = anim.targetId;
        const casterEl = elementsMap[casterId];
        const targetEl = elementsMap[targetId];

        switch (anim.type) {
            case 'normal_hit':
                // 攻击者冲锋
                if (casterEl) pulse(casterEl, anim.isEnemyAttack ? 'anim-lunge-enemy' : 'anim-lunge', 400);
                // 目标受击
                setTimeout(() => {
                    if (targetEl) pulse(targetEl, 'anim-hit', 350);
                    spawnFloatText(targetEl, `-${anim.damage}`, 'normal');
                    spawnParticles(targetEl, anim.element || 'wind', 4);
                }, _scaled(220));
                break;

            case 'crit_hit':
                if (casterEl) pulse(casterEl, anim.isEnemyAttack ? 'anim-lunge-enemy' : 'anim-lunge', 400);
                setTimeout(() => {
                    if (targetEl) pulse(targetEl, 'anim-crit', 500);
                    spawnFloatText(targetEl, `-${anim.damage}`, 'crit');
                    spawnParticles(targetEl, anim.element || 'wind', 10);
                }, _scaled(220));
                break;

            case 'heal':
                if (targetEl) pulse(targetEl, 'anim-fade-in', 300);
                spawnFloatText(targetEl, `+${anim.amount}`, 'heal');
                spawnParticles(targetEl, 'heal', 6);
                break;

            case 'status_apply': {
                const statusCfg = window.GG.StatusSystem?.getRegistry?.()?.[anim.statusId];
                const label = statusCfg?.label || anim.statusId || '状态';
                spawnFloatText(targetEl, `${statusCfg?.icon || '✨'} ${label}`, 'status');
                break;
            }

            case 'miss':
                spawnFloatText(targetEl, 'MISS', 'miss');
                break;
        }
    }

    // 播放一系列动画（按顺序带延迟）
    function playAnimationSequence(animations, elementsMap, onComplete) {
        let delay = 0;
        animations.forEach((anim, i) => {
            setTimeout(() => {
                // 必杀技全屏特效（在所有单次动画之前）
                if (anim.type === 'crit_hit' && i === 0) {
                    // 技能类型通过技能数据获取
                }
                playAnimation(anim, elementsMap);
                if (i === animations.length - 1) {
                    setTimeout(() => onComplete?.(), _scaled(600));
                }
            }, delay);
            delay += _scaled(anim.type === 'crit_hit' ? 250 : 200);
        });
        if (!animations.length) onComplete?.();
    }

    return { spawnFloatText, spawnParticles, triggerUltimate, pulse, playAnimation, playAnimationSequence };
})();
