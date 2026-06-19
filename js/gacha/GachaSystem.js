// 抽卡主系统
window.GG = window.GG || {};
window.GG.GachaSystem = (function () {
    const Pity = () => window.GG.PitySystem;
    const S = () => window.GG.SaveSystem;
    const EB = () => window.GG.EventBus;
    const Pools = () => window.GG.GachaPoolData;
    const CharData = () => window.GG.CharacterData || {};

    let _poolValidated = false;

    function _getAllCharIdsByRarity(rarity) {
        return Object.values(CharData())
            .filter(c => c && c.rarity === rarity)
            .map(c => c.id);
    }

    function _sanitizeCandidates(candidates, rarity) {
        const list = Array.isArray(candidates) ? candidates : [];
        return list.filter(id => CharData()[id]?.rarity === rarity);
    }

    function _validateIdsByRarity(poolId, key, rarity) {
        const pool = Pools().pools?.[poolId];
        const list = pool?.[key];
        if (!Array.isArray(list)) return [];
        return list.filter(id => CharData()[id]?.rarity !== rarity);
    }

    function validatePools() {
        const pools = Pools().pools || {};
        Object.keys(pools).forEach(poolId => {
            const bad5 = [..._validateIdsByRarity(poolId, 'pool5', 5), ..._validateIdsByRarity(poolId, 'featured5', 5)];
            const bad4 = [..._validateIdsByRarity(poolId, 'pool4', 4), ..._validateIdsByRarity(poolId, 'featured4', 4)];
            const bad3 = [..._validateIdsByRarity(poolId, 'pool3', 3), ..._validateIdsByRarity(poolId, 'featured3', 3)];
            const invalidIds = [...new Set([...bad5, ...bad4, ...bad3])];

            pools[poolId].__invalid = invalidIds.length > 0;
            if (invalidIds.length > 0) {
                console.error(`[GachaSystem] 卡池配置错误(${poolId})：以下角色稀有度与池子不匹配`, invalidIds);
            }
        });
    }

    function ensurePoolValidation() {
        if (_poolValidated) return;
        validatePools();
        _poolValidated = true;
    }

    // 从池中随机选一个角色
    function pickFromPool(pool, rarity, isFeatured) {
        let candidates;
        if (rarity === 5) {
            candidates = isFeatured && pool.featured5?.length ? pool.featured5 : pool.pool5;
        } else if (rarity === 4) {
            candidates = isFeatured && pool.featured4?.length ? pool.featured4 : pool.pool4;
        } else {
            candidates = pool.pool3;
        }

        const validCandidates = _sanitizeCandidates(candidates, rarity);
        const fallback = _getAllCharIdsByRarity(rarity);
        const finalPool = validCandidates.length ? validCandidates : fallback;
        if (!finalPool.length) return null;
        return finalPool[Math.floor(Math.random() * finalPool.length)];
    }

    // 执行一次抽卡（返回单次结果）
    function pullOne(poolId) {
        ensurePoolValidation();
        const poolConfig = Pools().pools[poolId];
        if (!poolConfig || poolConfig.__invalid) return null;

        const rarity = Pity().rollRarity(poolId, poolConfig);
        let isFeatured = false;
        if (rarity === 5) {
            isFeatured = Pity().resolve5StarFeatured(poolId, poolConfig);
        } else if (rarity === 4) {
            isFeatured = Math.random() < (poolConfig.featuredRate4 || 0.5);
        }
        const charId = pickFromPool(poolConfig, rarity, isFeatured);
        if (!charId) return null;
        return { charId, rarity, isFeatured };
    }

    // 执行N连抽（扣费 + 批量抽）
    function pull(poolId, count = 1) {
        ensurePoolValidation();
        const poolConfig = Pools().pools[poolId];
        if (!poolConfig) return { success: false, error: '卡池不存在' };
        if (poolConfig.__invalid) return { success: false, error: '卡池配置异常，已临时关闭该卡池' };

        const cost = poolConfig.costPerPull * count;
        const currency = poolConfig.currency || 'diamonds';
        if (!S().modifyResource(currency, -cost)) {
            return { success: false, error: `${currency === 'diamonds' ? '星尘晶' : '货币'}不足` };
        }

        const results = [];
        for (let i = 0; i < count; i++) {
            const result = pullOne(poolId);
            if (result) results.push(result);
        }

        // 添加到角色收藏（重复角色给碎片）
        const save = S().get();
        results.forEach(r => {
            if (!save.ownedCharacters[r.charId]) {
                save.ownedCharacters[r.charId] = {
                    ...(window.GG.CharacterProgression?.createDefaultProgress?.() || { level: 1, exp: 0 }),
                    shards: 0,
                    breakthroughLevel: 0,
                    awakening: 0,
                };
            } else {
                // 重复：给碎片
                const shardAmt = r.rarity === 5 ? 25 : r.rarity === 4 ? 5 : 1;
                save.ownedCharacters[r.charId].shards += shardAmt;
            }
        });

        // 更新统计
        save.stats = save.stats || {};
        save.stats.totalPulls = (save.stats.totalPulls || 0) + count;
        S().save();

        EB().emit('gacha:pulled', poolId, results);
        return { success: true, results, cost };
    }

    // 单抽
    function pullSingle(poolId) { return pull(poolId, 1); }
    // 十连
    function pullTen(poolId) { return pull(poolId, 10); }

    // 获取卡池当前保底信息
    function getPityInfo(poolId) {
        ensurePoolValidation();
        const poolConfig = Pools().pools[poolId];
        if (!poolConfig || poolConfig.__invalid) return null;
        const pityData = Pity().getPityData(poolId);
        return {
            count: pityData.count,
            hard: poolConfig.pity.hard,
            guaranteedFeatured: pityData.guaranteedFeatured,
            rate5: Pity().getActual5StarRate(poolId, poolConfig),
        };
    }

    return { pull, pullSingle, pullTen, getPityInfo };
})();
