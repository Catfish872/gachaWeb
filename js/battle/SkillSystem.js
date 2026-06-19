// 技能执行系统 — 数据驱动 + 注册式扩展
window.GG = window.GG || {};
window.GG.SkillSystem = (function () {
    const SD = () => window.GG.SkillData;
    const SS = () => window.GG.StatusSystem;
    const CS = () => window.GG.CharacterStats;
    const EB = () => window.GG.EventBus;
    const CES = () => window.GG.CombatEffectSystem;

    // 自定义效果处理器（高级技能可在此注册特殊逻辑）
    const customHandlers = {};
    function registerSkill(skillId, handler) {
        customHandlers[skillId] = handler;
    }

    // 根据 target 字段解析目标列表
    function resolveTargets(targetType, caster, allies, enemies) {
        switch (targetType) {
            case 'single':
            case 'single_enemy': return [enemies.filter(e => e.currentHp > 0)[0]].filter(Boolean);
            case 'all':
            case 'all_enemies': return enemies.filter(e => e.currentHp > 0);
            case 'self': return [caster];
            case 'all_allies': return allies.filter(a => a.currentHp > 0);
            case 'lowest_hp_ally': {
                const alive = allies.filter(a => a.currentHp > 0);
                if (!alive.length) return [];
                return [alive.reduce((a, b) => (a.currentHp / a.maxHp < b.currentHp / b.maxHp ? a : b))];
            }
            case 'random': {
                const alive = enemies.filter(e => e.currentHp > 0);
                return alive.length ? [alive[Math.floor(Math.random() * alive.length)]] : [];
            }
            case 'random_enemy': {
                const alive = enemies.filter(e => e.currentHp > 0);
                return alive.length ? [alive[Math.floor(Math.random() * alive.length)]] : [];
            }
            case 'chain3': { // 连锁攻击，最多3个目标
                const alive = enemies.filter(e => e.currentHp > 0);
                return alive.slice(0, 3);
            }
            default: return [];
        }
    }

    // 执行一次技能
    // 返回 { log: [], animations: [] }
    function executeSkill(skillId, caster, allies, enemies) {
        const skillData = SD()[skillId];
        if (!skillData) return { log: [`未知技能: ${skillId}`], animations: [] };

        const log = [];
        const animations = [];

        // 如果有自定义处理器，优先使用
        if (customHandlers[skillId]) {
            return customHandlers[skillId](skillData, caster, allies, enemies);
        }

        const runEffectHook = (trigger, ctx) => {
            const sys = CES();
            if (!sys?.emit) return ctx;
            return sys.emit(trigger, ctx) || ctx;
        };

        // 获取施法者的属性修正
        const mods = SS().getStatModifiers(caster);
        const effectiveAtk = Math.floor(caster.stats.atk * mods.atkMult);

        // 消耗/获得能量（技能类型）
        if (skillData.type === 'ultimate') {
            caster.energy = 0;
        } else {
            caster.energy = Math.min(100, caster.energy + (skillData.energyGain || 15));
        }

        // 处理技能冷却
        if (skillData.cooldown > 0) {
            caster.cooldowns = caster.cooldowns || {};
            const cdCtx = runEffectHook('before_set_cooldown', {
                caster,
                skillId,
                skillData,
                cooldown: skillData.cooldown,
                allies,
                enemies,
                log,
                animations,
            });
            caster.cooldowns[skillId] = Math.max(1, Math.floor(cdCtx.cooldown ?? skillData.cooldown));
        }

        let hadHeal = false;

        // 逐条执行效果
        skillData.effects.forEach((effect, effectIdx) => {
            const targets = resolveTargets(effect.target, caster, allies, enemies);
            const isHeal = effect.type === 'heal';
            const isDamage = effect.type === 'damage';
            const isStatus = effect.type === 'status';

            if (isDamage) {
                let chainMult = 1.0;
                targets.forEach((target, ti) => {
                    if (target.currentHp <= 0) return;

                    // 无敌检查
                    const targetMods = SS().getStatModifiers(target);
                    if (targetMods.damageReduction >= 1) {
                        log.push({ type: 'miss', attacker: caster.name, targetName: target.name, reason: '无敌' });
                        animations.push({ type: 'miss', targetId: target.id });
                        return;
                    }

                    // 计算伤害
                    const dmgCtx = runEffectHook('before_damage_calc', {
                        caster,
                        target,
                        skillId,
                        skillData,
                        effect,
                        effectIndex: effectIdx,
                        targetIndex: ti,
                        damageMultiplier: (effect.multiplier || 1.0) * chainMult,
                        allies,
                        enemies,
                        log,
                        animations,
                    });

                    const skillMult = dmgCtx.damageMultiplier ?? ((effect.multiplier || 1.0) * chainMult);
                    const result = CS().calcDamage({
                        atk: effectiveAtk,
                        multiplier: skillMult,
                        def: Math.floor(target.stats.def * targetMods.defMult),
                        cri: caster.stats.cri,
                        criDmg: caster.stats.criDmg,
                        defPierce: effect.defPierce || 0,
                        attackerElement: skillData.element || caster.element,
                        defenderElement: target.element,
                    });

                    // 护盾吸收
                    let finalDmg = result.damage;
                    const shieldStatus = target.statuses.find(s => s.id === 'shield');
                    if (shieldStatus) {
                        const shieldCfg = SS().getRegistry()['shield'];
                        finalDmg = shieldCfg.absorb(shieldStatus, finalDmg);
                    }
                    // 其他减伤
                    finalDmg = Math.floor(finalDmg * (1 - targetMods.damageReduction));
                    // 确保伤害非负
                    finalDmg = Math.max(0, finalDmg);

                    // 绝对取整并确保血量非负
                    target.currentHp = Math.max(0, Math.floor(target.currentHp - finalDmg));

                    log.push({
                        type: 'damage',
                        attacker: caster.name,
                        targetName: target.name,
                        skillName: skillData.name,
                        damage: finalDmg,
                        isCrit: result.isCrit,
                        elementMult: result.elementMult,
                    });
                    animations.push({
                        type: result.isCrit ? 'crit_hit' : 'normal_hit',
                        casterId: caster.id,
                        targetId: target.id,
                        damage: finalDmg,
                        isCrit: result.isCrit,
                        element: skillData.element || caster.element,
                    });

                    runEffectHook('after_damage', {
                        caster,
                        target,
                        skillId,
                        skillData,
                        effect,
                        effectIndex: effectIdx,
                        targetIndex: ti,
                        finalDamage: finalDmg,
                        calcResult: result,
                        allies,
                        enemies,
                        log,
                        animations,
                    });

                    // 暴击能量加成（格斯被动：暴击+5能量）
                    if (result.isCrit && caster.passiveId === 'gus_passive') {
                        caster.energy = Math.min(100, caster.energy + 5);
                    }

                    // 连锁伤害衰减
                    if (effect.chainDecay) chainMult = Math.max(0.3, chainMult - effect.chainDecay);
                });

            } else if (isHeal) {
                targets.forEach(target => {
                    if (target.currentHp <= 0) return;
                    let healAmt = Math.floor(CS().calcHeal({ atk: effectiveAtk, multiplier: effect.multiplier || 1.0 }));
                    healAmt = Math.max(0, healAmt); // 确保治疗量非负
                    target.currentHp = Math.min(target.maxHp, target.currentHp + healAmt);
                    log.push({ type: 'heal', unit: target.name, amount: healAmt, skillName: skillData.name });
                    animations.push({ type: 'heal', targetId: target.id, amount: healAmt });
                    hadHeal = true;

                    runEffectHook('after_heal', {
                        caster,
                        target,
                        skillId,
                        skillData,
                        effect,
                        effectIndex: effectIdx,
                        healAmount: healAmt,
                        allies,
                        enemies,
                        log,
                        animations,
                    });

                    // 夏娜被动：治愈后自身回复治愈量15%
                    if (caster.passiveId === 'shana_passive' && target !== caster) {
                        const selfHeal = Math.floor(healAmt * 0.15);
                        caster.currentHp = Math.min(caster.maxHp, caster.currentHp + selfHeal);
                    }
                });

            } else if (isStatus) {
                const statusTargets = resolveTargets(effect.target, caster, allies, enemies);
                statusTargets.forEach(target => {
                    if (target.currentHp <= 0) return;
                    const roll = Math.random();
                    if (roll < (effect.chance || 1.0)) {
                        SS().applyStatus(target, effect.statusId, effect.duration, effect.value ?? null);
                        log.push({ type: 'status', unit: target.name, statusId: effect.statusId, duration: effect.duration });
                        animations.push({ type: 'status_apply', targetId: target.id, statusId: effect.statusId });
                    }
                });
            }
        });

        runEffectHook('after_skill_execute', {
            caster,
            skillId,
            skillData,
            allies,
            enemies,
            log,
            animations,
            result: { hadHeal }
        });

        return { log, animations, hadHeal };
    }

    // 检查技能是否可用
    function isSkillAvailable(skillId, caster) {
        const data = SD()[skillId];
        if (!data) return false;
        if (data.type === 'ultimate') return caster.energy >= 100;
        if (data.type === 'skill') {
            const cd = caster.cooldowns?.[skillId] || 0;
            return cd <= 0;
        }
        return true; // 普攻永远可用
    }

    return {
        registerSkill,
        executeSkill,
        resolveTargets,
        isSkillAvailable,
    };
})();
