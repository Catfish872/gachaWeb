// 队伍编辑 UI
window.GG = window.GG || {};
window.GG.TeamUI = (function () {
    const S = () => window.GG.SaveSystem;
    const CD = () => window.GG.CharacterData;
    const RC = window.GG.RarityConfig;
    const CP = () => window.GG.CharacterProgression;

    let _selectedSlot = null; // 当前点击的槽位

    function init() {
        const page = document.getElementById('page-team');
        if (!page) return;
        render();
    }

    function render() {
        const page = document.getElementById('page-team');
        if (!page) return;
        const save = S().get();
        const team = save.team || [null, null, null];
        const elEmoji = { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' };
        const elColor = { fire: '#ef4444', water: '#3b82f6', wind: '#22c55e', thunder: '#eab308' };

        page.innerHTML = `
      <div style="padding:14px">
        <h2 style="font-size:1rem;font-weight:700;margin-bottom:12px">⚔️ 编队</h2>
        <!-- 队伍槽位 -->
        <div class="team-slots" id="team-slots">
          ${team.map((charId, i) => {
            const c = charId ? CD()[charId] : null;
            const rc = c ? RC?.[c.rarity] : null;
            const rarityClass = c ? `rarity-${c.rarity}` : '';
            return `
              <div class="team-slot ${c ? 'filled' : ''} ${rarityClass}" data-slot="${i}">
                ${c ? `
                  <div class="slot-char-icon">${c.image ? `<img src="${c.image}" alt="${c.name}" style="width:100%;height:100%;object-fit:cover;border-radius:10px;display:block"/>` : (elEmoji[c.element] || '⭐')}</div>
                  <div class="slot-char-name" style="color:${rc?.color || '#fff'}">${c.name}</div>
                  <div style="font-size:0.6rem;color:#94a3b8">${c.element ? window.GG.ElementNames[c.element] : ''}</div>
                  <button class="btn btn-ghost" style="padding:3px 8px;font-size:0.65rem;margin-top:4px" data-remove="${i}">移除</button>
                ` : `
                  <div style="font-size:1.5rem;opacity:0.3">＋</div>
                  <div class="slot-empty-text">点击选择角色</div>
                `}
              </div>`;
        }).join('')}
        </div>
        <div class="divider"></div>
        <!-- 角色列表 -->
        <div style="font-size:0.8rem;font-weight:600;color:#94a3b8;margin-bottom:10px">拥有的角色（点击加入队伍）</div>
        <div class="char-roster" id="char-roster">
          ${Object.entries(save.ownedCharacters || {}).map(([id, data]) => {
            const c = CD()[id];
            if (!c) return '';
            const rc = RC?.[c.rarity];
            const inTeam = team.includes(id);
            return `
              <div class="roster-card ${inTeam ? 'in-team' : ''} rarity-${c.rarity} hover-lift" data-add="${id}" title="${c.description || ''}">
                <div class="roster-char-icon">${c.image ? `<img src="${c.image}" alt="${c.name}" style="width:100%;height:100%;object-fit:cover;border-radius:10px;display:block"/>` : (elEmoji[c.element] || '⭐')}</div>
                <div class="roster-char-name">${c.name}</div>
                <div class="roster-char-stars" style="color:${rc?.color || '#fff'}">${[...Array(c.rarity)].map(() => '★').join('')}</div>
                <div class="roster-char-lv">Lv.${data.level || 1} · ${window.GG.ElementNames[c.element] || ''}</div>
                <div style="font-size:0.62rem;color:#9ca3af">${(data.level || 1) >= (CP()?.MAX_LEVEL || 10)
                    ? 'EXP MAX'
                    : `EXP ${Math.max(0, Math.floor(data.exp || 0))}/${CP()?.getExpToNextLevel?.(data.level || 1) || 0}`}</div>
                ${inTeam ? '<div style="font-size:0.7rem;color:#4ade80;font-weight:700">✓ 队中</div>' : ''}
              </div>`;
        }).join('')}
        </div>
      </div>`;

        // 绑定事件
        page.querySelectorAll('[data-slot]').forEach(el => {
            el.addEventListener('click', (e) => {
                if (e.target.dataset.remove !== undefined) return;
                // 高亮选中槽位
                page.querySelectorAll('[data-slot]').forEach(s => s.style.borderColor = '');
                el.style.borderColor = '#7c3aed';
                _selectedSlot = parseInt(el.dataset.slot);
                window.GG.UIManager.showToast('请在下方点击角色以加入队伍', 'warning');
            });
        });
        page.querySelectorAll('[data-remove]').forEach(el => {
            el.addEventListener('click', (e) => {
                e.stopPropagation();
                const idx = parseInt(el.dataset.remove);
                const save2 = S().get();
                save2.team[idx] = null;
                S().save();
                render();
            });
        });
        page.querySelectorAll('[data-add]').forEach(el => {
            el.addEventListener('click', () => {
                const id = el.dataset.add;
                const save2 = S().get();
                const team2 = save2.team || [null, null, null];
                if (team2.includes(id)) {
                    window.GG.UIManager.showToast('该角色已在队伍中', 'warning'); return;
                }
                let slot = _selectedSlot;
                if (slot === null || team2[slot] !== null) {
                    // 找第一个空槽
                    slot = team2.findIndex(s => !s);
                    if (slot === -1) { window.GG.UIManager.showToast('队伍已满（3人）', 'error'); return; }
                }
                team2[slot] = id;
                save2.team = team2;
                S().save();
                _selectedSlot = null;
                render();
                window.GG.UIManager.showToast(`${CD()[id]?.name} 已加入队伍！`, 'success');
            });
        });
    }

    return { init, render };
})();
