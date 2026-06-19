// 角色属性计算模块
// 负责根据角色数据、等级、觉醒等计算最终属性
window.GG = window.GG || {};
window.GG.CharacterStats = (function () {
    const CD = () => window.GG.CharacterData;

    // 计算某个角色实际等级下的属性（含命座/遗物加成）
    function computeStats(charId, level = 1, awakening = 0) {
        const data = CD()[charId];
        if (!data) return null;
        const base = data.baseStats;
        const growth = data.growthRate;

        // 基础成长（等级上限由经验系统控制，默认 10）
        const maxLv = window.GG.CharacterProgression?.MAX_LEVEL || 10;
        const lv = Math.max(1, Math.min(level, maxLv));
        const growthHp = Math.floor(base.hp + growth.hp * (lv - 1));
        const growthAtk = Math.floor(base.atk + growth.atk * (lv - 1));
        const growthDef = Math.floor(base.def + growth.def * (lv - 1));
        const growthSpd = base.spd;

        // 每级相对上一级 +10%（只作用于基础属性，不含命座/遗物）
        const baseMult = Math.pow(1.1, lv - 1);
        const hp = Math.floor(growthHp * baseMult);
        const atk = Math.floor(growthAtk * baseMult);
        const def = Math.floor(growthDef * baseMult);
        const spd = Math.floor(growthSpd * baseMult);
        const baseCri = base.cri * baseMult;
        const baseCriDmg = base.criDmg * baseMult;

        // 觉醒加成（每阶 +5%）
        const awakeningMult = 1 + awakening * 0.05;

        // 命座加成
        const cst = window.GG.ConstellationSystem?.getBonuses(charId) || {};
        const hpPct = (cst.hpPercent || 0) + (awakeningMult - 1);
        const atkPct = cst.atkPercent || 0;
        const defPct = cst.defPercent || 0;

        // 遗物加成
        const rb = window.GG.RelicSystem?.getEquippedBonuses(charId) || {};

        const finalHp = Math.floor((hp * (1 + hpPct) + (rb.hp_flat || 0)) * (1 + (rb.hp_pct || 0)));
        const finalAtk = Math.floor((atk * (1 + atkPct) + (rb.atk_flat || 0)) * (1 + (rb.atk_pct || 0)));
        const finalDef = Math.floor((def * (1 + defPct) + (rb.def_flat || 0)) * (1 + (rb.def_pct || 0)));
        const finalSpd = spd + (rb.spd || 0);
        const finalCri = Math.min(1.0, baseCri + (rb.cri_rate || 0));
        const finalCriDmg = baseCriDmg + (rb.cri_dmg || 0);

        return {
            maxHp: Math.max(1, finalHp),
            atk: Math.max(1, finalAtk),
            def: Math.max(0, finalDef),
            spd: finalSpd,
            cri: finalCri,
            criDmg: finalCriDmg,
            // 保存命座技能加成供 SkillSystem 使用
            normalDmgBonus: cst.normalDmgBonus || 0,
            skillDmgBonus: cst.skillDmgBonus || 0,
            ultDmgBonus: cst.ultDmgBonus || 0,
            skillCdReduce: cst.skillCdReduce || 0,
        };
    }

    // 元素克制表
    const ELEMENT_ADVANTAGE = {
        fire: { strong: 'wind', weak: 'water' },
        water: { strong: 'fire', weak: 'thunder' },
        wind: { strong: 'thunder', weak: 'fire' },
        thunder: { strong: 'water', weak: 'wind' },
    };

    // 计算元素克制系数
    function getElementMult(attackerElement, defenderElement) {
        if (!attackerElement || !defenderElement) return 1.0;
        const adv = ELEMENT_ADVANTAGE[attackerElement];
        if (!adv) return 1.0;
        if (adv.strong === defenderElement) return 1.5;
        if (adv.weak === defenderElement) return 0.75;
        return 1.0;
    }

    // 核心伤害公式
    // damage = ATK × multiplier × (100 / (100 + DEF×defPierceMult)) × elementMult × critMult
    function calcDamage({ atk, multiplier = 1.0, def, cri, criDmg, defPierce = 0, attackerElement, defenderElement }) {
        const isCrit = Math.random() < cri;
        const critMult = isCrit ? criDmg : 1.0;
        const effectiveDef = def * (1 - defPierce);
        const defReduction = 100 / (100 + effectiveDef);
        const elementMult = getElementMult(attackerElement, defenderElement);
        const raw = atk * multiplier * defReduction * elementMult * critMult;
        return {
            damage: Math.max(1, Math.floor(raw)),
            isCrit,
            elementMult,
        };
    }

    // 计算治愈量
    function calcHeal({ atk, multiplier = 1.0 }) {
        return Math.max(1, Math.floor(atk * multiplier));
    }

    return {
        computeStats,
        getElementMult,
        calcDamage,
        calcHeal,
        ELEMENT_ADVANTAGE,
    };
})();
