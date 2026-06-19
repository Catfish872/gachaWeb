// 章节五星角色赠送系统 —— 每章倒数第二关首次完成时赠送对应五星角色
// 赠送规则（已确认）：
//   - 首次未拥有：直接获得角色本体（命座0）
//   - 已拥有：转化为 25 碎片（5星重复碎片量，与抽卡一致）
//   - 命座突破仍受 6 阶上限约束（由 ConstellationSystem.unlock 的 currentLevel>=6 拦截保证）
//   - 每存档每章仅赠送一次（chapterGiftClaimed 记录）
window.GG = window.GG || {};
window.GG.ChapterGiftSystem = (function () {
    const S = () => window.GG.SaveSystem;
    const EB = () => window.GG.EventBus;
    const CP = () => window.GG.CharacterProgression;

    // 章节赠送映射表：新增章节只需在此追加一条
    // stageBeforeLast 表示该章倒数第二关的 stageId（赠送触发关卡）
    const CHAPTER_GIFT_MAP = {
        'ch1': { charId: 'kaldi', stageBeforeLast: 'ch1_4' },
        'ch2': { charId: 'ayla', stageBeforeLast: 'ch2_4' },
        // ========== 未来章节扩展预留 ==========
        // 'ch3': { charId: 'xxx', stageBeforeLast: 'ch3_4' },
    };

    // 5星角色重复获得的碎片数量（与抽卡保持一致）
    const SHARD_AMOUNT_FOR_DUP_5STAR = 25;

    // 获取某关卡所在章节与索引
    function _locateStage(stageId) {
        const chapters = window.GG.StageData?.chapters || [];
        for (const ch of chapters) {
            const idx = ch.stages.findIndex(s => s.id === stageId);
            if (idx !== -1) return { chapter: ch, index: idx };
        }
        return null;
    }

    // 判断某关卡是否为其所在章节的"倒数第二关"
    function isSecondToLastStage(stageId) {
        const loc = _locateStage(stageId);
        if (!loc) return false;
        const stages = loc.chapter.stages || [];
        // 至少需要 2 关，且该关为倒数第二个
        return stages.length >= 2 && loc.index === stages.length - 2;
    }

    // 获取某关卡对应章节的赠送配置（若该章节有赠送）
    function getGiftConfigForStage(stageId) {
        const loc = _locateStage(stageId);
        if (!loc) return null;
        const cfg = CHAPTER_GIFT_MAP[loc.chapter.id];
        if (!cfg) return null;
        // 必须是该章的倒数第二关，且配置的 stageBeforeLast 与当前关卡一致
        if (!isSecondToLastStage(stageId)) return null;
        if (cfg.stageBeforeLast && cfg.stageBeforeLast !== stageId) return null;
        const char = window.GG.CharacterData?.[cfg.charId];
        return {
            chapterId: loc.chapter.id,
            charId: cfg.charId,
            charName: char?.name || cfg.charId,
            rarity: char?.rarity || 5,
        };
    }

    // 查询某章节赠送是否已领取
    function isClaimed(chapterId) {
        const save = S().get();
        return !!save.chapterGiftClaimed?.[chapterId]?.claimed;
    }

    // 核心赠送逻辑：返回赠送结果（供调用方做 UI 反馈）
    // 仅执行实际发放，不负责触发条件判定（调用方应先确保为倒数第二关且首次完成）
    function _grant(giftConfig) {
        const save = S().get();
        const { chapterId, charId, charName, rarity } = giftConfig;
        const owned = save.ownedCharacters || (save.ownedCharacters = {});
        let result;

        if (!owned[charId]) {
            // 首次未拥有：直接获得本体（命座0）
            // 数据结构保持与抽卡、存档迁移一致
            owned[charId] = {
                ...(CP()?.createDefaultProgress?.() || { level: 1, exp: 0 }),
                shards: 0,
                constellation: 0,
                awakening: 0,
                breakthroughLevel: 0,
                equippedRelics: {},
            };
            result = { isNew: true, shardsGained: 0, charName };
        } else {
            // 已拥有：转化为碎片（5星25片）
            const shardAmt = rarity === 5 ? SHARD_AMOUNT_FOR_DUP_5STAR : (rarity === 4 ? 5 : 1);
            owned[charId].shards = (owned[charId].shards || 0) + shardAmt;
            result = { isNew: false, shardsGained: shardAmt, charName };
        }

        // 写入领取记录
        save.chapterGiftClaimed = save.chapterGiftClaimed || {};
        save.chapterGiftClaimed[chapterId] = {
            claimed: true,
            charId,
            date: Date.now(),
        };
        S().save();

        EB().emit('chapter:gift_granted', { chapterId, charId, ...result });
        return result;
    }

    // 主入口：检测关卡是否符合赠送条件并执行赠送
    // 返回 null 表示未触发赠送，否则返回赠送结果
    function checkAndGrant(stageId) {
        const giftConfig = getGiftConfigForStage(stageId);
        if (!giftConfig) return null;                       // 非赠送关卡
        if (isClaimed(giftConfig.chapterId)) return null;   // 该存档已领取
        return _grant(giftConfig);
    }

    // 对外提供查询接口（供 UI/对话系统判断是否为赠送时刻）
    return {
        checkAndGrant,
        isSecondToLastStage,
        getGiftConfigForStage,
        isClaimed,
        CHAPTER_GIFT_MAP,
    };
})();