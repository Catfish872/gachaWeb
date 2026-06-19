// UI 总管理器 — 页面路由、资源栏、Toast 通知
window.GG = window.GG || {};
window.GG.UIManager = (function () {
  const S = () => window.GG.SaveSystem;
  const Stamina = () => window.GG.StaminaSystem;
  const SAVE_PREF_IMPORT_SLOT = 'gg_import_target_slot';

  let _currentPage = 'home';
  let _toastQueue = [];
  let _toastTimer = null;

  // ===== 页面切换 =====
  function showPage(pageId) {
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.nav-item').forEach(n => {
      n.classList.toggle('active', n.dataset.page === pageId);
    });
    _moveNavIndicator(pageId);

    // 关闭那些自己管理 display 状态的特殊全屏页面
    window.GG.GrowthUI?.close?.();
    window.GG.AbyssUI?.close?.();

    const page = document.getElementById(`page-${pageId}`);
    if (page) page.classList.add('active');
    _currentPage = pageId;

    // 各页面刷新
    switch (pageId) {
      case 'stages': window.GG.StageUI?.render?.(); break;
      case 'team': window.GG.TeamUI?.render?.(); break;
      case 'gacha': _refreshGachaPage(); break;
      case 'shop': window.GG.ShopUI?.render?.(); break;
      case 'codex': _renderCodexPage(); break;
      case 'home': _renderHomePage(); break;
      case 'growth': window.GG.GrowthUI?.open?.(); break;
      case 'abyss': window.GG.AbyssUI?.open?.(); break;
    }
  }

  // 导航活跃指示器（滑动光标跟随）
  function _moveNavIndicator(pageId) {
    const navBar = document.getElementById('nav-bar');
    const activeItem = navBar?.querySelector(`.nav-item[data-page="${pageId}"]`);
    if (!navBar || !activeItem) return;
    let indicator = navBar.querySelector('.nav-indicator');
    if (!indicator) {
      indicator = document.createElement('div');
      indicator.className = 'nav-indicator';
      navBar.appendChild(indicator);
    }
    const navRect = navBar.getBoundingClientRect();
    const itemRect = activeItem.getBoundingClientRect();
    indicator.style.left = (itemRect.left - navRect.left) + 'px';
    indicator.style.width = itemRect.width + 'px';
  }

  function _refreshGachaPage() {
    const page = document.getElementById('page-gacha');
    if (!page || page.innerHTML.trim()) return; // 已渲染过则只刷保底
    window.GG.GachaUI?.init?.();
  }

  // ===== 资源栏更新 =====
  // 缓存上一次资源值，用于检测变化触发弹跳动画
  let _lastRes = { diamond: null, gold: null, stamina: null };

  function _popValue(el) {
    if (!el) return;
    el.classList.remove('pop');
    void el.offsetWidth; // 强制重排以重启动画
    el.classList.add('pop');
  }

  function updateResourceBar() {
    const save = S().get();
    if (!save) return;
    const diamond = save.resources.diamonds ?? 0;
    const gold = save.resources.gold ?? 0;
    const stamina = Stamina().getCurrent();
    const staminaMax = Stamina().MAX_STAMINA;

    const dEl = document.getElementById('res-diamonds');
    const gEl = document.getElementById('res-gold');
    const stEl = document.getElementById('res-stamina');
    if (dEl) {
      const txt = diamond.toLocaleString();
      if (_lastRes.diamond !== txt) { dEl.textContent = txt; if (_lastRes.diamond !== null) _popValue(dEl); _lastRes.diamond = txt; }
    }
    if (gEl) {
      const txt = gold >= 10000 ? (gold / 10000).toFixed(1) + '万' : gold.toLocaleString();
      if (_lastRes.gold !== txt) { gEl.textContent = txt; if (_lastRes.gold !== null) _popValue(gEl); _lastRes.gold = txt; }
    }
    if (stEl) {
      const txt = `${stamina}/${staminaMax}`;
      if (_lastRes.stamina !== txt) { stEl.textContent = txt; if (_lastRes.stamina !== null) _popValue(stEl); _lastRes.stamina = txt; }
      // 显示恢复倒计时（仅体力不满时）
      const timer = document.getElementById('stamina-timer');
      if (timer) {
        timer.textContent = stamina < staminaMax ? Stamina().formatTimeToRecover() : '';
      }
    }
  }

  // ===== Toast 通知 =====
  function showToast(msg, type = 'info', duration = 2500) {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const div = document.createElement('div');
    div.className = `toast ${type}`;
    div.textContent = msg;
    container.appendChild(div);
    setTimeout(() => { div.style.animation = 'fade-in 0.3s ease reverse both'; setTimeout(() => div.remove(), 300); }, duration);
  }

  // ===== 主页渲染 =====
  function _renderHomePage() {
    const page = document.getElementById('page-home');
    if (!page) return;
    const save = S().get();
    const stats = save.stats || {};
    const ownedCount = Object.keys(save.ownedCharacters || {}).length;
    const clearedCount = Object.values(save.stageProgress || {}).filter(p => p.cleared).length;
    const stamina = Stamina().getCurrent();

    page.innerHTML = `
      <div class="home-banner anim-fade-in">
        <div style="font-size:0.75rem;color:rgba(255,255,255,0.6);margin-bottom:4px">💎 当前星尘晶</div>
        <div style="font-size:2rem;font-weight:900;color:#fbbf24">${(save.resources.diamonds || 0).toLocaleString()}</div>
        <div style="font-size:0.75rem;color:rgba(255,255,255,0.5);margin-top:4px">⚡ 体力 ${stamina}/${Stamina().MAX_STAMINA}</div>
        <div style="margin-top:12px;display:flex;gap:8px">
          <button class="btn btn-gold" onclick="window.GG.UIManager.showPage('gacha')" style="flex:1;padding:10px">🎰 前往祈愿</button>
          <button class="btn btn-ghost" onclick="window.GG.UIManager.showPage('shop')" style="padding:10px 14px">💎 充值</button>
        </div>
      </div>
      <div class="home-stats-grid anim-slide-up">
        <div class="home-stat-card">
          <div class="stat-value">${ownedCount}</div>
          <div class="stat-label">⭐ 拥有角色</div>
        </div>
        <div class="home-stat-card">
          <div class="stat-value">${clearedCount}</div>
          <div class="stat-label">🗺️ 已通关卡</div>
        </div>
        <div class="home-stat-card">
          <div class="stat-value">${stats.totalPulls || 0}</div>
          <div class="stat-label">🎰 累计祈愿</div>
        </div>
        <div class="home-stat-card">
          <div class="stat-value">${stats.totalVictories || 0}</div>
          <div class="stat-label">⚔️ 战斗胜利</div>
        </div>
      </div>
      <div style="padding:0 0 12px" class="anim-slide-up">
        <div class="card" style="margin:0 0 10px;background:linear-gradient(90deg,rgba(124,58,237,0.15),transparent);border-color:rgba(124,58,237,0.3)">
          <div style="font-size:0.75rem;font-weight:700;color:#a855f7;margin-bottom:8px">📋 每日任务（即将开放）</div>
          ${['完成3次战斗', '进行一次十连祈愿', '登录游戏'].map(m => `
            <div style="display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05)">
              <span style="color:#4b5563;font-size:1rem">○</span>
              <span style="font-size:0.78rem;color:#94a3b8">${m}</span>
              <span style="margin-left:auto;font-size:0.72rem;color:#f59e0b">💎×20</span>
            </div>`).join('')}
        </div>
      </div>
      <div class="card" style="margin:0 0 12px;background:linear-gradient(90deg,rgba(16,185,129,0.12),transparent);border-color:rgba(16,185,129,0.32)">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px">
          <div style="font-size:0.82rem;font-weight:800;color:#34d399">💾 本地存档管理</div>
          <button class="btn btn-ghost" style="padding:6px 10px;font-size:0.7rem" onclick="window.GG.UIManager.promptBackupNow()">立即备份</button>
        </div>
        <div style="font-size:0.7rem;color:#94a3b8;margin-bottom:8px">提示：浏览器缓存可能被清理，建议每次上线前导出一次本地存档文件。</div>
        ${S().listSlots().map(slot => `
          <div style="padding:8px;border:1px solid rgba(255,255,255,0.08);border-radius:8px;margin-bottom:8px;background:${slot.isActive ? 'rgba(34,197,94,0.10)' : 'rgba(255,255,255,0.02)'}">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:6px">
              <div style="font-size:0.75rem;font-weight:700;color:${slot.isActive ? '#86efac' : '#cbd5e1'}">${slot.name}${slot.isActive ? '（当前）' : ''}</div>
              <div style="font-size:0.64rem;color:#94a3b8">${slot.hasData ? `上次保存：${_fmtTime(slot.lastSaved)}` : '空槽位'}</div>
            </div>
            <div style="display:flex;flex-wrap:wrap;gap:6px">
              <button class="btn btn-secondary" style="padding:6px 10px;font-size:0.68rem" onclick="window.GG.UIManager.handleSaveAction('switch','${slot.id}')" ${slot.isActive ? 'disabled' : ''}>切换</button>
              <button class="btn btn-ghost" style="padding:6px 10px;font-size:0.68rem" onclick="window.GG.UIManager.handleSaveAction('export','${slot.id}')">导出</button>
              <button class="btn btn-ghost" style="padding:6px 10px;font-size:0.68rem" onclick="window.GG.UIManager.handleSaveAction('import','${slot.id}')">导入</button>
              <button class="btn btn-ghost" style="padding:6px 10px;font-size:0.68rem;color:#f87171;border-color:rgba(248,113,113,0.4)" onclick="window.GG.UIManager.handleSaveAction('reset','${slot.id}')">重置槽位</button>
            </div>
          </div>
        `).join('')}
        <input type="file" id="save-import-input" accept=".json,application/json" style="display:none" />
      </div>`;

    const input = page.querySelector('#save-import-input');
    if (input) {
      input.addEventListener('change', async (e) => {
        const file = e.target.files?.[0];
        if (!file) return;
        const slotId = localStorage.getItem(SAVE_PREF_IMPORT_SLOT) || S().getActiveSlot?.() || 'slot1';
        const r = await S().importSlotFile(file, slotId);
        if (r.success) {
          showToast(`✅ 已导入到 ${slotId}，已切换生效`, 'success');
          S().switchSlot(slotId);
          showPage('home');
          updateResourceBar();
        } else {
          showToast(r.error || '导入失败', 'error');
        }
        e.target.value = '';
      });
    }
  }

  function _fmtTime(ts) {
    if (!ts) return '—';
    const d = new Date(ts);
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  async function handleSaveAction(action, slotId) {
    if (action === 'switch') {
      const r = S().switchSlot(slotId);
      if (!r.success) { showToast(r.error || '切换失败', 'error'); return; }
      showToast(`已切换到 ${slotId}`, 'success');
      showPage('home');
      updateResourceBar();
      return;
    }
    if (action === 'export') {
      const r = S().exportSlot(slotId);
      showToast(r.success ? '已导出存档文件' : (r.error || '导出失败'), r.success ? 'success' : 'error');
      return;
    }
    if (action === 'import') {
      localStorage.setItem(SAVE_PREF_IMPORT_SLOT, slotId);
      const input = document.getElementById('save-import-input');
      if (input) input.click();
      return;
    }
    if (action === 'reset') {
      const ok = await showConfirmDialog({
        title: '确认重置存档槽位',
        message: `将清空 ${slotId} 的当前进度，且不可撤销。是否继续？`,
        confirmText: '确认重置',
        cancelText: '取消',
        danger: true,
      });
      if (!ok) return;

      const r = S().resetSlot(slotId);
      showToast(r.success ? `${slotId} 已重置` : (r.error || '重置失败'), r.success ? 'success' : 'error');
      if (r.success && slotId === S().getActiveSlot()) {
        S().load(slotId);
        updateResourceBar();
      }
      showPage('home');
    }
  }

  async function promptBackupNow() {
    const ok = await showConfirmDialog({
      title: '导出本地存档备份',
      message: '建议定期备份，防止浏览器缓存丢失。现在立即导出当前槽位存档吗？',
      confirmText: '立即导出',
      cancelText: '稍后',
      danger: false,
    });
    if (!ok) return;
    const r = S().exportSlot?.(S().getActiveSlot?.() || 'slot1');
    showToast(r?.success ? '已导出本地备份文件' : (r?.error || '导出失败'), r?.success ? 'success' : 'error');
  }

  function showConfirmDialog({ title = '确认操作', message = '', confirmText = '确认', cancelText = '取消', danger = false } = {}) {
    return new Promise(resolve => {
      const overlay = document.createElement('div');
      overlay.className = 'modal-overlay';
      overlay.innerHTML = `
        <div class="modal" style="max-width:420px;width:min(92vw,420px);padding:0;overflow:hidden;border:1px solid ${danger ? 'rgba(248,113,113,0.35)' : 'rgba(124,58,237,0.35)'};box-shadow:0 20px 60px rgba(0,0,0,0.45)">
          <div style="padding:14px 16px;background:linear-gradient(135deg,${danger ? 'rgba(127,29,29,0.55),rgba(127,29,29,0.15)' : 'rgba(76,29,149,0.55),rgba(76,29,149,0.15)'});border-bottom:1px solid rgba(255,255,255,0.08)">
            <div style="font-size:0.9rem;font-weight:800;color:#f8fafc">${title}</div>
          </div>
          <div style="padding:16px;color:#cbd5e1;font-size:0.82rem;line-height:1.7">${message}</div>
          <div style="display:flex;gap:10px;justify-content:flex-end;padding:0 16px 16px">
            <button class="btn btn-ghost" id="game-modal-cancel">${cancelText}</button>
            <button class="btn ${danger ? 'btn-ghost' : 'btn-primary'}" id="game-modal-confirm" style="${danger ? 'color:#fda4af;border-color:rgba(251,113,133,0.45)' : ''}">${confirmText}</button>
          </div>
        </div>`;

      const done = (v) => {
        overlay.remove();
        resolve(!!v);
      };

      overlay.querySelector('#game-modal-cancel')?.addEventListener('click', () => done(false));
      overlay.querySelector('#game-modal-confirm')?.addEventListener('click', () => done(true));
      overlay.addEventListener('click', (e) => { if (e.target === overlay) done(false); });
      document.body.appendChild(overlay);
    });
  }

  // ===== 图鉴页面 =====
  function _renderCodexPage() {
    const page = document.getElementById('page-codex');
    if (!page) return;
    const save = S().get();
    const CD = window.GG.CharacterData;
    const RC = window.GG.RarityConfig;
    const EN = window.GG.ElementNames;
    const elEmoji = { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' };
    const elColor = { fire: '#ef4444', water: '#3b82f6', wind: '#22c55e', thunder: '#eab308' };

    let _filter = 'all';

    function doRender() {
      page.innerHTML = `
        <div style="padding:14px">
          <h2 style="font-size:1rem;font-weight:700;margin-bottom:10px">📖 角色图鉴</h2>
          <div class="codex-filter">
            ${['all', 'fire', 'water', 'wind', 'thunder'].map(f => `
              <button class="filter-btn ${_filter === f ? 'active' : ''}" data-filter="${f}">${f === 'all' ? '全部' : EN[f]}</button>`).join('')}
          </div>
          <div class="codex-grid" id="codex-grid"></div>
        </div>`;
      page.querySelectorAll('[data-filter]').forEach(btn => {
        btn.addEventListener('click', () => { _filter = btn.dataset.filter; doRender(); });
      });
      const grid = document.getElementById('codex-grid');
      Object.values(CD).filter(c => _filter === 'all' || c.element === _filter).forEach(c => {
        const owned = !!save.ownedCharacters?.[c.id];
        const rc = RC?.[c.rarity];
        const card = document.createElement('div');
        card.className = `codex-card ${!owned ? 'not-owned' : ''} rarity-${c.rarity} hover-lift`;
        card.innerHTML = `
          ${owned ? '<div class="codex-owned-badge">✓</div>' : ''}
          <div class="codex-avatar" style="background:linear-gradient(180deg,${(elColor[c.element] || '#4b5563')}22,transparent)">
            ${c.image
              ? `<img src="${c.image}" alt="${c.name}" style="width:100%;height:100%;object-fit:cover;border-radius:12px;display:block"/>`
              : `<span style="font-size:2.8rem">${elEmoji[c.element] || '⭐'}</span>`}
            <div class="codex-rarity-bar" style="background:${rc?.color || '#6b7280'}"></div>
          </div>
          <div class="codex-info">
            <div class="codex-char-name">${c.name}</div>
            <div class="codex-char-stars star-row r${c.rarity}-stars" style="color:${rc?.color || '#6b7280'}">${[...Array(c.rarity)].map(() => '★').join('')}</div>
          </div>`;
        card.addEventListener('click', () => _showCharDetail(c, save.ownedCharacters?.[c.id]));
        grid.appendChild(card);
      });
    }
    doRender();
  }

  function _showCharDetail(c, ownData) {
    const CS = window.GG.CharacterStats;
    const RC = window.GG.RarityConfig;
    const SD = window.GG.SkillData;
    const EN = window.GG.ElementNames;
    const elEmoji = { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' };
    const rc = RC?.[c.rarity];
    const lv = ownData?.level || 1;
    const awk = ownData?.awakening || 0;
    const stats = CS.computeStats(c.id, lv, awk);

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML = `
      <div class="modal" style="padding:0;overflow:hidden">
        <div style="background:linear-gradient(135deg,${c.colorDark || '#1e1b4b'},${c.color || '#7c3aed'}33);padding:20px 20px 16px;position:relative">
          <div style="font-size:3rem;margin-bottom:8px;width:72px;height:72px;border-radius:14px;overflow:hidden;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.18)">${c.image ? `<img src="${c.image}" alt="${c.name}" style="width:100%;height:100%;object-fit:cover;display:block"/>` : (elEmoji[c.element] || '⭐')}</div>
          <div style="font-size:1.2rem;font-weight:800">${c.name}</div>
          <div style="font-size:0.75rem;color:rgba(255,255,255,0.6)">${c.title || ''}</div>
          <div style="margin-top:6px;display:flex;gap:6px;align-items:center">
            <span style="color:${rc?.color || '#fff'}">${[...Array(c.rarity)].map(() => '★').join('')}</span>
            <span style="font-size:0.8rem;color:${(c.element === 'fire' ? '#ef4444' : c.element === 'water' ? '#3b82f6' : c.element === 'wind' ? '#22c55e' : '#eab308')}">${EN[c.element] || ''}</span>
            <span style="font-size:0.75rem;color:#94a3b8">${window.GG.RoleNames?.[c.role] || ''}</span>
          </div>
          <button id="modal-close" style="position:absolute;top:16px;right:16px;background:rgba(0,0,0,0.3);border:none;color:#fff;border-radius:50%;width:28px;height:28px;font-size:1rem;cursor:pointer;display:flex;align-items:center;justify-content:center">✕</button>
        </div>
        <div style="padding:16px">
          ${ownData ? `<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin-bottom:14px">
            ${[['HP', stats.maxHp], ['攻击', stats.atk], ['防御', stats.def], ['速度', stats.spd], ['暴击率', (stats.cri * 100).toFixed(1) + '%'], ['暴击伤害', (stats.criDmg * 100).toFixed(0) + '%']].map(([k, v]) => `
              <div style="background:rgba(255,255,255,0.05);border-radius:8px;padding:8px;text-align:center">
                <div style="font-size:0.65rem;color:#94a3b8">${k}</div>
                <div style="font-weight:700;font-size:0.9rem">${v}</div>
              </div>`).join('')}
          </div>` : `<div style="text-align:center;color:#94a3b8;padding:12px;font-size:0.85rem">未拥有此角色</div>`}
          <div style="font-size:0.75rem;color:#94a3b8;margin-bottom:10px;font-style:italic">"${c.flavorText || ''}"</div>
          <div style="font-size:0.75rem;color:#94a3b8;margin-bottom:12px">${c.passiveDesc || ''}</div>
          <div style="font-size:0.8rem;font-weight:600;margin-bottom:8px">📚 技能</div>
          ${(c.skills || []).map(sid => { const s = SD[sid]; return s ? `<div style="display:flex;align-items:flex-start;gap:8px;padding:8px;background:rgba(255,255,255,0.04);border-radius:8px;margin-bottom:6px"><span style="font-size:1.2rem">${s.icon || '⚔️'}</span><div><div style="font-size:0.8rem;font-weight:700">${s.name} <span style="font-size:0.65rem;color:#94a3b8;font-weight:400">[${s.type === 'normal' ? '普攻' : s.type === 'skill' ? '技能' : '必杀'}]</span></div><div style="font-size:0.72rem;color:#94a3b8">${s.description}</div></div></div>` : ''; }).join('')}
        </div>
      </div>`;
    overlay.querySelector('#modal-close').onclick = () => overlay.remove();
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
    document.body.appendChild(overlay);
  }

  // ===== 初始化 =====
  function init() {
    // 渲染默认首页
    showPage('home');
    updateResourceBar();
    // 体力倒计时每秒更新
    setInterval(updateResourceBar, 1000);
  }

  return { showPage, updateResourceBar, showToast, init, handleSaveAction, promptBackupNow, showConfirmDialog };
})();
