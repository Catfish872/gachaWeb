// 角色经验与等级系统
window.GG = window.GG || {};
window.GG.CharacterProgression = (function () {
    const S = () => window.GG.SaveSystem;
    const EB = () => window.GG.EventBus;

    const MAX_LEVEL = 10;
    const BASE_NEED_LV1 = 50;   // 1 -> 2
    const BASE_NEED_LV2 = 200;  // 2 -> 3，之后翻倍
    const MAX_EXP_NEED = 5000;

    function getExpToNextLevel(level) {
        const lv = Math.max(1, Math.min(level || 1, MAX_LEVEL));
        if (lv >= MAX_LEVEL) return 0;
        if (lv === 1) return BASE_NEED_LV1;
        return Math.min(BASE_NEED_LV2 * Math.pow(2, lv - 2), MAX_EXP_NEED);
    }

    function normalizeCharacterProgress(charSave) {
        if (!charSave || typeof charSave !== 'object') return;
        if (typeof charSave.level !== 'number' || !Number.isFinite(charSave.level)) charSave.level = 1;
        charSave.level = Math.max(1, Math.min(MAX_LEVEL, Math.floor(charSave.level)));

        if (typeof charSave.exp !== 'number' || !Number.isFinite(charSave.exp)) charSave.exp = 0;
        charSave.exp = Math.max(0, Math.floor(charSave.exp));

        if (charSave.level >= MAX_LEVEL) {
            charSave.exp = 0;
            return;
        }

        // 兼容历史存档：若 exp 异常过大，自动结算到合法区间
        while (charSave.level < MAX_LEVEL) {
            const need = getExpToNextLevel(charSave.level);
            if (charSave.exp < need) break;
            charSave.exp -= need;
            charSave.level += 1;
        }
        if (charSave.level >= MAX_LEVEL) {
            charSave.level = MAX_LEVEL;
            charSave.exp = 0;
        }
    }

    function grantExp(charSave, expGain) {
        normalizeCharacterProgress(charSave);
        const gain = Math.max(0, Math.floor(expGain || 0));
        if (!charSave || gain <= 0) return { gained: 0, leveledUp: 0, oldLevel: 1, newLevel: 1, oldExp: 0, newExp: 0 };

        const oldLevel = charSave.level;
        const oldExp = charSave.exp;

        if (charSave.level >= MAX_LEVEL) {
            return { gained: 0, leveledUp: 0, oldLevel, newLevel: oldLevel, oldExp, newExp: 0 };
        }

        charSave.exp += gain;
        let leveledUp = 0;
        while (charSave.level < MAX_LEVEL) {
            const need = getExpToNextLevel(charSave.level);
            if (charSave.exp < need) break;
            charSave.exp -= need;
            charSave.level += 1;
            leveledUp += 1;
        }

        if (charSave.level >= MAX_LEVEL) {
            charSave.level = MAX_LEVEL;
            charSave.exp = 0;
        }

        return {
            gained: gain,
            leveledUp,
            oldLevel,
            newLevel: charSave.level,
            oldExp,
            newExp: charSave.exp,
        };
    }

    // 队伍发放经验（普通关卡/深渊共用）
    function grantTeamExp(save, expGain) {
        const gain = Math.max(0, Math.floor(expGain || 0));
        if (!save || gain <= 0) return [];

        const team = (save.team || []).filter(Boolean);
        const changes = [];

        team.forEach(charId => {
            const charSave = save.ownedCharacters?.[charId];
            if (!charSave) return;
            const result = grantExp(charSave, gain);
            changes.push({ charId, ...result });

            EB()?.emit?.('character:exp_changed', charId, {
                level: charSave.level,
                exp: charSave.exp,
                gain,
            });

            if (result.leveledUp > 0) {
                EB()?.emit?.('character:level_up', charId, {
                    oldLevel: result.oldLevel,
                    newLevel: result.newLevel,
                });
            }
        });

        return changes;
    }

    // 用于存档迁移/抽卡新角色初始化
    function createDefaultProgress() {
        return { level: 1, exp: 0 };
    }

    return {
        MAX_LEVEL,
        MAX_EXP_NEED,
        getExpToNextLevel,
        normalizeCharacterProgress,
        grantExp,
        grantTeamExp,
        createDefaultProgress,
    };
})();
