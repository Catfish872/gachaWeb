// 养成界面 — 命座 + 遗物管理
window.GG = window.GG || {};
window.GG.GrowthUI = (function () {
    const S = () => window.GG.SaveSystem;
    const CS = () => window.GG.ConstellationSystem;
    const RS = () => window.GG.RelicSystem;
    const CD = () => window.GG.CharacterData;
    const EB = () => window.GG.EventBus;
    const RC = () => window.GG.RarityConfig;
    const Slots = () => window.GG.RelicSlots;
    const CP = () => window.GG.CharacterProgression;

    let _currentCharId = null;
    let _relicFilterSlot = null;
    let _eventsRegistered = false; // Bug1修复：防止重复注册事件
    let _initialized = false;       // Bug4修复：首次才全量渲染
    const RELIC_BATCH_PREF_KEY = 'gg_relic_batch_pref_v1';

    // ===== 打开养成页 =====
    function open() {
        const page = document.getElementById('page-growth');
        if (!page) return;
        page.style.display = 'block';

        if (!_eventsRegistered) {
            _bindEvents();
            _eventsRegistered = true;
        }

        if (!_initialized) {
            _render();
            _initialized = true;
        } else {
            // 再次打开只刷新左侧列表，右侧面板保持不变
            _refreshCharList();
            if (_currentCharId) {
                const card = page.querySelector(`.growth-char-card[data-char-id="${_currentCharId}"]`);
                if (card) card.classList.add('active');
            }
        }
    }

    function close() {
        const page = document.getElementById('page-growth');
        if (page) page.style.display = 'none';
    }

    // 只刷新左侧角色列表
    function _refreshCharList() {
        const scroll = document.querySelector('.char-grid-scroll');
        if (!scroll) return;
        const save = S().get();
        scroll.innerHTML = _getSortedCharIds(save).map(id => _renderCharCard(id, save)).join('');
        const page = document.getElementById('page-growth');
        page.querySelectorAll('.growth-char-card').forEach(el => {
            el.addEventListener('click', () => _selectChar(el, page));
        });
    }

    // Bug4：按稀有度从高到低排序
    function _getSortedCharIds(save) {
        return Object.keys(save.ownedCharacters || {}).sort((a, b) => {
            return (CD()[b]?.rarity || 0) - (CD()[a]?.rarity || 0);
        });
    }

    function _render() {
        const page = document.getElementById('page-growth');
        if (!page) return;
        const save = S().get();
        page.innerHTML = `
        <div class="growth-layout">
            <div class="growth-char-list">
                <div class="section-title">选择角色</div>
                <div class="char-grid-scroll">
                    ${_getSortedCharIds(save).map(id => _renderCharCard(id, save)).join('')}
                </div>
            </div>
            <div class="growth-panel" id="growth-panel">
                <div class="growth-placeholder">← 选择一个角色开始养成</div>
            </div>
        </div>`;
        page.querySelectorAll('.growth-char-card').forEach(el => {
            el.addEventListener('click', () => _selectChar(el, page));
        });
    }

    function _selectChar(el, page) {
        _currentCharId = el.dataset.charId;
        page.querySelectorAll('.growth-char-card').forEach(c => c.classList.remove('active'));
        el.classList.add('active');
        _renderPanel();
    }

    function _renderCharCard(charId, save) {
        const data = CD()[charId];
        if (!data) return '';
        const charSave = save.ownedCharacters[charId];
        const cLevel = charSave.constellation || 0;
        const rc = RC()[data.rarity] || {};
        const isActive = charId === _currentCharId ? 'active' : '';
        const lv = charSave.level || 1;
        const maxLv = CP()?.MAX_LEVEL || 10;
        const need = CP()?.getExpToNextLevel?.(lv) || 0;
        const exp = Math.max(0, Math.floor(charSave.exp || 0));
        return `
        <div class="growth-char-card ${isActive} rarity-${data.rarity} hover-lift" data-char-id="${charId}">
            <div class="char-card-icon" style="background:${data.colorDark || '#1e293b'};border-color:${rc.color || '#888'}">${data.image ? `<img src="${data.image}" alt="${data.name}" style="width:100%;height:100%;object-fit:cover;border-radius:10px;display:block"/>` : _elementEmoji(data.element)}</div>
            <div class="char-card-meta">
                <div class="char-card-name">${data.name}</div>
                <div class="char-card-info"><small>Lv.${lv} · C${cLevel} · ${data.rarity}⭐</small></div>
                <div class="char-card-info"><small>${lv >= maxLv ? 'EXP MAX' : `EXP ${exp}/${need}`}</small></div>
            </div>
        </div>`;
    }

    // ===== 右侧面板 =====
    function _renderPanel() {
        const panel = document.getElementById('growth-panel');
        if (!panel || !_currentCharId) return;
        panel.innerHTML = `
        <div class="growth-tabs">
            <button class="g-tab active" data-tab="constellation">⭐ 命座</button>
            <button class="g-tab" data-tab="relic">💎 遗物</button>
        </div>
        <div id="g-tab-content"></div>`;
        panel.querySelectorAll('.g-tab').forEach(btn => {
            btn.addEventListener('click', () => {
                panel.querySelectorAll('.g-tab').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                _renderTabContent(btn.dataset.tab);
            });
        });
        _renderTabContent('constellation');
    }

    function _renderTabContent(tab) {
        const el = document.getElementById('g-tab-content');
        if (!el) return;
        if (tab === 'constellation') _renderConstellationTab(el);
        else _renderRelicTab(el);
    }

    // ===== 命座标签页 =====
    function _renderConstellationTab(container) {
        const charId = _currentCharId;
        const data = CD()[charId];
        if (!data) return;
        const info = CS().getConstellationInfo(charId);
        const level = CS().getLevel(charId);
        const shards = CS().getShards(charId);
        const nextCost = CS().getNextCost(charId);
        const rc = RC()[data.rarity] || {};
        const save = S().get();
        const charSave = save?.ownedCharacters?.[charId] || {};
        const lv = charSave.level || 1;
        const maxLv = CP()?.MAX_LEVEL || 10;
        const expNeed = CP()?.getExpToNextLevel?.(lv) || 0;
        const exp = Math.max(0, Math.floor(charSave.exp || 0));
        const expPct = lv >= maxLv ? 100 : Math.max(0, Math.min(100, expNeed > 0 ? (exp / expNeed) * 100 : 0));

        container.innerHTML = `
        <div class="constellation-panel">
            <div class="constell-header">
                <div class="constell-char-name" style="color:${rc.color}">${data.name}</div>
                <div class="constell-shards">📖 碎片：<strong>${shards}</strong>
                    ${level < 6 ? ` / 下阶需 <strong>${nextCost}</strong>` : ' <span style="color:#22c55e">已满</span>'}
                </div>
                <div style="margin:6px 0 0;font-size:0.74rem;color:#cbd5e1">🎓 等级：<strong>Lv.${lv}</strong> · ${lv >= maxLv ? '<span style="color:#22c55e">EXP MAX</span>' : `EXP <strong>${exp}</strong> / <strong>${expNeed}</strong>`}</div>
                <div style="height:8px;border-radius:999px;overflow:hidden;background:rgba(148,163,184,0.25);margin-top:6px">
                    <div style="height:100%;width:${expPct}%;background:linear-gradient(90deg,#a78bfa,#22d3ee)"></div>
                </div>
                ${level < 6 && shards >= nextCost
                ? `<button class="btn btn-primary btn-sm" id="btn-unlock-constellation">✨ 解锁 C${level + 1}</button>`
                : `<button class="btn btn-ghost btn-sm" disabled>${level >= 6 ? '已达满命' : '碎片不足'}</button>`}
            </div>
            <div class="constellation-stars">
                ${info.map((c, i) => `
                <div class="constell-star ${c.unlocked ? 'unlocked' : 'locked'} ${c.isNext ? 'next' : ''}" data-idx="${i}">
                    <div class="constell-star-num">C${i + 1}</div>
                    <div class="constell-star-icon">${c.unlocked ? '✨' : '⭐'}</div>
                </div>`).join('')}
            </div>
            <div class="constell-details">
                ${info.map((c, i) => `
                <div class="constell-detail-item" data-idx="${i}" style="display:${i === (level > 0 ? level - 1 : 0) ? 'block' : 'none'}">
                    <div class="constell-detail-title ${c.unlocked ? 'unlocked-text' : ''}">C${i + 1} · ${c.label} ${c.unlocked ? '✅' : '🔒'}</div>
                    <div class="constell-detail-desc">${c.desc}</div>
                    ${!c.unlocked ? `<div class="constell-detail-cost">需要 ${c.cost} 碎片解锁</div>` : ''}
                </div>`).join('')}
            </div>
        </div>`;

        container.querySelectorAll('.constell-star').forEach(star => {
            star.addEventListener('click', () => {
                const idx = +star.dataset.idx;
                container.querySelectorAll('.constell-detail-item').forEach((d, di) => {
                    d.style.display = di === idx ? 'block' : 'none';
                });
            });
        });

        container.querySelector('#btn-unlock-constellation')?.addEventListener('click', () => {
            const result = CS().unlock(charId);
            if (result.success) {
                window.GG.UIManager?.showToast?.(`🎉 ${data.name} C${result.newLevel} 解锁！`, 'success');
                _renderConstellationTab(container);
                _refreshCharList();
            } else {
                window.GG.UIManager?.showToast?.(result.error, 'error');
            }
        });
    }

    // ===== 遗物标签页 =====
    function _renderRelicTab(container) {
        const charId = _currentCharId;
        const data = CD()[charId];
        if (!data) return;
        const equipped = RS().getEquippedRelics(charId);
        const inventory = RS().getInventory();

        container.innerHTML = `
        <div class="relic-panel">
            <div class="relic-equipped-section">
                <div class="section-label">已装备遗物</div>
                <div class="relic-slots-row">
                    ${Slots().map(slot => {
            const r = equipped[slot.id];
            return `<div class="relic-slot ${r ? 'has-relic' : 'empty'}" data-slot="${slot.id}">
                            <div class="relic-slot-icon">${slot.icon}</div>
                            <div class="relic-slot-name">${slot.name}</div>
                            ${r ? `
                            <div class="relic-slot-rarity" style="color:${window.GG.RelicRarityConfig?.[r.rarity]?.color || '#fff'}">+${r.level}</div>
                            <div class="relic-slot-main">${r.mainStat.name}</div>
                            <button class="relic-unequip-btn btn btn-ghost btn-xs" data-slot="${slot.id}">卸</button>` : '<div class="relic-empty-hint">空</div>'}
                        </div>`;
        }).join('')}
                </div>
            </div>
            <div class="relic-divider">▼ 背包（${inventory.length} 件）</div>
            <div class="relic-bag-section">
                <div class="relic-bag-filters">
                    <button class="relic-filter-btn ${!_relicFilterSlot ? 'active' : ''}" data-filter="">全部</button>
                    ${Slots().map(s => `<button class="relic-filter-btn ${_relicFilterSlot === s.id ? 'active' : ''}" data-filter="${s.id}">${s.icon}${s.name}</button>`).join('')}
                </div>
                ${_renderBatchSellPanel()}
                <div class="relic-bag-grid">${_renderRelicBag(inventory, equipped)}</div>
            </div>
        </div>`;

        container.querySelectorAll('.relic-unequip-btn').forEach(btn => {
            btn.addEventListener('click', e => { e.stopPropagation(); RS().unequip(charId, btn.dataset.slot); _renderRelicTab(container); });
        });
        container.querySelectorAll('.relic-filter-btn').forEach(btn => {
            btn.addEventListener('click', () => { _relicFilterSlot = btn.dataset.filter || null; _renderRelicTab(container); });
        });
        container.querySelectorAll('.relic-card').forEach(card => {
            card.addEventListener('click', () => _showRelicDetail(card.dataset.uid, charId, container));
        });

        _bindBatchSellEvents(container);
    }

    function _loadBatchPref() {
        try {
            const raw = localStorage.getItem(RELIC_BATCH_PREF_KEY);
            const p = raw ? JSON.parse(raw) : {};
            return {
                all3Star: !!p.all3Star,
                all4Star: !!p.all4Star,
                allUnupgraded: !!p.allUnupgraded,
            };
        } catch (_) {
            return { all3Star: true, all4Star: false, allUnupgraded: true };
        }
    }

    function _saveBatchPref(pref) {
        localStorage.setItem(RELIC_BATCH_PREF_KEY, JSON.stringify(pref));
    }

    function _renderBatchSellPanel() {
        const pref = _loadBatchPref();
        return `
        <div style="margin:8px 2px 10px;padding:10px;border:1px solid rgba(248,113,113,0.25);border-radius:10px;background:rgba(248,113,113,0.06)">
            <div style="font-size:0.74rem;font-weight:700;color:#fca5a5;margin-bottom:6px">🧹 批量分解（自动记忆勾选）</div>
            <div style="display:flex;flex-wrap:wrap;gap:10px;margin-bottom:8px;font-size:0.72rem;color:#cbd5e1">
                <label><input type="checkbox" data-batch-opt="all3Star" ${pref.all3Star ? 'checked' : ''}/> 所有三星</label>
                <label><input type="checkbox" data-batch-opt="all4Star" ${pref.all4Star ? 'checked' : ''}/> 所有四星</label>
                <label><input type="checkbox" data-batch-opt="allUnupgraded" ${pref.allUnupgraded ? 'checked' : ''}/> 所有未强化</label>
            </div>
            <button class="btn btn-ghost" id="btn-relic-batch-sell" style="color:#f87171;border-color:rgba(248,113,113,0.45)">🔨 按勾选条件批量分解</button>
        </div>`;
    }

    function _bindBatchSellEvents(container) {
        const opts = [...container.querySelectorAll('[data-batch-opt]')];
        opts.forEach(el => {
            el.addEventListener('change', () => {
                const pref = _loadBatchPref();
                pref[el.dataset.batchOpt] = !!el.checked;
                _saveBatchPref(pref);
            });
        });

        const btn = container.querySelector('#btn-relic-batch-sell');
        if (!btn) return;
        btn.addEventListener('click', () => {
            const pref = _loadBatchPref();
            if (!pref.all3Star && !pref.all4Star && !pref.allUnupgraded) {
                window.GG.UIManager?.showToast?.('请至少勾选一个批量分解条件', 'error');
                return;
            }
            window.GG.UIManager?.showConfirmDialog?.({
                title: '确认批量分解',
                message: '将按当前勾选条件分解遗物并获得金币，已装备遗物也会自动卸下。是否继续？',
                confirmText: '确认分解',
                cancelText: '取消',
                danger: true,
            }).then((ok) => {
                if (!ok) return;
                const r = RS().batchSell(pref);
                if (!r.success) {
                    window.GG.UIManager?.showToast?.(r.error || '批量分解失败', 'error');
                    return;
                }
                window.GG.UIManager?.showToast?.(`🔨 已分解 ${r.count} 件遗物，获得 ${r.gold} 🪙`, 'success');
                window.GG.UIManager?.updateResourceBar?.();
                _renderRelicTab(container);
            });
        });
    }

    function _renderRelicBag(inventory, equipped) {
        const filtered = _relicFilterSlot ? inventory.filter(r => r.slotId === _relicFilterSlot) : inventory;
        if (!filtered.length) return '<div class="relic-empty">背包没有遗物，快去通关关卡吧！</div>';

        const equippedUids = Object.values(equipped || {}).filter(Boolean).map(r => r?.uid);
        const groupRank = (relic) => {
            const ownerId = relic.equippedBy;
            const isEquippedByCurrent = ownerId === _currentCharId || (!ownerId && equippedUids.includes(relic.uid));
            const isEquippedByOther = !!ownerId && ownerId !== _currentCharId;
            if (!ownerId && !isEquippedByCurrent) return 0; // 未装备
            if (isEquippedByCurrent) return 1; // 当前角色装备
            if (isEquippedByOther) return 2; // 他人装备（排最后）
            return 0;
        };

        return [...filtered].sort((a, b) => {
            const g = groupRank(a) - groupRank(b);
            if (g !== 0) return g;
            return (b.rarity - a.rarity) || (b.level - a.level);
        }).map(r => {
            const rc = window.GG.RelicRarityConfig?.[r.rarity] || {};
            const slotDef = (window.GG.RelicSlots || []).find(s => s.id === r.slotId) || {};
            const ownerId = r.equippedBy;
            const isEquippedByCurrent = ownerId === _currentCharId || (!ownerId && equippedUids.includes(r.uid));
            const isEquippedByOther = !!ownerId && ownerId !== _currentCharId;
            const ownerName = isEquippedByOther ? (CD()[ownerId]?.name || ownerId) : '';
            const mainVal = RS().getMainStatValue(r);
            return `
            <div class="relic-card ${isEquippedByCurrent ? 'equipped' : ''} ${isEquippedByOther ? 'equipped-other' : ''} rarity-${r.rarity}" data-uid="${r.uid}" style="border-color:${rc.color || '#666'}">
                <div class="relic-card-top">
                    <span class="relic-slot-badge">${slotDef.icon || '?'}</span>
                    <span class="relic-card-rarity" style="color:${rc.color}">${rc.label || ''}+${r.level}</span>
                    ${isEquippedByCurrent ? '<span class="relic-equipped-badge">装备中</span>' : ''}
                </div>
                ${isEquippedByOther ? `<div class="relic-owner-badge">已装备给 ${ownerName}</div>` : ''}
                <div class="relic-card-main">${r.mainStat.name} ${_fmtVal(r.mainStat.stat, mainVal)}</div>
                <div class="relic-card-subs">${r.subStats.map(s => `<div class="relic-sub">${s.name} <span>+${_fmtVal(s.stat, s.value)}</span></div>`).join('')}</div>
            </div>`;
        }).join('');
    }

    // ===== 遗物详情弹窗（强化+装备+分解）=====
    function _showRelicDetail(uid, charId, container) {
        const save = S().get();
        const relic = (save.relics || []).find(r => r.uid === uid);
        if (!relic) return;
        const rc = window.GG.RelicRarityConfig?.[relic.rarity] || {};
        const slotDef = (window.GG.RelicSlots || []).find(s => s.id === relic.slotId) || {};
        const mainVal = RS().getMainStatValue(relic);
        const upgradeCost = window.GG.relicUpgradeCost(relic.level);
        const upgradeToMaxCost = RS().getUpgradeCostToMax(uid);
        const gold = save.resources?.gold || 0;
        // Bug3：分解金币（三/四/五星基础 + 强化等级加成）
        const sellValue = ({ 3: 50, 4: 200, 5: 800 }[relic.rarity] || 50) + relic.level * 20;

        container.querySelector('#relic-detail-popup')?.remove();
        const popup = document.createElement('div');
        popup.id = 'relic-detail-popup';
        popup.className = 'relic-detail-popup';
        popup.innerHTML = `
        <div class="relic-detail-header" style="border-color:${rc.color}">
            <span>${slotDef.icon} ${slotDef.name} · ${rc.label}</span>
            <button class="btn btn-ghost btn-xs" id="close-relic-detail">✕</button>
        </div>
        <div class="relic-detail-body">
            <div class="relic-main-row">
                <span class="relic-main-label">主词条</span>
                <span class="relic-main-val" style="color:${rc.color}">${relic.mainStat.name} <strong>${_fmtVal(relic.mainStat.stat, mainVal)}</strong></span>
            </div>
            <div class="relic-lv-bar">
                <div class="relic-lv-fill" style="width:${relic.level / 25 * 100}%;background:${rc.color}"></div>
                <span class="relic-lv-text">+${relic.level} / +25</span>
            </div>
            <div class="relic-subs-list">
                ${relic.subStats.map(s => `
                <div class="relic-sub-row">
                    <span class="relic-sub-name">${s.name}</span>
                    <span class="relic-sub-val">${_fmtVal(s.stat, s.value)}</span>
                </div>`).join('')}
            </div>
            <div class="relic-actions">
                <button class="btn btn-primary" id="btn-relic-equip">装备给 ${CD()[charId]?.name}</button>
                ${relic.level < 25
                ? `<button class="btn ${gold >= upgradeCost ? 'btn-secondary' : 'btn-ghost'}" id="btn-relic-upgrade">强化 +${relic.level + 1} <small>(${upgradeCost}🪙)</small></button>
                   <button class="btn ${gold >= upgradeToMaxCost ? 'btn-gold' : 'btn-ghost'}" id="btn-relic-upgrade-max">⚡ 一键满级 <small>(${upgradeToMaxCost}🪙)</small></button>`
                : `<button class="btn btn-ghost" disabled>已达满强化</button>`}
                <button class="btn btn-ghost" id="btn-relic-sell" style="color:#f87171;border-color:rgba(248,113,113,0.4)">🔨 分解 <small>(+${sellValue}🪙)</small></button>
            </div>
        </div>`;

        container.appendChild(popup);

        const closeBtn = popup.querySelector('#close-relic-detail');
        if (closeBtn) closeBtn.onclick = () => popup.remove();

        const equipBtn = popup.querySelector('#btn-relic-equip');
        if (equipBtn) {
            equipBtn.onclick = () => {
                const r2 = RS().equip(charId, uid);
                if (r2.success) { window.GG.UIManager?.showToast?.('遗物已装备！', 'success'); popup.remove(); _renderRelicTab(container); }
                else window.GG.UIManager?.showToast?.(r2.error, 'error');
            };
        }

        const upgradeBtn = popup.querySelector('#btn-relic-upgrade');
        if (upgradeBtn) {
            upgradeBtn.onclick = () => {
                const r2 = RS().upgrade(uid);
                if (r2.success) {
                    window.GG.UIManager?.showToast?.(r2.boostedStat ? `✨ 强化至 +${r2.newLevel}，${r2.boostedStat} 提升！` : `强化至 +${r2.newLevel}`, 'success');
                    window.GG.UIManager?.updateResourceBar?.();
                    popup.remove();
                    _showRelicDetail(uid, charId, container);
                    _renderRelicTab(container);
                } else window.GG.UIManager?.showToast?.(r2.error, 'error');
            };
        }

        const upgradeMaxBtn = popup.querySelector('#btn-relic-upgrade-max');
        if (upgradeMaxBtn) {
            upgradeMaxBtn.onclick = () => {
                window.GG.UIManager?.showConfirmDialog?.({
                    title: '确认一键强化',
                    message: `将一次性扣除 ${upgradeToMaxCost} 🪙，并把该遗物强化到 +25。是否继续？`,
                    confirmText: '确认强化',
                    cancelText: '取消',
                    danger: false,
                }).then((ok) => {
                    if (!ok) return;
                    const r2 = RS().upgradeToMax(uid);
                    if (r2.success) {
                        window.GG.UIManager?.showToast?.(`⚡ 已一键强化：+${r2.oldLevel} → +${r2.newLevel}（-${r2.totalCost}🪙）`, 'success');
                        window.GG.UIManager?.updateResourceBar?.();
                        popup.remove();
                        _showRelicDetail(uid, charId, container);
                        _renderRelicTab(container);
                    } else window.GG.UIManager?.showToast?.(r2.error, 'error');
                });
            };
        }

        // Bug3：分解 - 修复点击无反应
        const sellBtn = popup.querySelector('#btn-relic-sell');
        if (sellBtn) {
            sellBtn.onclick = () => {
                const r2 = RS().sell(uid);
                if (r2.success) {
                    window.GG.UIManager?.showToast?.(`🔨 分解成功，获得 ${r2.gold} 🪙`, 'info');
                    window.GG.UIManager?.updateResourceBar?.();
                    popup.remove();
                    _renderRelicTab(container);
                } else window.GG.UIManager?.showToast?.(r2.error, 'error');
            };
        }
    }

    function _fmtVal(stat, val) {
        if (['atk_pct', 'def_pct', 'hp_pct', 'cri_rate', 'cri_dmg', 'energy_rate'].includes(stat)) return (val * 100).toFixed(1) + '%';
        return Math.round(val).toString();
    }

    function _elementEmoji(el) {
        return { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' }[el] || '✨';
    }

    function _bindEvents() {
        // Bug1修复：只注册一次
        EB().on('relic:dropped', (relic) => {
            const slot = (window.GG.RelicSlots || []).find(s => s.id === relic.slotId);
            window.GG.UIManager?.showToast?.(
                `💎 获得遗物：${slot?.icon || ''}${slot?.name || relic.slotId}（${window.GG.RelicRarityConfig?.[relic.rarity]?.label || relic.rarity + '星'}）`,
                'success', 3000
            );
        });
    }

    return { open, close };
})();
