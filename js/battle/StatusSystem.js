// 状态效果注册系统
// 新增状态直接调用 StatusSystem.registerStatus() 即可，无需修改战斗引擎
window.GG = window.GG || {};
window.GG.StatusSystem = (function () {
    const registry = {};

    // 注册一种状态效果
    // handlers: { onApply, onTurnStart, onTurnEnd, onRemove, modifyDamage, modifyStats }
    function registerStatus(id, config) {
        registry[id] = config;
    }

    // 将状态施加给目标战斗单位（BattleUnit 实例）
    function applyStatus(unit, statusId, duration, value = null) {
        const config = registry[statusId];
        if (!config) { console.warn(`[StatusSystem] 未知状态: ${statusId}`); return; }

        // 防止同类叠加（除非 config.stackable = true）
        const existing = unit.statuses.find(s => s.id === statusId);
        if (existing && !config.stackable) {
            existing.duration = Math.max(existing.duration, duration); // 刷新持续时间
            return;
        }

        const statusInst = { id: statusId, duration, value, stacks: 1 };
        unit.statuses.push(statusInst);
        config.onApply?.(unit, statusInst);
        window.GG.EventBus.emit('status:applied', unit, statusId);
    }

    // 回合开始时，触发所有状态的 onTurnStart
    function processTurnStart(unit, log) {
        unit.statuses.forEach(s => {
            const cfg = registry[s.id];
            cfg?.onTurnStart?.(unit, s, log);
        });
    }

    // 回合结束时，触发 onTurnEnd 并减少持续时间
    function processTurnEnd(unit, log) {
        unit.statuses.forEach(s => {
            const cfg = registry[s.id];
            cfg?.onTurnEnd?.(unit, s, log);
            s.duration--;
        });
        // 移除已过期的状态
        const removed = unit.statuses.filter(s => s.duration <= 0);
        removed.forEach(s => {
            registry[s.id]?.onRemove?.(unit, s, log);
            window.GG.EventBus.emit('status:removed', unit, s.id);
        });
        unit.statuses = unit.statuses.filter(s => s.duration > 0);
    }

    // 检查单位是否有某状态
    function hasStatus(unit, statusId) {
        return unit.statuses.some(s => s.id === statusId);
    }

    // 聚合所有状态对属性的修正（返回修正对象）
    function getStatModifiers(unit) {
        const mods = { atkMult: 1, defMult: 1, spdMult: 1, damageReduction: 0 };
        unit.statuses.forEach(s => {
            const cfg = registry[s.id];
            cfg?.modifyStats?.(unit, s, mods);
        });
        return mods;
    }

    // 检查单位是否可以行动（冰冻/眩晕/无敌时跳过）
    function canAct(unit) {
        if (hasStatus(unit, 'freeze') || hasStatus(unit, 'stun')) return false;
        return true;
    }

    // 获取所有已注册的状态定义
    function getRegistry() { return registry; }

    // ===== 注册核心状态效果 =====
    const EB = () => window.GG.EventBus;

    // 🔥 燃烧
    registerStatus('burn', {
        label: '燃烧', icon: '🔥', colorClass: 'status-fire',
        description: '每回合开始受到火属性伤害',
        onTurnStart(unit, s, log) {
            const dmg = Math.max(1, Math.floor(unit.baseAtk * 0.18));
            unit.currentHp = Math.max(0, unit.currentHp - dmg);
            log?.push({ type: 'status_dmg', unit: unit.name, statusId: 'burn', damage: dmg });
            EB().emit('status:damage', unit, 'burn', dmg);
        },
    });

    // ❄️ 冰冻（跳过行动）
    registerStatus('freeze', {
        label: '冰冻', icon: '❄️', colorClass: 'status-ice',
        description: '无法行动',
        onApply(unit) { unit._frozen = true; },
        onRemove(unit) { unit._frozen = false; },
    });

    // 🌀 眩晕（跳过行动 + DEF-30%）
    registerStatus('stun', {
        label: '眩晕', icon: '💫', colorClass: 'status-stun',
        description: '无法行动，防御-30%',
        modifyStats(unit, s, mods) { mods.defMult *= 0.7; },
    });

    // ☠️ 中毒（叠加层数，每层每回合掉HP%）
    registerStatus('poison', {
        label: '中毒', icon: '☠️', colorClass: 'status-poison',
        stackable: true,
        description: '每回合损失最大HP 5%（可叠加）',
        onTurnStart(unit, s, log) {
            const dmg = Math.max(1, Math.floor(unit.maxHp * 0.05));
            unit.currentHp = Math.max(0, unit.currentHp - dmg);
            log?.push({ type: 'status_dmg', unit: unit.name, statusId: 'poison', damage: dmg });
            EB().emit('status:damage', unit, 'poison', dmg);
        },
    });

    // ⚡ 感电（跳过行动，下一个行动的单位也受到伤害）
    registerStatus('electrify', {
        label: '感电', icon: '⚡', colorClass: 'status-thunder',
        description: '无法行动',
        onApply(unit) { unit._electrified = true; },
        onRemove(unit) { unit._electrified = false; },
    });

    // 💚 再生
    registerStatus('regen', {
        label: '再生', icon: '💚', colorClass: 'status-heal',
        description: '每回合恢复最大HP 8%',
        onTurnStart(unit, s, log) {
            const heal = Math.max(1, Math.floor(unit.maxHp * 0.08));
            unit.currentHp = Math.min(unit.maxHp, unit.currentHp + heal);
            log?.push({ type: 'heal', unit: unit.name, amount: heal, source: 'regen' });
            EB().emit('status:heal', unit, 'regen', heal);
        },
    });

    // ⬆️ 攻强
    registerStatus('atk_up', {
        label: '攻强', icon: '⬆️', colorClass: 'status-buff',
        description: '攻击力提升',
        modifyStats(unit, s, mods) { mods.atkMult *= (1 + (s.value || 0.3)); },
    });

    // ⬆️ 防强
    registerStatus('def_up', {
        label: '防强', icon: '🛡️', colorClass: 'status-buff',
        description: '防御力提升',
        modifyStats(unit, s, mods) { mods.defMult *= (1 + (s.value || 0.3)); },
    });

    // ⬇️ 速降
    registerStatus('spd_down', {
        label: '减速', icon: '🐢', colorClass: 'status-debuff',
        description: '速度降低',
        modifyStats(unit, s, mods) { mods.spdMult *= (1 - (s.value || 0.3)); },
    });

    // 🛡️ 护盾（吸收伤害）
    registerStatus('shield', {
        label: '护盾', icon: '🛡️', colorClass: 'status-shield',
        description: '吸收一定量伤害',
        onApply(unit, s) {
            // value 为比例：0.3 = 吸收 30% 最大HP 的伤害
            s.shieldHp = Math.floor(unit.maxHp * (s.value || 0.3));
        },
        // 由战斗引擎在受伤前调用 absorb
        absorb(s, damage) {
            if (!s.shieldHp) return damage;
            const absorbed = Math.min(s.shieldHp, damage);
            s.shieldHp -= absorbed;
            if (s.shieldHp <= 0) s.duration = 0; // 护盾耗尽后失效
            return damage - absorbed;
        },
    });

    // 🌟 无敌（免疫所有伤害）
    registerStatus('invincible', {
        label: '无敌', icon: '🌟', colorClass: 'status-buff',
        description: '免疫所有伤害',
        modifyStats(unit, s, mods) { mods.damageReduction = 1; },
    });

    // 🎯 嘲讽
    registerStatus('taunt', {
        label: '嘲讽', icon: '🎯', colorClass: 'status-buff',
        description: '强制所有敌方攻击此目标',
    });

    // ===== 扩展预留 ==========
    // 新状态效果：调用 registerStatus('id', { label, icon, ... handlers }) 即可

    return {
        registerStatus,
        applyStatus,
        processTurnStart,
        processTurnEnd,
        hasStatus,
        getStatModifiers,
        canAct,
        getRegistry,
    };
})();
