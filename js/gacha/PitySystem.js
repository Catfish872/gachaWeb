// 保底系统 — 管理每个卡池的抽卡计数和大保底状态
window.GG = window.GG || {};
window.GG.PitySystem = (function () {
    const S = () => window.GG.SaveSystem;

    // 获取某个卡池的保底计数
    function getPityData(poolId) {
        const save = S().get();
        if (!save.pityCounters) save.pityCounters = {};
        if (!save.pityCounters[poolId]) {
            save.pityCounters[poolId] = { count: 0, count4: 0, guaranteedFeatured: false };
        }
        return save.pityCounters[poolId];
    }

    // 计算当前五星实际概率（考虑软保底）
    function getActual5StarRate(poolId, poolConfig) {
        const pity = getPityData(poolId);
        const { soft, hard, softIncrease } = poolConfig.pity;
        const base = poolConfig.rates[5] || 0.016;
        if (pity.count < soft) return base;
        return Math.min(1.0, base + (pity.count - soft + 1) * softIncrease);
    }

    // 计算当前四星实际概率（10连必有四星：连续9抽没四星则第10抽必出）
    function getActual4StarRate(poolId, poolConfig) {
        const pity = getPityData(poolId);
        if (pity.count4 >= 9) return 1.0; // 软保底：10连内必有四星
        return poolConfig.rates[4] || 0.15;
    }

    // 执行一次概率抽取（返回稀有度：3/4/5）
    function rollRarity(poolId, poolConfig) {
        const pity = getPityData(poolId);
        const rate5 = getActual5StarRate(poolId, poolConfig);
        const rate4 = getActual4StarRate(poolId, poolConfig);

        // 硬保底
        if (pity.count >= poolConfig.pity.hard - 1) {
            incrementCount(poolId, 5);
            return 5;
        }

        const roll = Math.random();
        if (roll < rate5) {
            incrementCount(poolId, 5);
            return 5;
        } else if (roll < rate5 + rate4) {
            incrementCount(poolId, 4);
            return 4;
        } else {
            incrementCount(poolId, 3);
            return 3;
        }
    }

    // 确定五星是否为 UP 角色（大保底逻辑）
    function resolve5StarFeatured(poolId, poolConfig) {
        if (!poolConfig.guaranteedFeatured) {
            // 常驻池：50%概率出 featured，50%出常驻
            return Math.random() < (poolConfig.featuredRate5 || 0.5);
        }
        const pity = getPityData(poolId);
        if (pity.guaranteedFeatured) {
            // 大保底：必出 UP
            pity.guaranteedFeatured = false;
            S().save();
            return true;
        }
        const isFeatured = Math.random() < (poolConfig.featuredRate5 || 0.5);
        if (!isFeatured) {
            // 本次没出 UP，下次大保底
            pity.guaranteedFeatured = true;
            S().save();
        }
        return isFeatured;
    }

    function incrementCount(poolId, gotRarity) {
        const pity = getPityData(poolId);
        if (gotRarity === 5) {
            pity.count = 0;
            pity.count4 = 0;
        } else if (gotRarity === 4) {
            pity.count++;
            pity.count4 = 0;
        } else {
            pity.count++;
            pity.count4++;
        }
        S().save();
    }

    return {
        getPityData,
        getActual5StarRate,
        getActual4StarRate,
        rollRarity,
        resolve5StarFeatured,
    };
})();
