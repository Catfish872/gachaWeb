// 抽卡界面 UI
window.GG = window.GG || {};
window.GG.GachaUI = (function () {
    const GS = () => window.GG.GachaSystem;
    const PD = () => window.GG.GachaPoolData;
    const CD = () => window.GG.CharacterData;
    const RC = window.GG.RarityConfig;
    const BA = () => window.GG.BattleAnimator;
    const UI = () => window.GG.UIManager;

    let _currentPoolId = 'limited_kaldi';
    let _isPulling = false;

    function init() {
        const page = document.getElementById('page-gacha');
        if (!page) return;
        _renderPoolTabs(page);
        _renderBanner(page);
        _renderActions(page);
    }

    function _getPoolOrder() { return PD().activePools || ['limited_kaldi', 'standard']; }

    function _renderPoolTabs(page) {
        let tabs = page.querySelector('.pool-selector');
        if (!tabs) { tabs = document.createElement('div'); tabs.className = 'pool-selector'; page.appendChild(tabs); }
        tabs.innerHTML = '';
        _getPoolOrder().forEach(pid => {
            const pool = PD().pools[pid];
            if (!pool) return;
            const div = document.createElement('div');
            div.className = `pool-tab ${pid === _currentPoolId ? 'active' : ''}`;
            div.textContent = pool.name;
            div.addEventListener('click', () => { _currentPoolId = pid; _switchPool(); });
            tabs.appendChild(div);
        });
    }

    function _renderBanner(page) {
        let bc = page.querySelector('.banner-card');
        if (!bc) { bc = document.createElement('div'); bc.className = 'banner-card'; page.insertBefore(bc, page.firstChild); }
        const pool = PD().pools[_currentPoolId];
        if (!pool) return;
        const pityInfo = GS().getPityInfo(_currentPoolId);
        bc.style.setProperty('--banner-gradient', `linear-gradient(135deg, ${pool.gradientFrom || '#1e1b4b'}, ${pool.gradientTo || '#312e81'})`);
        bc.innerHTML = `
      <div class="banner-bg-glow" style="background:linear-gradient(135deg,${pool.gradientFrom || '#1e1b4b'},${pool.gradientTo || '#312e81'})"></div>
      <div class="banner-bg-pattern"></div>
      <div class="banner-emoji">${pool.banner || '🌟'}</div>
      <div class="banner-info">
        <div class="banner-name">${pool.name}</div>
        <div class="banner-subtitle">${pool.subtitle || ''}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap">
          ${(pool.featured5 || []).map(id => {
            const c = CD()[id];
            return `<span style="background:rgba(245,158,11,0.2);border:1px solid rgba(245,158,11,0.5);border-radius:6px;padding:2px 8px;font-size:0.7rem;color:#fbbf24">UP★ ${c?.name || id}</span>`;
        }).join('')}
        </div>
        <div class="banner-pity-text">
          当前: ${pityInfo?.count || 0}/${pityInfo?.hard || 90}抽 · ${pityInfo?.guaranteedFeatured ? '⭐大保底' : '小保底'}
          · 五星概率: ${((pityInfo?.rate5 || 0.016) * 100).toFixed(2)}%
        </div>
      </div>`;
    }

    function _renderActions(page) {
        let acts = page.querySelector('.gacha-actions');
        if (!acts) { acts = document.createElement('div'); acts.className = 'gacha-actions'; page.appendChild(acts); }
        const pool = PD().pools[_currentPoolId];
        if (!pool) return;
        const cost1 = pool.costPerPull;
        const cost10 = pool.costPerPull * 10;
        acts.innerHTML = `
      <div class="gacha-btn single" id="btn-pull-1">
        <div class="pull-label">单抽</div>
        <div class="pull-count">×1</div>
        <div class="pull-cost">💎 ${cost1}</div>
      </div>
      <div class="gacha-btn ten" id="btn-pull-10">
        <div class="pull-label">十连</div>
        <div class="pull-count">×10</div>
        <div class="pull-cost">💎 ${cost10} <span style="font-size:0.6rem;color:#86efac">保底内有四星</span></div>
      </div>`;
        page.querySelector('#btn-pull-1')?.addEventListener('click', () => doPull(1));
        page.querySelector('#btn-pull-10')?.addEventListener('click', () => doPull(10));

        // 详细概率说明
        if (!page.querySelector('.gacha-detail')) {
            const detail = document.createElement('div');
            detail.className = 'gacha-detail';
            detail.style.cssText = 'padding:0 12px 12px;font-size:0.72rem;color:#94a3b8;line-height:2';
            detail.innerHTML = `
        <div>⭐⭐⭐⭐⭐ 五星: 1.6%（73抽开始递增，90抽保底）</div>
        <div>⭐⭐⭐⭐ 四星: 15%（10抽内必有四星）</div>
        <div>⭐⭐⭐ 三星: 83.4%</div>`;
            page.appendChild(detail);
        }
    }

    function _switchPool() {
        const page = document.getElementById('page-gacha');
        if (!page) return;
        _renderPoolTabs(page);
        _renderBanner(page);
        _renderActions(page);
    }

    function doPull(count) {
        if (_isPulling) return;
        _isPulling = true;

        const result = count === 1
            ? window.GG.GachaSystem.pullSingle(_currentPoolId)
            : window.GG.GachaSystem.pullTen(_currentPoolId);

        if (!result.success) {
            UI().showToast(result.error, 'error');
            _isPulling = false;
            return;
        }

        // 刷新保底显示
        const page = document.getElementById('page-gacha');
        if (page) _renderBanner(page);
        UI().updateResourceBar();

        // 显示结果
        _showResults(result.results, count);
        _isPulling = false;
    }

    function _showResults(results, lastCount = 1) {
        const has5Star = results.some(r => r.rarity === 5);
        const overlay = document.createElement('div');
        overlay.className = 'gacha-results-overlay';
        overlay.style.display = 'flex';
        overlay.style.flexDirection = 'column';

        const grid = document.createElement('div');
        grid.className = 'gacha-results-grid';

        if (results.length === 1) {
            grid.style.gridTemplateColumns = '1fr';
            grid.style.maxWidth = '160px';
        }

        const elEmoji = { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' };
        let first5StarCard = null;

        results.forEach((r, i) => {
            const c = CD()[r.charId];
            const rc = RC?.[r.rarity];
            const card = document.createElement('div');
            card.className = `gacha-result-card gacha-card-reveal rarity-${r.rarity} ${r.rarity === 5 ? 'gacha-card-5star' : r.rarity === 4 ? 'rarity-burst-4' : ''}`;
            card.style.animationDelay = `${i * 0.07}s`;
            card.style.overflow = 'hidden';
            if (r.rarity === 5) card.style.background = 'radial-gradient(circle at top, rgba(245,158,11,0.35), rgba(120,53,15,0.15))';
            card.innerHTML = `
        <div class="gacha-char-icon">${c ? (elEmoji[c.element] || '⭐') : '❓'}</div>
        <div class="gacha-char-name">${c?.name || r.charId}</div>
        <div class="star-row r${r.rarity}-stars">${[...Array(r.rarity)].map(() => '★').join('')}</div>
        ${r.isFeatured ? '<div style="font-size:0.55rem;color:#fbbf24;font-weight:700">UP!</div>' : ''}`;
            grid.appendChild(card);
            if (r.rarity === 5 && !first5StarCard) first5StarCard = card;
        });

        const actions = document.createElement('div');
        actions.style.cssText = 'display:flex;gap:10px;margin-top:8px;flex-wrap:wrap;justify-content:center';

        const closeBtn = document.createElement('button');
        closeBtn.className = 'btn btn-primary';
        closeBtn.style.cssText = 'padding:12px 20px;font-size:0.92rem';
        closeBtn.textContent = has5Star ? '✨ 关闭结果' : '关闭';
        closeBtn.onclick = () => overlay.remove();

        const pullSameBtn = document.createElement('button');
        pullSameBtn.className = 'btn btn-secondary';
        pullSameBtn.style.cssText = 'padding:12px 20px;font-size:0.92rem';
        pullSameBtn.textContent = `再来${lastCount === 10 ? '十连' : '一抽'}`;
        pullSameBtn.onclick = () => {
            overlay.remove();
            doPull(lastCount === 10 ? 10 : 1);
        };

        const pullTenBtn = document.createElement('button');
        pullTenBtn.className = 'btn btn-gold';
        pullTenBtn.style.cssText = 'padding:12px 20px;font-size:0.92rem';
        pullTenBtn.textContent = '直接十连';
        pullTenBtn.onclick = () => {
            overlay.remove();
            doPull(10);
        };

        actions.appendChild(closeBtn);
        actions.appendChild(pullSameBtn);
        actions.appendChild(pullTenBtn);

        overlay.appendChild(grid);
        overlay.appendChild(actions);
        document.body.appendChild(overlay);

        // 五星特殊揭晓序列：光柱 → 爆裂环 → 特写 → 闪屏
        if (has5Star) {
            // 光柱
            const pillar = document.createElement('div');
            pillar.className = 'gacha-light-pillar';
            overlay.appendChild(pillar);
            setTimeout(() => pillar.remove(), 1000);

            // 爆裂环（光柱升起后）
            setTimeout(() => {
                const ring = document.createElement('div');
                ring.className = 'gacha-burst-ring';
                overlay.appendChild(ring);
                setTimeout(() => ring.remove(), 800);
            }, 300);

            // 五星特写 + 大字标题
            setTimeout(() => {
                if (first5StarCard && overlay.contains(first5StarCard)) {
                    first5StarCard.classList.add('gacha-card-spotlight');
                }
                const title = document.createElement('div');
                title.className = 'gacha-5star-title text-gradient-gold';
                title.textContent = '★ 五星 ★';
                overlay.appendChild(title);
                // 生成金色粒子缓降装饰
                for (let s = 0; s < 12; s++) {
                    const sparkle = document.createElement('div');
                    sparkle.className = 'gacha-sparkle';
                    sparkle.style.left = (15 + Math.random() * 70) + '%';
                    sparkle.style.top = (20 + Math.random() * 30) + '%';
                    sparkle.style.animationDelay = (Math.random() * 1) + 's';
                    overlay.appendChild(sparkle);
                    setTimeout(() => sparkle.remove(), 2500);
                }
            }, 600);

            // 必杀闪屏
            setTimeout(() => BA().triggerUltimate('fire'), 300);
        }
    }

    return { init, doPull };
})();
