// 默认战斗效果注册（命座通用 + 五星被动/C6）
window.GG = window.GG || {};
window.GG.registerDefaultCombatEffects = (function () {
    const CES = () => window.GG.CombatEffectSystem;
    const SS = () => window.GG.StatusSystem;
    const CS = () => window.GG.CharacterStats;

    let _registered = false;

    function _alive(units) {
        return (units || []).filter(u => u && u.currentHp > 0);
    }

    function _abyssEffects(type) {
        if (!window.GG.AbyssSystem?.getRogueEffects) return [];
        return window.GG.AbyssSystem.getRogueEffects().filter(e => !type || e.type === type);
    }

    function register() {
        if (_registered) return;
        _registered = true;

        // ===== 深渊肉鸽：直接伤害倍率修正 =====
        CES().register('before_damage_calc', {
            id: 'abyss_rogue_damage_modifiers',
            priority: 80,
            predicate: ({ target }) => !!target,
            handler: (ctx) => {
                const buckets = {
                    statusDamage: 0,
                    skillTypeDamage: 0,
                    skillTypeStatusDamage: 0,
                };
                const takenBuckets = {
                    damageTaken: 0,
                    statusDamageTaken: 0,
                };
                const isAllyAttack = !!ctx.caster?.isAlly;
                const isAllyTakingDamage = !!ctx.target?.isAlly;
                _abyssEffects().forEach(effect => {
                    const v = Number(effect.value) || 0;
                    if (isAllyAttack && effect.type === 'damageVsStatus' && SS().hasStatus(ctx.target, effect.statusId)) buckets.statusDamage += v;
                    if (isAllyAttack && effect.type === 'skillTypeDamage' && ctx.skillData?.type === effect.skillType) buckets.skillTypeDamage += v;
                    if (isAllyAttack && effect.type === 'skillTypeDamageVsStatus' && ctx.skillData?.type === effect.skillType && SS().hasStatus(ctx.target, effect.statusId)) buckets.skillTypeStatusDamage += v;
                    if (isAllyTakingDamage && effect.type === 'damageTakenMult') takenBuckets.damageTaken += v;
                    if (isAllyTakingDamage && effect.type === 'damageTakenWhileStatus' && SS().hasStatus(ctx.target, effect.statusId)) takenBuckets.statusDamageTaken += v;
                });
                const outgoingMult = Object.values(buckets).reduce((mult, value) => value === 0 ? mult : mult * Math.max(0.1, 1 + value), 1);
                const takenMult = Object.values(takenBuckets).reduce((mult, value) => value === 0 ? mult : mult * Math.max(0.1, 1 + value), 1);
                const finalMult = outgoingMult * (isAllyTakingDamage ? Math.max(0.1, takenMult) : takenMult);
                if (finalMult !== 1) ctx.damageMultiplier = Number(ctx.damageMultiplier ?? 1) * finalMult;
            },
        });

        // ===== 深渊肉鸽：能量获得增幅 =====
        CES().register('before_energy_gain', {
            id: 'abyss_rogue_energy_gain',
            priority: 80,
            predicate: ({ caster }) => !!caster?.isAlly,
            handler: (ctx) => {
                const bonus = _abyssEffects('energyGainMult').reduce((sum, e) => sum + (Number(e.value) || 0), 0);
                if (bonus !== 0) ctx.energyGain = Math.floor((ctx.energyGain || 0) * Math.max(0, 1 + bonus));
            },
        });

        // ===== 深渊肉鸽：治疗增幅 =====
        CES().register('before_heal_calc', {
            id: 'abyss_rogue_heal_modifiers',
            priority: 80,
            predicate: ({ caster }) => !!caster?.isAlly,
            handler: (ctx) => {
                const bonus = _abyssEffects('healMult').reduce((sum, e) => sum + (Number(e.value) || 0), 0);
                if (bonus !== 0) ctx.healMultiplier = Number(ctx.healMultiplier ?? 1) * Math.max(0, 1 + bonus);
            },
        });

        // ===== 深渊肉鸽：伤害后状态、追加伤害、命中能量 =====
        CES().register('after_damage', {
            id: 'abyss_rogue_after_damage',
            priority: 180,
            predicate: ({ caster, target, finalDamage }) => !!caster?.isAlly && !!target && finalDamage > 0,
            handler: (ctx) => {
                const skillElement = ctx.skillData?.element || ctx.effect?.element || ctx.caster?.element;
                _abyssEffects().forEach(effect => {
                    if (effect.type === 'applyStatusAfterDamage') {
                        if (effect.element && effect.element !== skillElement) return;
                        if (Math.random() < (effect.chance ?? 1)) {
                            SS().applyStatus(ctx.target, effect.statusId, effect.duration || 1, effect.value ?? null);
                            ctx.log?.push({ type: 'status', unit: ctx.target.name, statusId: effect.statusId, duration: effect.duration || 1 });
                            ctx.animations?.push({ type: 'status_apply', targetId: ctx.target.id, statusId: effect.statusId });
                        }
                    }

                    if (effect.type === 'energyOnHitStatus' && SS().hasStatus(ctx.target, effect.statusId)) {
                        ctx.caster.energy = Math.min(100, (ctx.caster.energy || 0) + (Number(effect.value) || 0));
                    }

                    if (effect.type === 'extraDamageVsStatus' && SS().hasStatus(ctx.target, effect.statusId) && ctx.target.currentHp > 0) {
                        const flag = `_abyssExtra_${effect.rewardInstanceId || effect.rewardId}_${ctx.skillId}_${ctx.target.id}`;
                        if (ctx.caster[flag]) return;
                        ctx.caster[flag] = true;
                        setTimeout(() => { if (ctx.caster) delete ctx.caster[flag]; }, 0);
                        const tMods = SS().getStatModifiers(ctx.target);
                        if (tMods.damageReduction >= 1 && SS().hasStatus(ctx.target, 'invincible')) return;
                        const calc = CS().calcDamage({
                            atk: ctx.caster.stats.atk,
                            multiplier: Number(effect.multiplier) || 0.3,
                            def: effect.trueDamage ? 0 : Math.floor(ctx.target.stats.def * tMods.defMult),
                            cri: 0,
                            criDmg: 1,
                            attackerElement: effect.element || ctx.caster.element,
                            defenderElement: ctx.target.element,
                        });
                        let extraDmg = effect.trueDamage
                            ? Math.max(0, Math.floor(ctx.caster.stats.atk * (Number(effect.multiplier) || 0.3)))
                            : calc.damage;
                        const minExtraDmgAfterReduction = extraDmg > 0 ? Math.max(1, Math.floor(extraDmg * 0.1)) : 0;
                        const shieldStatus = ctx.target.statuses?.find(s => s.id === 'shield');
                        if (shieldStatus) extraDmg = SS().getRegistry()['shield'].absorb(shieldStatus, extraDmg);
                        extraDmg = Math.max(minExtraDmgAfterReduction, Math.floor(extraDmg * Math.max(0.1, 1 - Math.max(0, tMods.damageReduction || 0))));
                        if (extraDmg <= 0) return;
                        ctx.target.currentHp = Math.max(0, ctx.target.currentHp - extraDmg);
                        ctx.log?.push({ type: 'damage', attacker: ctx.caster.name, targetName: ctx.target.name, skillName: effect.rewardName || '深渊回响', damage: extraDmg, isCrit: false, elementMult: calc.elementMult });
                        ctx.animations?.push({ type: 'normal_hit', casterId: ctx.caster.id, targetId: ctx.target.id, damage: extraDmg, isCrit: false, element: effect.element || ctx.caster.element });
                    }
                });
            },
        });

        // ===== 深渊肉鸽：治疗后附加状态 =====
        CES().register('after_heal', {
            id: 'abyss_rogue_after_heal',
            priority: 180,
            predicate: ({ caster, target, healAmount }) => !!caster?.isAlly && !!target && healAmount > 0,
            handler: (ctx) => {
                _abyssEffects('statusAfterHeal').forEach(effect => {
                    SS().applyStatus(ctx.target, effect.statusId, effect.duration || 1, effect.value ?? null);
                    ctx.log?.push({ type: 'status', unit: ctx.target.name, statusId: effect.statusId, duration: effect.duration || 1 });
                    ctx.animations?.push({ type: 'status_apply', targetId: ctx.target.id, statusId: effect.statusId });
                });
            },
        });

        // ===== 通用命座 C1/C3/C5：按技能类型增伤 =====
        CES().register('before_damage_calc', {
            id: 'constellation_damage_bonus',
            priority: 100,
            predicate: ({ caster, skillData }) => !!caster?.isAlly && !!skillData,
            handler: (ctx) => {
                const bonuses = CES().getConstellationBonuses(ctx.caster);
                const type = ctx.skillData?.type;
                let bonus = 0;
                if (type === 'normal') bonus = bonuses.normalDmgBonus || 0;
                else if (type === 'skill') bonus = bonuses.skillDmgBonus || 0;
                else if (type === 'ultimate') bonus = bonuses.ultDmgBonus || 0;

                const base = Number(ctx.damageMultiplier ?? 1);
                ctx.damageMultiplier = base * (1 + bonus);
            },
        });

        // ===== 通用命座 C2：战技冷却缩短（最低 1） =====
        CES().register('before_set_cooldown', {
            id: 'constellation_skill_cd_reduce',
            priority: 100,
            predicate: ({ caster, skillData }) => !!caster?.isAlly && skillData?.type === 'skill',
            handler: (ctx) => {
                const bonuses = CES().getConstellationBonuses(ctx.caster);
                const reduce = bonuses.skillCdReduce || 0;
                const baseCd = Number(ctx.cooldown || 0);
                ctx.cooldown = Math.max(1, baseCd - reduce);
            },
        });

        // ===== 五星被动：卡尔迪（攻击燃烧目标 -> 伤害加深乘区） =====
        CES().register('before_damage_calc', {
            id: 'passive_kaldi_burn_damage_deepen',
            priority: 220,
            predicate: ({ caster, target }) => !!caster?.isAlly && caster.passiveId === 'kaldi_passive' && !!target,
            handler: (ctx) => {
                if (!SS().hasStatus(ctx.target, 'burn')) return;
                ctx.damageDeepenBonus = Number(ctx.damageDeepenBonus || 0) + 0.2;
            },
        });

        // ===== 通用伤害加深乘区：所有 damageDeepenBonus 加算后统一乘算 =====
        CES().register('before_damage_calc', {
            id: 'damage_deepen_bucket_resolver',
            priority: 900,
            predicate: ({ damageDeepenBonus }) => Number(damageDeepenBonus || 0) !== 0,
            handler: (ctx) => {
                const deepen = Number(ctx.damageDeepenBonus || 0);
                ctx.damageMultiplier = Number(ctx.damageMultiplier ?? 1) * Math.max(0.1, 1 + deepen);
            },
        });

        // ===== 五星被动：艾拉（每回合开始治疗最低血队友） =====
        CES().register('unit_turn_start', {
            id: 'passive_ayla_turn_heal',
            priority: 200,
            predicate: ({ unit }) => !!unit?.isAlly && unit.passiveId === 'ayla_passive' && unit.currentHp > 0,
            handler: (ctx) => {
                const allies = _alive(ctx.allies);
                if (!allies.length) return;
                const target = allies.reduce((a, b) => (a.currentHp / a.maxHp < b.currentHp / b.maxHp ? a : b));
                const heal = Math.max(1, Math.floor((ctx.unit.stats?.atk || 0) * 0.4));
                const before = target.currentHp;
                target.currentHp = Math.min(target.maxHp, target.currentHp + heal);
                const actual = target.currentHp - before;
                if (actual > 0) {
                    ctx.log?.push({ type: 'heal', unit: target.name, amount: actual, skillName: '艾拉·霜语祷告' });
                    CES().emit('after_heal', {
                        caster: ctx.unit,
                        target,
                        skillId: 'ayla_passive',
                        skillData: { id: 'ayla_passive', name: '艾拉·霜语祷告', type: 'passive' },
                        effect: { type: 'heal', source: 'passive' },
                        effectIndex: 0,
                        healAmount: actual,
                        allies: ctx.allies,
                        enemies: ctx.enemies,
                        log: ctx.log,
                        animations: ctx.animations,
                    });
                }
            },
        });

        // ===== 五星 C6：卡尔迪（终结技命中燃烧目标追加火伤） =====
        CES().register('after_damage', {
            id: 'c6_kaldi_ult_bonus_vs_burn',
            priority: 300,
            predicate: ({ caster, target, skillData, finalDamage }) => {
                if (!caster?.isAlly || caster.id !== 'kaldi') return false;
                if (!skillData || skillData.type !== 'ultimate') return false;
                if (!target || target.currentHp <= 0 || finalDamage <= 0) return false;
                if (!CES().hasC6Type(caster, 'on_ult_hit_burned')) return false;
                return SS().hasStatus(target, 'burn');
            },
            handler: (ctx) => {
                const bonus = CES().getC6Value(ctx.caster, 'c6_bonus', 0.8);
                const tMods = SS().getStatModifiers(ctx.target);
                if (tMods.damageReduction >= 1 && SS().hasStatus(ctx.target, 'invincible')) return;

                const calc = CS().calcDamage({
                    atk: ctx.caster.stats.atk,
                    multiplier: bonus,
                    def: Math.floor(ctx.target.stats.def * tMods.defMult),
                    cri: 0,
                    criDmg: 1,
                    attackerElement: 'fire',
                    defenderElement: ctx.target.element,
                });

                let extraDmg = calc.damage;
                const minExtraDmgAfterReduction = extraDmg > 0 ? Math.max(1, Math.floor(extraDmg * 0.1)) : 0;
                const shieldStatus = ctx.target.statuses?.find(s => s.id === 'shield');
                if (shieldStatus) {
                    const shieldCfg = SS().getRegistry()['shield'];
                    extraDmg = shieldCfg.absorb(shieldStatus, extraDmg);
                }
                extraDmg = Math.max(minExtraDmgAfterReduction, Math.floor(extraDmg * Math.max(0.1, 1 - Math.max(0, tMods.damageReduction || 0))));
                extraDmg = Math.max(0, extraDmg);
                if (extraDmg <= 0) return;

                ctx.target.currentHp = Math.max(0, Math.floor(ctx.target.currentHp - extraDmg));
                ctx.log?.push({
                    type: 'damage',
                    attacker: ctx.caster.name,
                    targetName: ctx.target.name,
                    skillName: '不灭炎心',
                    damage: extraDmg,
                    isCrit: false,
                    elementMult: calc.elementMult,
                });
                ctx.animations?.push({
                    type: 'normal_hit',
                    casterId: ctx.caster.id,
                    targetId: ctx.target.id,
                    damage: extraDmg,
                    isCrit: false,
                    element: 'fire',
                });
            },
        });

        // ===== 五星 C6：艾拉（治愈行动后全队再生1回合） =====
        CES().register('after_skill_execute', {
            id: 'c6_ayla_heal_spreads_regen',
            priority: 300,
            predicate: ({ caster, result }) => {
                if (!caster?.isAlly || caster.id !== 'ayla') return false;
                if (!result?.hadHeal) return false;
                return CES().hasC6Type(caster, 'heal_spreads_regen');
            },
            handler: (ctx) => {
                _alive(ctx.allies).forEach(u => {
                    SS().applyStatus(u, 'regen', 1);
                    ctx.log?.push({ type: 'status', unit: u.name, statusId: 'regen', duration: 1 });
                });
            },
        });
    }

    return register;
})();
