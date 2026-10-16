// 深渊系统业务层
window.GG = window.GG || {};
window.GG.AbyssSystem = (function () {
    const S = () => window.GG.SaveSystem;
    const GE = () => window.GG.GameEngine;
    const BE = () => window.GG.BattleEngine;
    const AD = () => window.GG.AbyssData;
    const EB = () => window.GG.EventBus;
    const Stamina = () => window.GG.StaminaSystem;
    const CP = () => window.GG.CharacterProgression;

    function _createRogueState() {
        return {
            runId: null,
            selectedRewards: [],
            pendingChoices: [],
            nextStep: { type: 'none', floor: 0 },
            characterFocus: {},
            eligibleCharacters: [],
            temporaryCurrency: 0,
            eventHistory: [],
            shopStock: [],
        };
    }

    function _normalizeRogue(prog) {
        if (!prog.rogue || typeof prog.rogue !== 'object') prog.rogue = _createRogueState();
        const base = _createRogueState();
        prog.rogue = {
            ...base,
            ...prog.rogue,
            selectedRewards: Array.isArray(prog.rogue.selectedRewards) ? prog.rogue.selectedRewards : [],
            pendingChoices: Array.isArray(prog.rogue.pendingChoices) ? prog.rogue.pendingChoices : [],
            nextStep: (prog.rogue.nextStep && typeof prog.rogue.nextStep === 'object') ? prog.rogue.nextStep : { type: 'none', floor: 0 },
            characterFocus: (prog.rogue.characterFocus && typeof prog.rogue.characterFocus === 'object') ? prog.rogue.characterFocus : {},
            eligibleCharacters: Array.isArray(prog.rogue.eligibleCharacters) ? prog.rogue.eligibleCharacters : [],
            eventHistory: Array.isArray(prog.rogue.eventHistory) ? prog.rogue.eventHistory : [],
            shopStock: Array.isArray(prog.rogue.shopStock) ? prog.rogue.shopStock : [],
        };
        return prog.rogue;
    }

    // 获取深渊进度数据
    function getProgress() {
        const save = S().get();
        if (!save.abyss) {
            save.abyss = {
                currentFloor: 1,      // 当前挑战到的层数
                maxFloor: 0,          // 历史最高层数
                savedPartyState: null,// 暂离保存的阵容和血量状态
                lastFreeResetTime: 0, // 上次免费重置的时间戳（每日0点刷新）
                rogue: _createRogueState(),
            };
        }
        _normalizeRogue(save.abyss);
        return save.abyss;
    }

    function getRogueState() {
        return _normalizeRogue(getProgress());
    }

    function _getTeamFiveStars() {
        const save = S().get();
        const team = (save.team || []).filter(Boolean);
        return team.filter(id => window.GG.CharacterData?.[id]?.rarity === 5);
    }

    function _initRogueRunIfNeeded() {
        const prog = getProgress();
        const rogue = getRogueState();
        if (rogue.runId) return rogue;

        const chars = _getTeamFiveStars();
        rogue.runId = `abyss_${Date.now()}_${Math.random().toString(36).slice(2)}`;
        rogue.selectedRewards = [];
        rogue.pendingChoices = [];
        rogue.nextStep = { type: 'none', floor: 0 };
        rogue.eligibleCharacters = chars;
        rogue.characterFocus = {};
        const base = chars.length ? 1 / chars.length : 0;
        chars.forEach(id => { rogue.characterFocus[id] = base; });
        prog.rogue = rogue;
        S().save();
        return rogue;
    }

    function resetRogueRun() {
        const prog = getProgress();
        prog.rogue = _createRogueState();
    }

    // 检查今天是否可以免费重置
    function canFreeReset() {
        const prog = getProgress();
        const lastDate = new Date(prog.lastFreeResetTime);
        const now = new Date();
        // 如果上次重置不是今天，则可以免费重置
        return lastDate.toDateString() !== now.toDateString();
    }

    // 执行重置进度
    function reset(useDiamonds = false) {
        const save = S().get();
        const prog = getProgress();

        if (!useDiamonds) {
            if (!canFreeReset()) return { success: false, error: '今日免费重置次数已用完' };
            prog.lastFreeResetTime = Date.now();
        } else {
            const cost = AD().resetDiamondCost || 100;
            if ((save.resources?.diamonds || 0) < cost) {
                return { success: false, error: `钻石不足（需要 ${cost} 💎）` };
            }
            save.resources.diamonds -= cost;
            EB().emit('resource:changed', 'diamonds', save.resources.diamonds);
        }

        // 清空状态、层数和本局肉鸽构筑
        prog.currentFloor = 1;
        prog.savedPartyState = null;
        resetRogueRun();
        S().save();
        return { success: true };
    }

    // 暂离/保存队伍当前状态
    function savePartyState(battleState) {
        if (!battleState || !battleState.allies) return;
        const prog = getProgress();

        prog.savedPartyState = battleState.allies.map(a => ({
            id: a.id,
            currentHp: a.currentHp,
            maxHp: a.maxHp || a.stats?.maxHp || 1,
            energy: a.energy || 0,
            cooldowns: a.cooldowns || {}
        }));

        S().save();
    }

    // 清除队伍保存状态（例如团灭后）
    function clearPartyState() {
        const prog = getProgress();
        prog.savedPartyState = null;
        S().save();
    }

    function _isRewardFloor(floor) {
        const marks = AD().rogue?.rewardFloorsInCycle || [3, 6, 9];
        return marks.includes(floor % 10);
    }

    function _isBossRewardFloor(floor) {
        return floor > 0 && floor % 10 === 0;
    }

    // 生成深渊关卡并计算奖励
    function enterNextFloor() {
        _initRogueRunIfNeeded();
        const prog = getProgress();
        const floor = prog.currentFloor;
        const config = AD().generateStageConfig(floor);

        // 深渊必掉一只高星遗物
        const rarityRoll = Math.random();
        // 1-9层 4星保底（概率出5星），10层往后必出5星
        const base5StarRate = (floor - 1) * 0.05 + 0.05; // 5%, 10%, 15%... 
        let relicRarity = 4;
        if (floor >= 10 || rarityRoll < base5StarRate) relicRarity = 5;

        const diamondReward = floor >= 10
            ? Math.min(500, 100 + Math.floor((floor - 10) / 10) * 50)
            : 0;

        config.rewards = {
            gold: Math.floor(AD().rewards.gold[0] * (1 + floor * 0.1) + Math.random() * (AD().rewards.gold[1] - AD().rewards.gold[0])),
            exp: AD().rewards.exp + floor * 20,
            diamonds: diamondReward,
            relicDrop: {
                slotId: window.GG.RelicSlots[Math.floor(Math.random() * 5)].id,
                rarity: relicRarity
            }
        };

        return { success: true, stageConfig: config };
    }

    function _cloneReward(reward) {
        return JSON.parse(JSON.stringify(reward));
    }

    function _pickByWeight(items, getWeight) {
        const weighted = (items || []).map(item => ({ item, weight: Math.max(0, Number(getWeight(item)) || 0) })).filter(x => x.weight > 0);
        const total = weighted.reduce((sum, x) => sum + x.weight, 0);
        if (!total) return weighted[0]?.item || items?.[0] || null;
        let roll = Math.random() * total;
        for (const entry of weighted) {
            roll -= entry.weight;
            if (roll <= 0) return entry.item;
        }
        return weighted[weighted.length - 1]?.item || null;
    }

    function _pickRarity(forcedRarity = null) {
        if (forcedRarity) return forcedRarity;
        const weights = AD().rogue?.rarityWeights || { white: 62, blue: 30, gold: 8 };
        return _pickByWeight(Object.keys(weights), key => weights[key]) || 'white';
    }

    function _availableRewards() {
        const rogue = getRogueState();
        const eligible = new Set(rogue.eligibleCharacters || []);
        return (AD().rogue?.rewards || []).filter(r => {
            if (r.pool === 'character') return eligible.has(r.characterId);
            return true;
        });
    }

    function _drawReward(preferPool, excludeIds = new Set(), forcedRarity = null) {
        const rogue = getRogueState();
        const rarity = _pickRarity(forcedRarity);
        const all = _availableRewards().filter(r => !excludeIds.has(r.id));
        const poolFiltered = all.filter(r => preferPool ? r.pool === preferPool : true);
        const rarityPool = poolFiltered.filter(r => r.rarity === rarity);
        const candidates = rarityPool.length ? rarityPool : (poolFiltered.length ? poolFiltered : all);
        if (!candidates.length) return null;

        return _cloneReward(_pickByWeight(candidates, r => {
            if (r.pool === 'common') return 1;
            const focus = rogue.characterFocus?.[r.characterId] ?? 0.25;
            return Math.max(0.01, focus);
        }));
    }

    function generateRewardChoices(floor, options = {}) {
        const choices = [];
        const used = new Set();
        const forcedRarity = options.forceRarity || null;
        const forceGold = forcedRarity === 'gold';

        if (!forceGold) {
            const common = _drawReward('common', used);
            if (common) { choices.push(common); used.add(common.id); }
        }

        while (choices.length < 3) {
            const reward = _drawReward(null, used, forcedRarity);
            if (!reward) break;
            choices.push(reward);
            used.add(reward.id);
        }

        if (choices.length < 3) {
            _availableRewards()
                .filter(r => !forcedRarity || r.rarity === forcedRarity)
                .forEach(r => {
                    if (choices.length >= 3 || used.has(r.id)) return;
                    choices.push(_cloneReward(r));
                    used.add(r.id);
                });
        }

        return choices.map((r, idx) => ({ ...r, choiceId: `${floor}_${idx}_${r.id}` }));
    }

    function _updateFocusForReward(reward) {
        if (!reward?.characterId) return;
        const cfg = AD().rogue || {};
        const rogue = getRogueState();
        const ids = rogue.eligibleCharacters || [];
        if (!ids.includes(reward.characterId) || ids.length <= 0) return;

        const min = cfg.focusMin ?? 0.15;
        const max = cfg.focusMax ?? 0.45;
        const gain = cfg.focusGainOnPick ?? 0.10;
        const focus = { ...(rogue.characterFocus || {}) };
        ids.forEach(id => { if (!Number.isFinite(focus[id])) focus[id] = 1 / ids.length; });
        focus[reward.characterId] = Math.min(max, focus[reward.characterId] + gain);

        let remaining = Math.max(0, 1 - focus[reward.characterId]);
        const others = ids.filter(id => id !== reward.characterId);
        const otherTotal = others.reduce((sum, id) => sum + Math.max(min, focus[id]), 0);
        others.forEach(id => {
            const ratio = otherTotal > 0 ? Math.max(min, focus[id]) / otherTotal : 1 / Math.max(1, others.length);
            focus[id] = Math.max(min, Math.min(max, remaining * ratio));
        });

        const sum = ids.reduce((acc, id) => acc + focus[id], 0) || 1;
        ids.forEach(id => { focus[id] = Math.max(min, Math.min(max, focus[id] / sum)); });
        rogue.characterFocus = focus;
    }

    function chooseReward(choiceId, fallbackChoice = null) {
        const prog = getProgress();
        const rogue = getRogueState();
        let reward = (rogue.pendingChoices || []).find(r => r.choiceId === choiceId || r.id === choiceId);
        if (!reward && fallbackChoice && (fallbackChoice.choiceId === choiceId || fallbackChoice.id === choiceId)) {
            const fallbackFloor = String(fallbackChoice.choiceId || '').split('_')[0];
            const isSameRewardFloor = Number(fallbackFloor) === (rogue.nextStep?.floor || Math.max(1, prog.currentFloor - 1));
            if (rogue.nextStep?.type === 'reward' && isSameRewardFloor) {
                reward = fallbackChoice;
                rogue.pendingChoices = [fallbackChoice];
            }
        }
        if (!reward) return { success: false, error: '奖励选项不存在或已过期' };

        const stored = _cloneReward(reward);
        delete stored.choiceId;
        stored.pickedAtFloor = rogue.nextStep?.floor || Math.max(1, prog.currentFloor - 1);
        rogue.selectedRewards.push(stored);
        rogue.pendingChoices = [];
        rogue.nextStep = { type: 'none', floor: stored.pickedAtFloor };
        _updateFocusForReward(stored);
        S().save();
        return { success: true, reward: stored, nextStep: rogue.nextStep };
    }

    function getSelectedRewards() {
        return getRogueState().selectedRewards || [];
    }

    function getRogueEffects() {
        return getSelectedRewards().flatMap((r, idx) => (r.effects || []).map(e => ({
            ...e,
            rewardId: r.id,
            rewardInstanceId: `${r.id}_${idx}`,
            rewardName: r.name
        })));
    }

    function _applyVictoryRecovery(battleState) {
        const effects = getRogueEffects().filter(e => e.type === 'victoryHealPct');
        if (!effects.length || !battleState?.allies) return;
        const pct = effects.reduce((sum, e) => sum + (Number(e.value) || 0), 0);
        if (pct <= 0) return;
        battleState.allies.forEach(unit => {
            if (!unit || unit.currentHp <= 0) return;
            unit.currentHp = Math.min(unit.maxHp, Math.floor(unit.currentHp + unit.maxHp * pct));
        });
    }

    // 战斗引擎完成一场“深渊”胜利后，推进层数并记录
    function processVictory(battleState) {
        const prog = getProgress();
        const rewards = battleState.rewards || {};

        // 发放奖励（普通胜利在GameEngine里，深渊专门在这处理）
        const save = S().get();
        if (rewards.gold) save.resources.gold += rewards.gold;
        if (rewards.diamonds) save.resources.diamonds += rewards.diamonds;
        if (rewards.exp) {
            CP()?.grantTeamExp?.(save, rewards.exp);
        }

        // 处理通关遗物掉落
        if (rewards.relicDrop) {
            const relic = window.GG.RelicSystem?.generate(rewards.relicDrop.rarity, rewards.relicDrop.slotId);
            if (relic) {
                window.GG.RelicSystem?.addToInventory(relic);
                EB().emit('relic:dropped', relic);
            }
        }

        // 触发资源UI变更
        EB().emit('resource:changed', 'gold', save.resources.gold);
        EB().emit('resource:changed', 'diamonds', save.resources.diamonds);

        _applyVictoryRecovery(battleState);

        // 先推进层数，再保存刚打完的队伍状态；随后再写奖励待选，避免 savePartyState 的保存覆盖 pendingChoices
        const clearedFloor = prog.currentFloor;
        prog.currentFloor++;
        if (clearedFloor > prog.maxFloor) {
            prog.maxFloor = clearedFloor;
        }
        savePartyState(battleState);

        const pendingChoices = _isBossRewardFloor(clearedFloor)
            ? generateRewardChoices(clearedFloor, { forceRarity: 'gold' })
            : (_isRewardFloor(clearedFloor) ? generateRewardChoices(clearedFloor) : []);
        const rogue = getRogueState();
        if (pendingChoices.length) {
            rogue.pendingChoices = pendingChoices;
            rogue.nextStep = { type: 'reward', floor: clearedFloor };
        } else {
            rogue.pendingChoices = [];
            rogue.nextStep = { type: 'none', floor: clearedFloor };
        }

        S().save();
        return { nextStep: { ...rogue.nextStep }, pendingChoices: [...rogue.pendingChoices] };
    }

    function clearRunOnDefeat() {
        const prog = getProgress();
        prog.savedPartyState = null;
        resetRogueRun();
        S().save();
    }

    return {
        getProgress, getRogueState, getSelectedRewards, getRogueEffects,
        canFreeReset, reset, resetRogueRun,
        enterNextFloor, savePartyState, clearPartyState, clearRunOnDefeat,
        processVictory, chooseReward, generateRewardChoices
    };
})();
