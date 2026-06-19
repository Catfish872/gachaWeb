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

    // 获取深渊进度数据
    function getProgress() {
        const save = S().get();
        if (!save.abyss) {
            save.abyss = {
                currentFloor: 1,      // 当前挑战到的层数
                maxFloor: 0,          // 历史最高层数
                savedPartyState: null,// 暂离保存的阵容和血量状态
                lastFreeResetTime: 0  // 上次免费重置的时间戳（每日0点刷新）
            };
        }
        return save.abyss;
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

        // 清空状态和层数
        prog.currentFloor = 1;
        prog.savedPartyState = null;
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

    // 生成深渊关卡并计算奖励
    function enterNextFloor() {
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

        // 如果此时全部幸存，直接推进下一层
        prog.currentFloor++;
        if (prog.currentFloor - 1 > prog.maxFloor) {
            prog.maxFloor = prog.currentFloor - 1;
        }
        savePartyState(battleState); // 暂时保存刚打完的状态
        S().save();
    }

    return {
        getProgress, canFreeReset, reset,
        enterNextFloor, savePartyState, clearPartyState, processVictory
    };
})();
