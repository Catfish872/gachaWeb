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

    function register() {
        if (_registered) return;
        _registered = true;

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

        // ===== 五星被动：卡尔迪（受伤且自身燃烧 -> 攻强） =====
        CES().register('after_damage', {
            id: 'passive_kaldi_burned_atk_up',
            priority: 200,
            predicate: ({ target, finalDamage }) => !!target?.isAlly && target.passiveId === 'kaldi_passive' && finalDamage > 0,
            handler: (ctx) => {
                if (!SS().hasStatus(ctx.target, 'burn')) return;
                SS().applyStatus(ctx.target, 'atk_up', 2, 0.2);
                ctx.log?.push({ type: 'status', unit: ctx.target.name, statusId: 'atk_up', duration: 2 });
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
                if (tMods.damageReduction >= 1) return;

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
                const shieldStatus = ctx.target.statuses?.find(s => s.id === 'shield');
                if (shieldStatus) {
                    const shieldCfg = SS().getRegistry()['shield'];
                    extraDmg = shieldCfg.absorb(shieldStatus, extraDmg);
                }
                extraDmg = Math.floor(extraDmg * (1 - tMods.damageReduction));
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
