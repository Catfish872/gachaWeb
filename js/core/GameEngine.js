// 游戏总引擎 — 全局状态机，协调所有子系统
window.GG = window.GG || {};
window.GG.GameEngine = (function () {
    const EB = () => window.GG.EventBus;
    const S = () => window.GG.SaveSystem;
    const Stamina = () => window.GG.StaminaSystem;
    const CP = () => window.GG.CharacterProgression;

    let _initialized = false;

    function _setupListeners() {
        // 资源变化时更新顶部栏
        EB().on('resource:changed', () => {
            window.GG.UIManager?.updateResourceBar?.();
        });
        // 体力 tick 时更新
        EB().on('stamina:tick', () => {
            window.GG.UIManager?.updateResourceBar?.();
        });
        // 角色升级提示
        EB().on('character:level_up', (charId, payload) => {
            const name = window.GG.CharacterData?.[charId]?.name || charId;
            const newLv = payload?.newLevel || 1;
            window.GG.UIManager?.showToast?.(`🎉 ${name} 升至 Lv.${newLv}`, 'success');
            window.GG.TeamUI?.render?.();
        });
    }

    // 进入关卡（扣体力，初始化战斗）
    function enterStage(stageId) {
        const allChapters = window.GG.StageData.chapters;
        let stageConfig = null;
        for (const ch of allChapters) {
            stageConfig = ch.stages.find(s => s.id === stageId);
            if (stageConfig) break;
        }
        if (!stageConfig) return { success: false, error: '关卡不存在' };

        const cost = stageConfig.staminaCost || 6;
        if (!Stamina().consume(cost)) return { success: false, error: '体力不足！请等待恢复或前往商城充能。' };

        // 构建我方队伍
        const save = S().get();
        const team = (save.team || []).filter(Boolean);
        if (team.length === 0) return { success: false, error: '队伍为空，请先编队！' };

        const allyData = team.map(id => ({
            id,
            saveData: save.ownedCharacters[id] || { level: 1, awakening: 0 },
        }));

        // 创建战斗配置
        const wave = stageConfig.waves?.[0] || { enemies: [] };
        const battleConfig = {
            ...stageConfig,
            enemies: wave.enemies,
            scaleMult: 1.0,
        };

        const battleState = window.GG.BattleEngine.initBattle(battleConfig, allyData);
        EB().emit('game:enter_battle', stageId, battleState);
        return { success: true, battleState };
    }

    // 获取章节是否解锁
    function isChapterUnlocked(chapterId) {
        const save = S().get();
        const ch = window.GG.StageData.chapters.find(c => c.id === chapterId);
        if (!ch) return false;
        if (ch.unlocked) return true;
        if (ch.unlockCondition) return !!save.stageProgress?.[ch.unlockCondition]?.cleared;
        return false;
    }

    // 标记关卡通关
    function markStageCleared(stageId, turns) {
        const save = S().get();
        if (!save.stageProgress) save.stageProgress = {};
        const prev = save.stageProgress[stageId] || {};
        save.stageProgress[stageId] = {
            cleared: true,
            stars: 3, // TODO: 根据通关条件给星
            bestTurns: Math.min(turns, prev.bestTurns ?? Infinity),
        };
        save.stats.totalVictories = (save.stats.totalVictories || 0) + 1;
        save.stats.totalBattles = (save.stats.totalBattles || 0) + 1;
        S().save();
    }

    // ====== 新增：进入深渊下一层 ======
    function enterAbyssLayer() {
        const allyData = [];
        const save = S().get();
        const team = (save.team || []).filter(Boolean);
        if (team.length === 0) return { success: false, error: '队伍为空，请先编队！' };

        team.forEach(id => {
            allyData.push({ id, saveData: save.ownedCharacters[id] || { level: 1, awakening: 0 } });
        });

        // 生成深渊关卡
        const result = window.GG.AbyssSystem.enterNextFloor();
        if (!result.success) return result;

        const stageConfig = result.stageConfig;

        // 构建带深渊膨胀系数的战斗配置
        const battleConfig = {
            ...stageConfig,
            scaleMult: 1.0, // 在 BattleEngine 里会根据 stageConfig.floor 提取对应公式
        };

        // 载入持久化的深渊状态传入 initBattle
        const abyssState = save.abyss?.savedPartyState;

        const battleState = window.GG.BattleEngine.initBattle(battleConfig, allyData, abyssState);
        EB().emit('game:enter_battle', stageConfig.id, battleState);

        return { success: true, battleState };
    }

    // ====== 战斗胜利全局处理 ======
    function _onBattleVictory(rewards) {
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
                // 通知UI弹出Toast
                window.GG.EventBus.emit('relic:dropped', relic);
            }
        }

        S().save();

        // 触发资源变更UI更新
        window.GG.EventBus.emit('resource:changed', 'gold', save.resources.gold);
        window.GG.EventBus.emit('resource:changed', 'diamonds', save.resources.diamonds);
    }

    function _onBattleDefeat(config) {
        // 如果是深渊失败，清除暂存进度与本局肉鸽构筑
        if (config?.isAbyss) {
            window.GG.AbyssSystem?.clearRunOnDefeat?.();
        }
    }

    // 游戏初始化（入口调用）
    function init() {
        if (_initialized) return;
        _setupListeners();
        EB().on('battle:victory', _onBattleVictory);
        EB().on('battle:defeat', _onBattleDefeat);
        _initialized = true;
        EB().emit('game:ready');
        console.log('[GameEngine] 游戏初始化完成 ✓');
    }

    // 检测并发放章节五星角色赠送（由 UI 层在合适时机调用）
    // 返回 null 表示未触发赠送，否则返回 { isNew, shardsGained, charName }
    function checkChapterGift(stageId) {
        return window.GG.ChapterGiftSystem?.checkAndGrant(stageId) || null;
    }

    return {
        init,
        enterStage,
        isChapterUnlocked,
        markStageCleared,
        checkChapterGift,   // 新增：章节五星赠送检测
        enterAbyssLayer,    // 新增：深渊入口
    };
})();
