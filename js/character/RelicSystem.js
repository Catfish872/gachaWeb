// 遗物系统 — 生成/强化/装备/属性加成
window.GG = window.GG || {};
window.GG.RelicSystem = (function () {
    const S = () => window.GG.SaveSystem;
    const Slots = () => window.GG.RelicSlots;
    const MainPool = () => window.GG.RelicMainStatPool;
    const SubPool = () => window.GG.RelicSubStatPool;
    const RarityConf = () => window.GG.RelicRarityConfig;
    const UpgradeCost = (lv) => window.GG.relicUpgradeCost(lv);

    // ===== 生成一件遗物 =====
    function generate(rarity, slotId) {
        const slotMainPool = MainPool()[slotId];
        if (!slotMainPool) return null;

        // 随机选主词条
        const mainDef = slotMainPool[Math.floor(Math.random() * slotMainPool.length)];

        // 随机副词条（从池中选，不与主词条重复）
        const rarityConf = RarityConf()[rarity] || RarityConf()[3];
        const pool = SubPool().filter(s => s.stat !== mainDef.stat);
        const subCount = rarityConf.initSubStats;
        const subs = _pickRandom(pool, subCount).map(def => ({
            stat: def.stat,
            name: def.name,
            value: _randBetween(def.range[0], def.range[1], def.stat),
        }));

        return {
            uid: Date.now() + Math.random().toString(36).slice(2, 7),
            slotId,
            rarity,
            level: 0,   // 强化等级 0~25
            mainStat: { stat: mainDef.stat, name: mainDef.name, base: mainDef.base, perLevel: mainDef.perLevel },
            subStats: subs,
            equippedBy: null,   // 装备给哪个角色ID，null=背包
        };
    }

    // ===== 强化遗物（+1级）=====
    function upgrade(relicUid) {
        const save = S().get();
        const relic = _findRelic(save, relicUid);
        if (!relic) return { success: false, error: '遗物不存在' };
        if (relic.level >= 25) return { success: false, error: '已达最高强化等级' };

        const cost = UpgradeCost(relic.level);
        if ((save.resources?.gold || 0) < cost) {
            return { success: false, error: `金币不足（需要 ${cost} 🪙）` };
        }

        save.resources.gold -= cost;
        const boosted = _upgradeOneLevel(relic);
        S().save();
        return { success: true, boostedStat: boosted, newLevel: relic.level, cost };
    }

    // ===== 一键强化到满级（一次性扣费）=====
    function upgradeToMax(relicUid) {
        const save = S().get();
        const relic = _findRelic(save, relicUid);
        if (!relic) return { success: false, error: '遗物不存在' };
        if (relic.level >= 25) return { success: false, error: '已达满强化' };

        const totalCost = getUpgradeCostToMax(relicUid);
        if ((save.resources?.gold || 0) < totalCost) {
            return { success: false, error: `金币不足（需要 ${totalCost} 🪙）` };
        }

        const oldLevel = relic.level;
        save.resources.gold -= totalCost;
        const boostedStats = [];
        while (relic.level < 25) {
            const boosted = _upgradeOneLevel(relic);
            if (boosted) boostedStats.push(boosted);
        }

        S().save();
        return {
            success: true,
            oldLevel,
            newLevel: relic.level,
            totalCost,
            boostedStats,
        };
    }

    function getUpgradeCostToMax(relicUid) {
        const save = S().get();
        const relic = _findRelic(save, relicUid);
        if (!relic) return 0;
        let cost = 0;
        for (let lv = relic.level; lv < 25; lv++) {
            cost += UpgradeCost(lv);
        }
        return cost;
    }

    function _upgradeOneLevel(relic) {
        relic.level++;

        // 每满4级提升一条副词条
        if (relic.level % 4 === 0 && relic.subStats.length > 0) {
            const targetSub = relic.subStats[Math.floor(Math.random() * relic.subStats.length)];
            const def = SubPool().find(s => s.stat === targetSub.stat);
            if (def) {
                const boost = _randBetween(def.range[0] * 0.8, def.range[1] * 0.8, targetSub.stat);
                targetSub.value += boost;
                targetSub.value = _round(targetSub.value, def.stat);
            }
            return targetSub.name;
        }
        return null;
    }

    // ===== 将背包遗物装备给角色 =====
    function equip(charId, relicUid) {
        const save = S().get();
        const relic = _findRelic(save, relicUid);
        if (!relic) return { success: false, error: '遗物不存在' };

        // 先卸下该角色同部位的旧遗物
        const oldUid = save.ownedCharacters?.[charId]?.equippedRelics?.[relic.slotId];
        if (oldUid && oldUid !== relicUid) {
            const old = _findRelic(save, oldUid);
            if (old) old.equippedBy = null;
        }

        // 若此遗物已被其他角色装备，先卸下
        if (relic.equippedBy && relic.equippedBy !== charId) {
            const prev = save.ownedCharacters?.[relic.equippedBy];
            if (prev?.equippedRelics) prev.equippedRelics[relic.slotId] = null;
        }

        // 装备
        if (!save.ownedCharacters[charId]) return { success: false, error: '未拥有该角色' };
        save.ownedCharacters[charId].equippedRelics = save.ownedCharacters[charId].equippedRelics || {};
        save.ownedCharacters[charId].equippedRelics[relic.slotId] = relicUid;
        relic.equippedBy = charId;
        S().save();
        return { success: true };
    }

    // ===== 卸下遗物 =====
    function unequip(charId, slotId) {
        const save = S().get();
        const equippedRelics = save.ownedCharacters?.[charId]?.equippedRelics;
        if (!equippedRelics) return;
        const uid = equippedRelics[slotId];
        if (uid) {
            const relic = _findRelic(save, uid);
            if (relic) relic.equippedBy = null;
            equippedRelics[slotId] = null;
        }
        S().save();
    }

    // ===== 获取角色身上的遗物加成（供 CharacterStats 使用）=====
    function getEquippedBonuses(charId) {
        const save = S().get();
        const equippedRelics = save.ownedCharacters?.[charId]?.equippedRelics || {};
        const bonus = {
            hp_flat: 0, atk_flat: 0, def_flat: 0,
            hp_pct: 0, atk_pct: 0, def_pct: 0,
            spd: 0, cri_rate: 0, cri_dmg: 0, energy_rate: 0,
        };

        Slots().forEach(slot => {
            const uid = equippedRelics[slot.id];
            if (!uid) return;
            const relic = _findRelic(save, uid);
            if (!relic) return;

            // 主词条
            const mainVal = relic.mainStat.base + relic.mainStat.perLevel * relic.level;
            _addStatBonus(bonus, relic.mainStat.stat, mainVal);

            // 副词条
            relic.subStats.forEach(sub => {
                _addStatBonus(bonus, sub.stat, sub.value);
            });
        });

        return bonus;
    }

    // ===== 获取遗物背包列表（按部位过滤可选）=====
    function getInventory(slotFilter) {
        const save = S().get();
        const all = save.relics || [];
        if (slotFilter) return all.filter(r => r.slotId === slotFilter);
        return all;
    }

    // ===== 获取角色已装备的遗物对象（5件）=====
    function getEquippedRelics(charId) {
        const save = S().get();
        const result = {};
        const equipped = save.ownedCharacters?.[charId]?.equippedRelics || {};
        Slots().forEach(slot => {
            const uid = equipped[slot.id];
            result[slot.id] = uid ? _findRelic(save, uid) : null;
        });
        return result;
    }

    // ===== 遗物主词条当前值 =====
    function getMainStatValue(relic) {
        return relic.mainStat.base + relic.mainStat.perLevel * relic.level;
    }

    // ===== 内部工具函数 =====
    function _findRelic(save, uid) {
        return (save.relics || []).find(r => r.uid === uid) || null;
    }

    function _pickRandom(arr, n) {
        const copy = [...arr];
        const result = [];
        for (let i = 0; i < n && copy.length > 0; i++) {
            const idx = Math.floor(Math.random() * copy.length);
            result.push(copy.splice(idx, 1)[0]);
        }
        return result;
    }

    function _randBetween(min, max, stat) {
        // 根据 stat 类型决定精度
        const val = min + Math.random() * (max - min);
        return _round(val, stat);
    }

    function _round(val, stat) {
        // 整数型 stat：spd, hp_flat, atk_flat, def_flat
        if (['spd', 'hp_flat', 'atk_flat', 'def_flat', 'energy_rate_flat'].includes(stat)) {
            return Math.round(val);
        }
        return Math.round(val * 1000) / 1000; // 保留3位小数（百分比）
    }

    function _addStatBonus(bonus, stat, val) {
        if (bonus[stat] !== undefined) bonus[stat] += val;
    }

    // ===== 新增遗物到背包 =====
    function addToInventory(relic) {
        const save = S().get();
        if (!save.relics) save.relics = [];
        save.relics.push(relic);
        S().save();
    }

    // ===== 分解遗物（从背包移除，返还金币）=====
    function sell(uid) {
        const save = S().get();
        const idx = (save.relics || []).findIndex(r => r.uid === uid);
        if (idx === -1) return { success: false, error: '遗物不存在' };
        const relic = save.relics[idx];

        // 先自动卸下（若已装备）
        if (relic.equippedBy) {
            const charSave = save.ownedCharacters?.[relic.equippedBy];
            if (charSave?.equippedRelics) charSave.equippedRelics[relic.slotId] = null;
        }

        // 计算分解金币
        const gold = ({ 3: 50, 4: 200, 5: 800 }[relic.rarity] || 50) + relic.level * 20;
        save.relics.splice(idx, 1);
        save.resources = save.resources || {};
        save.resources.gold = (save.resources.gold || 0) + gold;
        S().save();
        window.GG.EventBus.emit('resource:changed', 'gold', save.resources.gold);
        return { success: true, gold };
    }

    // ===== 批量分解 =====
    function batchSell(options = {}) {
        const save = S().get();
        const all = save.relics || [];
        const targets = all.filter(r => {
            const is3 = !!options.all3Star && r.rarity === 3;
            const is4 = !!options.all4Star && r.rarity === 4;
            const isUnupgraded = !!options.allUnupgraded && r.level === 0;
            return is3 || is4 || isUnupgraded;
        });

        if (!targets.length) return { success: false, error: '没有符合条件的遗物', count: 0, gold: 0 };

        let totalGold = 0;
        targets.forEach(r => {
            if (r.equippedBy) {
                const charSave = save.ownedCharacters?.[r.equippedBy];
                if (charSave?.equippedRelics) charSave.equippedRelics[r.slotId] = null;
            }
            totalGold += ({ 3: 50, 4: 200, 5: 800 }[r.rarity] || 50) + r.level * 20;
        });

        const uids = new Set(targets.map(r => r.uid));
        save.relics = all.filter(r => !uids.has(r.uid));
        save.resources = save.resources || {};
        save.resources.gold = (save.resources.gold || 0) + totalGold;
        S().save();
        window.GG.EventBus.emit('resource:changed', 'gold', save.resources.gold);

        return { success: true, count: targets.length, gold: totalGold };
    }

    return {
        generate, upgrade, upgradeToMax, getUpgradeCostToMax, equip, unequip,
        getEquippedBonuses, getInventory, getEquippedRelics,
        getMainStatValue, addToInventory, sell, batchSell
    };
})();
