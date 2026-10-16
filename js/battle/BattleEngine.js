// 战斗引擎核心 — 回合制战斗逻辑
window.GG = window.GG || {};
window.GG.BattleEngine = (function () {
    const SS = () => window.GG.StatusSystem;
    const Skill = () => window.GG.SkillSystem;
    const CS = () => window.GG.CharacterStats;
    const CD = () => window.GG.CharacterData;
    const ED = () => window.GG.EnemyData;
    const ESD = () => window.GG.EnemySkillData;
    const EB = () => window.GG.EventBus;
    const CES = () => window.GG.CombatEffectSystem;

    let _state = null;
    let _autoBattleEnabled = false; // 跨战斗继承自动战斗偏好
    let _battleSpeed = 1;           // 跨战斗继承速度倍率（1x/2x/4x）

    // ===== 创建我方战斗单位 =====
    function createAllyUnit(charId, saveData) {
        const data = CD()[charId];
        if (!data) return null;
        const { level = 1, awakening = 0 } = saveData || {};
        const stats = CS().computeStats(charId, level, awakening);
        return {
            id: charId, name: data.name, element: data.element, role: data.role,
            isAlly: true,
            stats, maxHp: stats.maxHp, currentHp: stats.maxHp,
            skills: data.skills, passiveId: data.passiveId,
            energy: 0, cooldowns: {},
            statuses: [],
            baseAtk: stats.atk,
            rarity: data.rarity,
            image: data.image,
        };
    }

    // ===== 创建敌方战斗单位 =====
    // scaleMult 可以是普通的数值，也可以是深渊传来的精细化膨胀配置对象
    function createEnemyUnit(enemyId, scaleMult) {
        scaleMult = scaleMult || 1.0;
        let hpMod = scaleMult, atkMod = scaleMult, defMod = scaleMult, spdMod = 1.0;

        // 深渊模式传参：{ hpMod, atkMod, defMod, spdMod, scaleMult }
        if (typeof scaleMult === 'object') {
            hpMod = scaleMult.hpMod;
            atkMod = scaleMult.atkMod;
            defMod = scaleMult.defMod;
            spdMod = scaleMult.spdMod;
            scaleMult = scaleMult.scaleMult; // 用于其他综合计算
        }

        const data = ED()[enemyId];
        if (!data) return null;
        const bs = data.baseStats;
        const stats = {
            maxHp: Math.floor(bs.hp * hpMod),
            atk: Math.floor(bs.atk * atkMod),
            def: Math.floor(bs.def * defMod),
            spd: Math.floor(bs.spd * spdMod),
            cri: 0.10, criDmg: 1.5,
        };
        return {
            id: enemyId + '_' + Math.random().toString(36).slice(2),
            dataId: enemyId, name: data.name, element: data.element,
            isAlly: false, isBoss: data.isBoss || false,
            icon: data.icon,
            stats, maxHp: stats.maxHp, currentHp: stats.maxHp,
            skills: data.skills, aiPattern: data.aiPattern,
            phaseThreshold: data.phaseThreshold, phase2Skills: data.phase2Skills,
            energy: 0, cooldowns: {}, statuses: [],
            baseAtk: stats.atk,
            inPhase2: false,
            skillCooldowns: {},
        };
    }

    // ===== 构建行动顺序队列（按速度降序） =====
    function buildActionQueue(allies, enemies) {
        const all = [...allies, ...enemies].filter(u => u.currentHp > 0);
        return all.sort((a, b) => {
            const spdA = a.stats.spd * SS().getStatModifiers(a).spdMult;
            const spdB = b.stats.spd * SS().getStatModifiers(b).spdMult;
            if (spdB !== spdA) return spdB - spdA;
            return a.isAlly ? -1 : 1; // 速度相同时我方优先
        });
    }

    // ===== 敌人 AI 选技能 =====
    function selectEnemySkill(enemy) {
        const availableSkills = enemy.skills.filter(sid => (enemy.skillCooldowns[sid] || 0) <= 0);
        if (!availableSkills.length) return enemy.skills[0] || null;

        switch (enemy.aiPattern) {
            case 'aggressive': {
                const dmgSkills = availableSkills.filter(s => ESD()[s]?.effects?.some(e => e.type === 'damage'));
                return dmgSkills.length ? dmgSkills[0] : availableSkills[0];
            }
            case 'defensive': {
                const isLowHp = enemy.currentHp / enemy.maxHp < 0.5;
                if (isLowHp) {
                    const defSkill = availableSkills.find(s =>
                        ESD()[s]?.effects?.some(e => e.type === 'status' && ['shield', 'def_up'].includes(e.statusId)));
                    if (defSkill) return defSkill;
                }
                return availableSkills[Math.floor(Math.random() * availableSkills.length)];
            }
            case 'boss': {
                if (enemy.inPhase2 && enemy.phase2Skills?.length) {
                    const p2 = enemy.phase2Skills.filter(s => (enemy.skillCooldowns[s] || 0) <= 0);
                    if (p2.length) return p2[Math.floor(Math.random() * p2.length)];
                }
                return availableSkills[Math.floor(Math.random() * availableSkills.length)];
            }
            default:
                return availableSkills[Math.floor(Math.random() * availableSkills.length)];
        }
    }

    // ===== 执行敌方技能 =====
    // 注意：从敌方视角，"allies(我方)"是玩家队伍，"enemies(敌方)"是自己一方
    function executeEnemySkill(skillId, enemy, allies, enemies) {
        const skillData = ESD()[skillId] || { name: '攻击', effects: [{ type: 'damage', target: 'single', multiplier: 1.0 }] };
        const log = [];
        const animations = [];
        const mods = SS().getStatModifiers(enemy);
        const effectiveAtk = Math.floor(enemy.stats.atk * mods.atkMult);

        const runEffectHook = (trigger, ctx) => {
            const sys = CES();
            if (!sys?.emit) return ctx;
            return sys.emit(trigger, ctx) || ctx;
        };

        skillData.effects.forEach(effect => {
            const aliveAllies = allies.filter(a => a.currentHp > 0);   // 玩家方（攻击目标）
            const aliveEnemies = enemies.filter(e => e.currentHp > 0); // 敌方同伴（增益目标）
            const taunted = aliveAllies.find(a => SS().hasStatus(a, 'taunt'));

            let targets = [];
            // 从敌方视角解析目标语义
            switch (effect.target) {
                case 'self':
                    targets = [enemy]; break;
                case 'all_allies':
                    // 己方全体增益 → 所有存活敌人（含自身）
                    targets = aliveEnemies.length ? aliveEnemies : [enemy]; break;
                case 'single':
                case 'random':
                case 'random_enemy':
                case 'single_enemy':
                    // 攻击玩家单体，先检查嘲讽
                    targets = taunted ? [taunted]
                        : (aliveAllies.length ? [aliveAllies[Math.floor(Math.random() * aliveAllies.length)]] : []);
                    break;
                case 'all':
                case 'all_enemies':
                    // 攻击玩家全体 AOE
                    targets = taunted ? [taunted] : [...aliveAllies]; break;
                default:
                    targets = aliveAllies.length ? [aliveAllies[0]] : [];
            }

            if (effect.type === 'damage') {
                targets.forEach(target => {
                    if (target.currentHp <= 0) return;
                    const tMods = SS().getStatModifiers(target);
                    const isInvincible = tMods.damageReduction >= 1 && SS().hasStatus(target, 'invincible');
                    if (isInvincible) {
                        log.push({ type: 'miss', attacker: enemy.name, targetName: target.name, reason: '无敌' });
                        return;
                    }
                    const dmgCtx = runEffectHook('before_damage_calc', {
                        caster: enemy,
                        target,
                        skillId,
                        skillData,
                        effect,
                        damageMultiplier: effect.multiplier || 1.0,
                        allies: enemies,
                        enemies: allies,
                        log,
                        animations,
                    });

                    const calc = CS().calcDamage({
                        atk: effectiveAtk, multiplier: dmgCtx.damageMultiplier ?? (effect.multiplier || 1.0),
                        def: Math.floor(target.stats.def * tMods.defMult),
                        cri: enemy.stats.cri, criDmg: enemy.stats.criDmg,
                        attackerElement: effect.element || enemy.element,
                        defenderElement: target.element,
                    });
                    let finalDmg = calc.damage;
                    const minDamageAfterReduction = finalDmg > 0 ? Math.max(1, Math.floor(finalDmg * 0.1)) : 0;
                    const shieldStatus = target.statuses.find(s => s.id === 'shield');
                    if (shieldStatus) {
                        const shieldCfg = SS().getRegistry()['shield'];
                        finalDmg = shieldCfg.absorb(shieldStatus, finalDmg);
                    }
                    const damageReductionMult = Math.max(0.1, 1 - Math.max(0, tMods.damageReduction || 0));
                    finalDmg = Math.max(minDamageAfterReduction, Math.floor(finalDmg * damageReductionMult));
                    finalDmg = Math.max(0, finalDmg); // 确保伤害绝对非负

                    target.currentHp = Math.max(0, Math.floor(target.currentHp - finalDmg));
                    log.push({ type: 'damage', attacker: enemy.name, targetName: target.name, skillName: skillData.name, damage: finalDmg, isCrit: calc.isCrit, isEnemy: true, elementMult: calc.elementMult });
                    animations.push({ type: calc.isCrit ? 'crit_hit' : 'normal_hit', casterId: enemy.id, targetId: target.id, damage: finalDmg, isCrit: calc.isCrit, element: effect.element || enemy.element, isEnemyAttack: true });

                    runEffectHook('after_damage', {
                        caster: enemy,
                        target,
                        skillId,
                        skillData,
                        effect,
                        finalDamage: finalDmg,
                        calcResult: calc,
                        allies: enemies,
                        enemies: allies,
                        log,
                        animations,
                    });
                });

            } else if (effect.type === 'status') {
                targets.forEach(target => {
                    if (!target || target.currentHp <= 0) return;
                    if (Math.random() < (effect.chance || 1.0)) {
                        SS().applyStatus(target, effect.statusId, effect.duration, effect.value ?? null);
                        log.push({ type: 'status', unit: target.name, statusId: effect.statusId, duration: effect.duration });
                        animations.push({ type: 'status_apply', targetId: target.id, statusId: effect.statusId });
                    }
                });

            } else if (effect.type === 'heal') {
                targets.forEach(target => {
                    if (target.currentHp <= 0) return;
                    const heal = CS().calcHeal({ atk: effectiveAtk, multiplier: effect.multiplier || 1.0 });
                    target.currentHp = Math.min(target.maxHp, target.currentHp + heal);
                    log.push({ type: 'heal', unit: target.name, amount: heal });

                    runEffectHook('after_heal', {
                        caster: enemy,
                        target,
                        skillId,
                        skillData,
                        effect,
                        healAmount: heal,
                        allies: enemies,
                        enemies: allies,
                        log,
                        animations,
                    });
                });
            }
        });

        return { log, animations };
    }

    // ===== 执行敌方回合 =====
    function executeEnemyTurn(enemy) {
        if (!_state) return;
        if (enemy.currentHp <= 0) { advanceTurn(); return; }

        try {
            // BOSS 阶段二触发
            if (enemy.isBoss && !enemy.inPhase2 && enemy.currentHp / enemy.maxHp < (enemy.phaseThreshold || 0.5)) {
                enemy.inPhase2 = true;
                _state.log.push({ type: 'phase_change', unit: enemy.name });
                EB().emit('battle:boss_phase2', enemy);
            }

            // 控制效果检查（冻结/眩晕）
            if (!SS().canAct(enemy)) {
                _state.log.push({ type: 'skip', unit: enemy.name, reason: '控制效果' });
                EB().emit('battle:skip', enemy);
                advanceTurn();
                return;
            }

            const skillId = selectEnemySkill(enemy);
            if (!skillId) { advanceTurn(); return; }

            const result = executeEnemySkill(skillId, enemy, _state.allies, _state.enemies);
            _state.log.push(...result.log);

            // 设置敌方本次使用的技能的冷却初始值
            const eSkill = ESD()[skillId];
            if (eSkill?.cooldown) enemy.skillCooldowns[skillId] = eSkill.cooldown;

            EB().emit('battle:action', enemy, skillId, result);
            CES()?.emit?.('after_action', {
                actor: enemy,
                skillId,
                result,
                state: _state,
                allies: _state.enemies,
                enemies: _state.allies,
            });
            advanceTurn();

        } catch (err) {
            console.error('[BattleEngine] executeEnemyTurn 出错，强制推进回合:', err);
            advanceTurn(); // 防止永久卡死
        }
    }

    function _getAbyssEffects(type) {
        if (!window.GG.AbyssSystem?.getRogueEffects) return [];
        return window.GG.AbyssSystem.getRogueEffects().filter(e => !type || e.type === type);
    }

    function _applyAbyssStatRewards(allies, abyssState) {
        const effects = _getAbyssEffects('stat');
        if (!effects.length) return;
        allies.forEach(unit => {
            if (!unit) return;
            const savedMaxHp = Number(unit._abyssSavedMaxHp) || unit.maxHp;
            const hpRatio = abyssState ? (savedMaxHp > 0 ? unit.currentHp / savedMaxHp : 1) : 1;
            const statBuckets = effects.reduce((buckets, effect) => {
                const stat = effect.stat;
                if (!stat) return buckets;
                buckets[stat] = (buckets[stat] || 0) + (Number(effect.value) || 0);
                return buckets;
            }, {});
            if (statBuckets.atkMult) unit.stats.atk = Math.floor(unit.stats.atk * Math.max(0.1, 1 + statBuckets.atkMult));
            if (statBuckets.defMult) unit.stats.def = Math.floor(unit.stats.def * Math.max(0.1, 1 + statBuckets.defMult));
            if (statBuckets.maxHpMult) unit.stats.maxHp = Math.floor(unit.stats.maxHp * Math.max(0.1, 1 + statBuckets.maxHpMult));
            if (statBuckets.criAdd) unit.stats.cri = Math.min(1, (unit.stats.cri || 0) + statBuckets.criAdd);
            if (statBuckets.criDmgAdd) unit.stats.criDmg = (unit.stats.criDmg || 1.5) + statBuckets.criDmgAdd;
            unit.maxHp = unit.stats.maxHp;
            unit.currentHp = Math.max(1, Math.min(unit.maxHp, Math.floor(unit.maxHp * hpRatio)));
            unit.baseAtk = unit.stats.atk;
            delete unit._abyssSavedMaxHp;
        });
    }

    function _applyAbyssBattleStartRewards(allies, enemies) {
        if (!window.GG.AbyssSystem?.getRogueEffects) return;
        const effects = window.GG.AbyssSystem.getRogueEffects();
        effects.forEach(effect => {
            if (effect.type === 'battleStartEnergy') {
                allies.forEach(unit => { if (unit.currentHp > 0) unit.energy = Math.min(100, (unit.energy || 0) + (Number(effect.value) || 0)); });
            } else if (effect.type === 'battleStartStatus') {
                allies.forEach(unit => { if (unit.currentHp > 0) SS().applyStatus(unit, effect.statusId, effect.duration || 1, effect.value ?? null); });
            } else if (effect.type === 'enemyBattleStartStatus') {
                const alive = enemies.filter(e => e.currentHp > 0);
                const count = Math.min(alive.length, Math.max(1, effect.count || alive.length));
                const targets = [...alive].sort(() => Math.random() - 0.5).slice(0, count);
                targets.forEach(unit => SS().applyStatus(unit, effect.statusId, effect.duration || 1, effect.value ?? null));
            }
        });
    }

    // ===== 初始化战斗 =====
    // abyssState: 若为深渊继承模式，将传入上局保存的血量状态数组 [{id, currentHp, cooldowns}]
    function initBattle(stageConfig, allyData, abyssState) {
        const allies = allyData.map(({ id, saveData }) => {
            const unit = createAllyUnit(id, saveData);
            if (unit && abyssState) {
                const saved = abyssState.find(s => s.id === id);
                if (saved) {
                    unit.currentHp = saved.currentHp;
                    unit.cooldowns = saved.cooldowns || {};
                    unit.energy = Number.isFinite(saved.energy) ? saved.energy : (unit.energy || 0);
                    unit._abyssSavedMaxHp = Number.isFinite(saved.maxHp) ? saved.maxHp : unit.maxHp;
                }
            }
            return unit;
        }).filter(Boolean);

        if (stageConfig?.isAbyss) {
            _applyAbyssStatRewards(allies, abyssState);
        }

        // 深渊模式动态计算膨胀系数
        const enemies = stageConfig.enemies.map(eid => {
            let scale = stageConfig.scaleMult || 1.0;
            if (stageConfig.isAbyss && window.GG.AbyssData) {
                scale = window.GG.AbyssData.calcInflatedStats(stageConfig.floor, eid);
            }
            return createEnemyUnit(eid, scale);
        }).filter(Boolean);

        if (stageConfig?.isAbyss) {
            _applyAbyssBattleStartRewards(allies, enemies);
        }

        _state = {
            allies, enemies,
            turn: 0,
            phase: 'player_turn',
            log: [],
            roundRobin: [],
            currentActorIdx: 0,
            stageConfig,
            rewards: null,
            isAuto: _autoBattleEnabled, // 是否开启了自动战斗（继承上次选择）
        };

        refreshRoundRobin();
        EB().emit('battle:init', _state);
        return _state;
    }

    function refreshRoundRobin() {
        if (!_state) return;
        _state.roundRobin = buildActionQueue(_state.allies, _state.enemies);
        _state.currentActorIdx = 0;
        _state.turn++;
    }

    function getState() { return _state; }

    // 获取当前行动者（跳过已死亡单位）
    function getCurrentActor() {
        if (!_state) return null;
        const rr = _state.roundRobin;
        while (_state.currentActorIdx < rr.length) {
            const actor = rr[_state.currentActorIdx];
            if (actor.currentHp > 0) return actor;
            _state.currentActorIdx++;
        }
        return null;
    }

    // ===== 玩家技能行动 =====
    function playerAction(skillId) {
        if (!_state || _state.phase !== 'player_turn') return null;
        const actor = getCurrentActor();
        if (!actor || !actor.isAlly || actor.currentHp <= 0) return null;

        const skillData = window.GG.SkillData[skillId];
        if (!skillData) return null;
        if (!Skill().isSkillAvailable(skillId, actor)) return null;

        const result = Skill().executeSkill(skillId, actor, _state.allies, _state.enemies);
        _state.log.push(...result.log);

        EB().emit('battle:action', actor, skillId, result);
        CES()?.emit?.('after_action', {
            actor,
            skillId,
            result,
            state: _state,
            allies: _state.allies,
            enemies: _state.enemies,
        });
        advanceTurn();
        return result;
    }

    function getBattleSpeed() {
        return _battleSpeed;
    }

    function getScaledDelay(ms) {
        const speed = Math.max(1, _battleSpeed || 1);
        return Math.max(40, Math.floor(ms / speed));
    }

    function cycleBattleSpeed() {
        const speeds = [1, 2, 4];
        const idx = speeds.indexOf(_battleSpeed);
        _battleSpeed = speeds[(idx + 1) % speeds.length];
        EB().emit('battle:speed_changed', _battleSpeed);
        return _battleSpeed;
    }

    // ===== 推进回合 =====
    function advanceTurn() {
        if (!_state) return;
        _state.currentActorIdx++;

        if (checkVictory()) return;
        if (checkDefeat()) return;

        const next = getCurrentActor();
        if (!next) {
            processTurnEnd();
            return;
        }

        if (next.currentHp <= 0) {
            advanceTurn();
            return;
        }

        if (next.isAlly) {
            if (!SS().canAct(next)) {
                _state.log.push({ type: 'skip', unit: next.name, reason: '控制效果' });
                EB().emit('battle:skip', next);
                advanceTurn();
                return;
            }
            _state.phase = 'player_turn';
            EB().emit('battle:player_turn', next);

            // 如果开启了自动战斗，直接执行AI策略
            if (_state.isAuto) {
                setTimeout(() => executeAutoTurn(next), getScaledDelay(600));
            }
        } else {
            _state.phase = 'enemy_turn';
            EB().emit('battle:enemy_turn', next);
            setTimeout(() => executeEnemyTurn(next), getScaledDelay(800));
        }
    }

    // ===== 自动战斗 AI =====
    function executeAutoTurn(actor) {
        if (!_state || _state.phase !== 'player_turn' || !_state.isAuto) return;
        if (actor.currentHp <= 0) return;

        // 依次挑选：大招 -> 有冷却的小技能 -> 普攻
        let selectedSkillId = null;
        for (const sid of actor.skills) {
            const sData = window.GG.SkillData[sid];
            if (!sData) continue;

            if (sData.type === 'ultimate' && actor.energy >= 100) {
                selectedSkillId = sid;
                break;
            }
            if (sData.type === 'skill' && (actor.cooldowns?.[sid] || 0) <= 0) {
                selectedSkillId = sid;
                // 注意：这里不直接 break，如果后续发现有大招可以使用，大招优先级更高
            }
        }

        // 如果没有选到（比如能量不满、小技能都在CD），就用第一个技能（默认普攻）
        if (!selectedSkillId) {
            selectedSkillId = actor.skills[0];
        }

        // 通知 UI 执行（模拟玩家点击，能触发必杀特效等）
        EB().emit('battle:auto_action', actor.id, selectedSkillId);
    }

    // ===== 所有单位完成行动后处理 =====
    function processTurnEnd() {
        if (!_state) return;
        const all = [..._state.allies, ..._state.enemies];
        all.forEach(unit => {
            if (unit.currentHp <= 0) return;
            // 只有当这是这个单位刚刚行动的回合结束时才结算状态与冷却
            // 为简化：所有的Buff按大回合扣除，但技能冷却必须是“仅个人的行动后扣除”。
            // 由于 processTurnEnd 是所有人各自轮一次的大回合结束，依然会全部减，需修改它的逻辑为各退一回合
            CES()?.emit?.('unit_turn_start', {
                unit,
                state: _state,
                allies: unit.isAlly ? _state.allies : _state.enemies,
                enemies: unit.isAlly ? _state.enemies : _state.allies,
                log: _state.log,
            });

            SS().processTurnStart(unit, _state.log);
            SS().processTurnEnd(unit, _state.log);

            // 冷却统一结算机制：每个大回合结束时，所有人冷却 - 1。（也就是每过一轮，冷却好一回合）
            // 我方技能冷却倒数
            if (unit.isAlly && unit.cooldowns) {
                Object.keys(unit.cooldowns).forEach(k => { if (unit.cooldowns[k] > 0) unit.cooldowns[k]--; });
            }
            // 敌人技能冷却倒数
            if (!unit.isAlly && unit.skillCooldowns) {
                Object.keys(unit.skillCooldowns).forEach(k => { if (unit.skillCooldowns[k] > 0) unit.skillCooldowns[k]--; });
            }
        });

        if (checkVictory() || checkDefeat()) return;
        EB().emit('battle:turn_end', _state.turn);
        refreshRoundRobin();

        const firstActor = getCurrentActor();
        if (!firstActor) { processTurnEnd(); return; }
        if (firstActor.isAlly) {
            _state.phase = 'player_turn';
            EB().emit('battle:player_turn', firstActor);
            // 修复：新回合首个行动者为我方时，自动战斗也要立即接管
            if (_state.isAuto) {
                setTimeout(() => executeAutoTurn(firstActor), getScaledDelay(400));
            }
        } else {
            _state.phase = 'enemy_turn';
            setTimeout(() => executeEnemyTurn(firstActor), getScaledDelay(600));
        }
    }

    function checkVictory() {
        if (!_state) return false;
        if (_state.enemies.every(e => e.currentHp <= 0)) {
            _state.phase = 'victory';
            _state.rewards = calcRewards();

            // 深渊模式专属结算流程（状态继承+选项）
            if (_state.stageConfig.isAbyss) {
                const abyssResult = window.GG.AbyssSystem.processVictory(_state);
                EB().emit('battle:abyss_victory', { rewards: _state.rewards, floor: _state.stageConfig.floor, state: _state, nextStep: abyssResult?.nextStep, choices: abyssResult?.pendingChoices || [] });
            } else {
                EB().emit('battle:victory', _state.rewards);
            }
            return true;
        }
        return false;
    }

    function checkDefeat() {
        if (!_state) return false;
        if (_state.allies.every(a => a.currentHp <= 0)) {
            _state.phase = 'defeat';
            EB().emit('battle:defeat', { isAbyss: _state.stageConfig.isAbyss });
            return true;
        }
        return false;
    }

    function calcRewards() {
        const cfg = _state.stageConfig;

        // 如果是深渊，AbyssSystem 已经在进入时生成了具体的数值与必掉 5 星遗物
        if (cfg.isAbyss && cfg.rewards) {
            return cfg.rewards;
        }

        const goldRange = cfg.rewards?.gold || [30, 60];
        const gold = Math.floor(goldRange[0] + Math.random() * (goldRange[1] - goldRange[0]));
        const exp = cfg.rewards?.exp || 20;

        // 遗物掉落（普通关卡通关掉落几率不保底）
        const slots = ['helmet', 'chest', 'belt', 'boots', 'necklace'];
        const slotId = slots[Math.floor(Math.random() * slots.length)];
        const rarityRoll = Math.random() * 100;
        const rarity = rarityRoll < 5 ? 5 : rarityRoll < 40 ? 4 : 3;

        return {
            gold,
            exp,
            diamonds: cfg.rewards?.diamonds || 0,
            relicDrop: { slotId, rarity }, // 可拓展几率不掉落
        };
    }

    function endBattle() {
        _state = null;
    }

    // 切换自动战斗状态
    function toggleAutoBattle() {
        if (!_state) return false;
        _state.isAuto = !_state.isAuto;
        _autoBattleEnabled = _state.isAuto;

        // 如果切成自动时当前正好是我方回合，立马触发
        if (_state.isAuto && _state.phase === 'player_turn') {
            const actor = getCurrentActor();
            if (actor && actor.isAlly) {
                setTimeout(() => executeAutoTurn(actor), getScaledDelay(400));
            }
        }
        return _state.isAuto;
    }

    // ===== 启动第一回合（由 BattleUI 在绑定事件后调用）=====
    // Bug2修复：如果第一个行动者是敌人，之前无人触发其回合
    function startBattle() {
        if (!_state) return;
        const firstActor = getCurrentActor();
        if (!firstActor) return;
        if (firstActor.currentHp <= 0) {
            advanceTurn();
            return;
        }
        if (firstActor.isAlly) {
            _state.phase = 'player_turn';
            EB().emit('battle:player_turn', firstActor);
            // 修复：开局第一手若是我方且已开启自动战斗，要立即自动出手
            if (_state.isAuto) {
                setTimeout(() => executeAutoTurn(firstActor), getScaledDelay(400));
            }
        } else {
            _state.phase = 'enemy_turn';
            EB().emit('battle:enemy_turn', firstActor);
            setTimeout(() => executeEnemyTurn(firstActor), getScaledDelay(1000));
        }
    }

    return {
        initBattle, getState, getCurrentActor,
        playerAction, advanceTurn, endBattle, startBattle,
        createAllyUnit, createEnemyUnit, toggleAutoBattle,
        cycleBattleSpeed, getBattleSpeed, getScaledDelay,
    };
})();
