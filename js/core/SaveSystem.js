// 存档系统 — localStorage 多槽位 + 本地导入导出
// 结构化存档，支持版本迁移
window.GG = window.GG || {};
window.GG.SaveSystem = (function () {
    const LEGACY_SAVE_KEY = 'GachaGame_Save_v2';
    const SAVE_KEY_PREFIX = 'GachaGame_Save_v3_';
    const META_KEY = 'GachaGame_Save_meta_v3';
    const CURRENT_VERSION = 3;
    const SLOT_IDS = ['slot1', 'slot2', 'slot3'];

    function _slotKey(slotId) {
        return `${SAVE_KEY_PREFIX}${slotId}`;
    }

    // 默认存档（新玩家初始状态）
    function createDefaultSave() {
        return {
            version: CURRENT_VERSION,
            createdAt: Date.now(),
            lastSaved: Date.now(),

            // 资源
            resources: {
                diamonds: 1600,  // 初始给1600（可以十连一次）
                gold: 50000,
                stamina: 100,
                staminaLastUpdate: Date.now(),
            },

            // 已拥有角色列表 { charId: { level, exp, shards, constellation, awakening, equippedRelics } }
            ownedCharacters: {
                'ember': { level: 1, exp: 0, shards: 3, constellation: 0, awakening: 0, equippedRelics: {} },
                'zeph': { level: 1, exp: 0, shards: 1, constellation: 0, awakening: 0, equippedRelics: {} },
            },

            // 遗物背包（所有遗物对象的数组）
            relics: [],

            // 队伍配置（3个槽位）
            team: ['ember', 'zeph', null],

            // 关卡进度 { stageId: { cleared, stars, bestTurns } }
            stageProgress: {},

            // 抽卡保底计数 { poolId: { count, guaranteedFeatured } }
            pityCounters: {
                standard: { count: 0, count4: 0, guaranteedFeatured: false },
                limited_kaldi: { count: 0, count4: 0, guaranteedFeatured: false },
            },

            // 每日任务进度（预留接口）
            dailyMissions: { lastReset: 0, completed: [] },

            // 统计数据
            stats: {
                totalPulls: 0,
                totalBattles: 0,
                totalVictories: 0,
                totalGoldSpent: 0,
            },

            // 已读剧情记录 { 'ch1_1_pre': true, ... }，用于区分首次/重复阅读
            dialogueSeen: {},

            // 章节五星角色赠送记录 { 'ch1': { claimed: true, charId: 'kaldi', date: 0 } }
            // 每存档每章仅赠送一次
            chapterGiftClaimed: {},
        };
    }

    function _createDefaultMeta() {
        const slots = {};
        SLOT_IDS.forEach((id, i) => {
            slots[id] = {
                id,
                name: `存档${i + 1}`,
                createdAt: 0,
                lastSaved: 0,
                hasData: false,
            };
        });
        return {
            activeSlot: 'slot1',
            slots,
            migratedLegacy: false,
        };
    }

    function _loadMeta() {
        try {
            const raw = localStorage.getItem(META_KEY);
            const base = _createDefaultMeta();
            if (!raw) return base;
            const parsed = JSON.parse(raw);
            const merged = {
                ...base,
                ...(parsed || {}),
                slots: { ...base.slots, ...(parsed?.slots || {}) },
            };
            if (!SLOT_IDS.includes(merged.activeSlot)) merged.activeSlot = 'slot1';
            SLOT_IDS.forEach((id, i) => {
                merged.slots[id] = {
                    id,
                    name: `存档${i + 1}`,
                    createdAt: 0,
                    lastSaved: 0,
                    hasData: false,
                    ...(merged.slots[id] || {}),
                };
            });
            return merged;
        } catch (e) {
            console.warn('[SaveSystem] 读取元信息失败，重置为默认值', e);
            return _createDefaultMeta();
        }
    }

    function _saveMeta(meta) {
        try {
            localStorage.setItem(META_KEY, JSON.stringify(meta));
        } catch (e) {
            console.error('[SaveSystem] 保存元信息失败', e);
        }
    }

    function _normalizeSave(parsed) {
        if (!parsed || typeof parsed !== 'object') return createDefaultSave();
        const merged = { ...createDefaultSave(), ...parsed, version: CURRENT_VERSION };
        merged.resources = { ...createDefaultSave().resources, ...(parsed.resources || {}) };
        merged.stats = { ...createDefaultSave().stats, ...(parsed.stats || {}) };
        merged.pityCounters = { ...createDefaultSave().pityCounters, ...(parsed.pityCounters || {}) };
        merged.ownedCharacters = parsed.ownedCharacters || createDefaultSave().ownedCharacters;
        const CP = window.GG.CharacterProgression;
        Object.values(merged.ownedCharacters || {}).forEach(charSave => {
            if (!charSave || typeof charSave !== 'object') return;
            if (typeof charSave.level !== 'number' || !Number.isFinite(charSave.level)) charSave.level = 1;
            if (typeof charSave.exp !== 'number' || !Number.isFinite(charSave.exp)) charSave.exp = 0;
            CP?.normalizeCharacterProgress?.(charSave);
        });
        merged.relics = Array.isArray(parsed.relics) ? parsed.relics : [];
        merged.team = Array.isArray(parsed.team) ? parsed.team : createDefaultSave().team;
        merged.stageProgress = parsed.stageProgress || {};
        // 剧情对话已读记录 / 章节赠送记录（旧存档迁移补齐默认值）
        merged.dialogueSeen = (parsed.dialogueSeen && typeof parsed.dialogueSeen === 'object') ? parsed.dialogueSeen : {};
        merged.chapterGiftClaimed = (parsed.chapterGiftClaimed && typeof parsed.chapterGiftClaimed === 'object') ? parsed.chapterGiftClaimed : {};
        return merged;
    }

    function _safeParseSave(raw) {
        try {
            return _normalizeSave(JSON.parse(raw));
        } catch (e) {
            return null;
        }
    }

    function _touchSlotMeta(meta, slotId, saveObj) {
        if (!meta.slots[slotId]) meta.slots[slotId] = { id: slotId, name: slotId, createdAt: 0, lastSaved: 0, hasData: false };
        meta.slots[slotId].hasData = true;
        meta.slots[slotId].createdAt = saveObj.createdAt || Date.now();
        meta.slots[slotId].lastSaved = saveObj.lastSaved || Date.now();
    }

    function _buildExportPayload(slotId, saveObj) {
        return {
            game: 'void-rift-gacha',
            schema: CURRENT_VERSION,
            slotId,
            exportedAt: Date.now(),
            data: saveObj,
        };
    }

    function _downloadTextFile(filename, text) {
        const blob = new Blob([text], { type: 'application/json;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 500);
    }

    let _save = null;
    let _activeSlot = 'slot1';

    return {
        // 加载存档（游戏初始化时调用）
        load(slotId) {
            const meta = _loadMeta();
            if (slotId && SLOT_IDS.includes(slotId)) meta.activeSlot = slotId;
            _activeSlot = meta.activeSlot;

            // 兼容旧版单存档：首次迁移到 slot1
            if (!meta.migratedLegacy) {
                const oldRaw = localStorage.getItem(LEGACY_SAVE_KEY);
                const slot1Raw = localStorage.getItem(_slotKey('slot1'));
                if (oldRaw && !slot1Raw) {
                    localStorage.setItem(_slotKey('slot1'), oldRaw);
                }
                meta.migratedLegacy = true;
                _saveMeta(meta);
            }

            try {
                const raw = localStorage.getItem(_slotKey(_activeSlot));
                if (raw) {
                    const parsed = JSON.parse(raw);
                    _save = _normalizeSave(parsed);
                    if ((parsed.version || 0) < CURRENT_VERSION) this.save();
                } else {
                    _save = createDefaultSave();
                    this.save();
                }
            } catch (e) {
                console.warn('[SaveSystem] 读取存档失败，重置为默认值', e);
                _save = createDefaultSave();
                this.save();
            }

            const meta2 = _loadMeta();
            _touchSlotMeta(meta2, _activeSlot, _save);
            meta2.activeSlot = _activeSlot;
            _saveMeta(meta2);

            return _save;
        },

        // 保存（写入 localStorage）
        save() {
            if (!_save) return;
            _save.lastSaved = Date.now();
            try {
                localStorage.setItem(_slotKey(_activeSlot), JSON.stringify(_save));
                const meta = _loadMeta();
                meta.activeSlot = _activeSlot;
                _touchSlotMeta(meta, _activeSlot, _save);
                _saveMeta(meta);
            } catch (e) {
                console.error('[SaveSystem] 保存失败', e);
            }
        },

        // 获取当前存档对象（引用，直接修改后调用 save()）
        get() { return _save; },

        getActiveSlot() { return _activeSlot; },

        listSlots() {
            const meta = _loadMeta();
            return SLOT_IDS.map(id => {
                const m = meta.slots[id] || {};
                const raw = localStorage.getItem(_slotKey(id));
                const parsed = raw ? _safeParseSave(raw) : null;
                return {
                    id,
                    name: m.name || id,
                    isActive: id === meta.activeSlot,
                    hasData: !!(m.hasData || parsed),
                    createdAt: m.createdAt || parsed?.createdAt || 0,
                    lastSaved: m.lastSaved || parsed?.lastSaved || 0,
                    totalPulls: parsed?.stats?.totalPulls || 0,
                    totalVictories: parsed?.stats?.totalVictories || 0,
                    ownedCount: Object.keys(parsed?.ownedCharacters || {}).length,
                };
            });
        },

        switchSlot(slotId) {
            if (!SLOT_IDS.includes(slotId)) return { success: false, error: '无效存档槽位' };
            this.save();
            this.load(slotId);
            window.GG.EventBus?.emit?.('resource:changed', 'diamonds', _save?.resources?.diamonds || 0);
            window.GG.EventBus?.emit?.('resource:changed', 'gold', _save?.resources?.gold || 0);
            window.GG.EventBus?.emit?.('resource:changed', 'stamina', _save?.resources?.stamina || 0);
            return { success: true, slotId };
        },

        // 重置当前槽位（慎用）
        reset() {
            _save = createDefaultSave();
            this.save();
            return _save;
        },

        // 重置指定槽位
        resetSlot(slotId = _activeSlot) {
            if (!SLOT_IDS.includes(slotId)) return { success: false, error: '无效存档槽位' };
            const saveObj = createDefaultSave();
            try {
                localStorage.setItem(_slotKey(slotId), JSON.stringify(saveObj));
                const meta = _loadMeta();
                _touchSlotMeta(meta, slotId, saveObj);
                _saveMeta(meta);
                if (slotId === _activeSlot) _save = saveObj;
                return { success: true };
            } catch (e) {
                return { success: false, error: '重置失败' };
            }
        },

        exportSlot(slotId = _activeSlot) {
            if (!SLOT_IDS.includes(slotId)) return { success: false, error: '无效存档槽位' };
            const raw = localStorage.getItem(_slotKey(slotId));
            const saveObj = raw ? _safeParseSave(raw) : _save;
            if (!saveObj) return { success: false, error: '该槽位没有可导出的存档' };
            const payload = _buildExportPayload(slotId, saveObj);
            const date = new Date(payload.exportedAt);
            const pad = (n) => String(n).padStart(2, '0');
            const stamp = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}`;
            _downloadTextFile(`voidrift_${slotId}_${stamp}.json`, JSON.stringify(payload, null, 2));
            return { success: true };
        },

        async importSlotFile(file, slotId = _activeSlot) {
            if (!SLOT_IDS.includes(slotId)) return { success: false, error: '无效存档槽位' };
            if (!file) return { success: false, error: '未选择文件' };
            try {
                const text = await file.text();
                const parsed = JSON.parse(text);
                const saveData = parsed?.data && typeof parsed.data === 'object' ? parsed.data : parsed;
                const normalized = _normalizeSave(saveData);
                normalized.lastSaved = Date.now();

                localStorage.setItem(_slotKey(slotId), JSON.stringify(normalized));
                const meta = _loadMeta();
                _touchSlotMeta(meta, slotId, normalized);
                _saveMeta(meta);

                if (slotId === _activeSlot) {
                    _save = normalized;
                    window.GG.EventBus?.emit?.('resource:changed', 'diamonds', _save?.resources?.diamonds || 0);
                    window.GG.EventBus?.emit?.('resource:changed', 'gold', _save?.resources?.gold || 0);
                    window.GG.EventBus?.emit?.('resource:changed', 'stamina', _save?.resources?.stamina || 0);
                }

                return { success: true };
            } catch (e) {
                console.error('[SaveSystem] 导入存档失败', e);
                return { success: false, error: '文件格式不正确或导入失败' };
            }
        },

        // 兼容旧接口：不再弹浏览器原生确认框，直接执行导出
        promptBackupOnLogin() {
            const r = this.exportSlot(_activeSlot);
            return { prompted: true, exported: !!r?.success };
        },

        // 获取资源
        getResource(key) { return _save?.resources[key] ?? 0; },

        // 修改资源（支持负数消耗，返回是否成功）
        modifyResource(key, delta) {
            if (!_save) return false;
            const current = _save.resources[key] ?? 0;
            if (delta < 0 && current + delta < 0) return false; // 资源不足
            _save.resources[key] = current + delta;
            this.save();
            window.GG.EventBus.emit('resource:changed', key, _save.resources[key]);
            return true;
        },

        // 设置资源（直接设值）
        setResource(key, value) {
            if (!_save) return;
            _save.resources[key] = value;
            this.save();
            window.GG.EventBus.emit('resource:changed', key, value);
        },
    };
})();
