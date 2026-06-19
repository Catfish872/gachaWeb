// 命座系统 — 解锁/查询/属性加成计算
window.GG = window.GG || {};
window.GG.ConstellationSystem = (function () {
    const S = () => window.GG.SaveSystem;
    const Generic = () => window.GG.ConstellationGeneric;
    const C6Data = () => window.GG.ConstellationC6;
    const CostData = () => window.GG.ConstellationCost;
    const CharData = () => window.GG.CharacterData;

    // 获取角色当前命座等级（0~6）
    function getLevel(charId) {
        const save = S().get();
        return save.ownedCharacters?.[charId]?.constellation || 0;
    }

    // 获取角色当前碎片数
    function getShards(charId) {
        const save = S().get();
        return save.ownedCharacters?.[charId]?.shards || 0;
    }

    // 解锁下一阶命座（消耗碎片）
    function unlock(charId) {
        const save = S().get();
        const charSave = save.ownedCharacters?.[charId];
        if (!charSave) return { success: false, error: '未拥有该角色' };

        const rarity = CharData()[charId]?.rarity || 3;
        const currentLevel = charSave.constellation || 0;
        if (currentLevel >= 6) return { success: false, error: '已达最高命座' };

        const cost = CostData()[rarity][currentLevel];
        if ((charSave.shards || 0) < cost) {
            return { success: false, error: `碎片不足（需要 ${cost} 片，当前 ${charSave.shards || 0} 片）` };
        }

        charSave.shards -= cost;
        charSave.constellation = currentLevel + 1;
        S().save();

        window.GG.EventBus.emit('constellation:unlocked', charId, charSave.constellation);
        return { success: true, newLevel: charSave.constellation };
    }

    // 获取角色所有命座信息（含解锁状态）
    function getConstellationInfo(charId) {
        const rarity = CharData()[charId]?.rarity || 3;
        const level = getLevel(charId);
        const shards = getShards(charId);
        const costs = CostData()[rarity];
        const c6 = C6Data()[charId] || { label: '命运之星', desc: '专属效果（待实装）', buff: {} };

        return Generic().map((g, i) => ({
            index: i,
            level: i + 1,
            label: i === 5 ? c6.label : g.label,
            desc: i === 5 ? c6.desc : g.desc,
            buff: i === 5 ? c6.buff : g.buff,
            cost: costs[i],
            unlocked: level > i,
            isNext: level === i, // 下一个可解锁
            canUnlock: level === i && shards >= costs[i],
        }));
    }

    // 计算命座带来的属性加成（返回加成对象，由 CharacterStats 合并）
    function getBonuses(charId) {
        const level = getLevel(charId);
        const bonuses = {
            hpPercent: 0, defPercent: 0, atkPercent: 0,
            normalDmgBonus: 0, skillDmgBonus: 0, ultDmgBonus: 0,
            skillCdReduce: 0,
            custom: {},  // C6 专属效果标记
        };
        if (level === 0) return bonuses;

        Generic().slice(0, level).forEach((g, i) => {
            const buff = i === 5
                ? (window.GG.ConstellationC6[charId]?.buff || {})
                : g.buff;
            if (buff.hpPercent) bonuses.hpPercent += buff.hpPercent;
            if (buff.defPercent) bonuses.defPercent += buff.defPercent;
            if (buff.atkPercent) bonuses.atkPercent += buff.atkPercent;
            if (buff.normalDmgBonus) bonuses.normalDmgBonus += buff.normalDmgBonus;
            if (buff.skillDmgBonus) bonuses.skillDmgBonus += buff.skillDmgBonus;
            if (buff.ultDmgBonus) bonuses.ultDmgBonus += buff.ultDmgBonus;
            if (buff.skillCdReduce) bonuses.skillCdReduce += buff.skillCdReduce;
            if (buff.c6_type) bonuses.custom = buff; // C6
        });
        return bonuses;
    }

    // 获取下阶解锁费用（-1 表示已满级）
    function getNextCost(charId) {
        const rarity = CharData()[charId]?.rarity || 3;
        const level = getLevel(charId);
        if (level >= 6) return -1;
        return CostData()[rarity][level];
    }

    return { getLevel, getShards, unlock, getConstellationInfo, getBonuses, getNextCost };
})();
