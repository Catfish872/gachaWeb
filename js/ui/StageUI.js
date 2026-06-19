// 关卡地图 UI
window.GG = window.GG || {};
window.GG.StageUI = (function () {
  const SD = () => window.GG.StageData;
  const GE = () => window.GG.GameEngine;
  const S = () => window.GG.SaveSystem;
  const Stamina = () => window.GG.StaminaSystem;

  function init() { render(); }

  function render() {
    const page = document.getElementById('page-stages');
    if (!page) return;
    const save = S().get();
    page.innerHTML = '';

    const title = document.createElement('div');
    title.innerHTML = '<h2 style="font-size:1rem;font-weight:700;padding:14px 14px 6px">🗺️ 关卡地图</h2>';
    page.appendChild(title);

    SD().chapters.forEach(ch => {
      const isUnlocked = GE().isChapterUnlocked(ch.id);
      const card = document.createElement('div');
      card.className = `chapter-card ${!isUnlocked ? 'chapter-locked' : ''}`;
      card.innerHTML = `
        <div class="chapter-header">
          <div>
            <div class="chapter-title">${!isUnlocked ? '🔒 ' : ''}${ch.name}</div>
            <div style="font-size:0.72rem;color:#94a3b8">${ch.description}</div>
          </div>
          <div style="font-size:0.8rem;color:#94a3b8">${isUnlocked ? '▼' : '🔒'}</div>
        </div>`;

      if (isUnlocked) {
        const stageList = document.createElement('div');
        stageList.className = 'stage-list';
        ch.stages.forEach(stage => {
          const progress = save.stageProgress?.[stage.id];
          const cleared = !!progress?.cleared;
          const canEnter = Stamina().getCurrent() >= stage.staminaCost;
          const item = document.createElement('div');
          item.className = `stage-item ${cleared ? 'cleared' : ''} ${!canEnter ? 'insufficient' : ''}`;
          item.style.opacity = canEnter ? '1' : '0.6';
          let typeClass = 'normal', typeName = '普通';
          if (stage.isBoss) { typeClass = 'boss'; typeName = 'BOSS'; }
          if (stage.isElite) { typeClass = 'elite'; typeName = '精英'; }
          item.innerHTML = `
            ${cleared ? '<span class="stage-cleared-icon">✓</span>' : '<span style="color:#475569">○</span>'}
            <span style="flex:1;font-size:0.85rem;font-weight:600">${stage.name}</span>
            <span class="stage-type-badge ${typeClass}">${typeName}</span>
            <span class="stage-cost">⚡${stage.staminaCost}</span>`;
          item.addEventListener('click', () => {
            if (!canEnter) { window.GG.UIManager.showToast('体力不足！', 'error'); return; }
            window.GG.BattleUI.open(stage.id);
          });
          stageList.appendChild(item);
        });
        card.appendChild(stageList);
      } else {
        const lockNote = document.createElement('div');
        lockNote.style.cssText = 'padding:10px 16px;font-size:0.75rem;color:#475569';
        lockNote.textContent = `需要通关 ${ch.unlockCondition || '前置关卡'} 解锁`;
        card.appendChild(lockNote);
      }
      page.appendChild(card);
    });

    // ====== 深渊塔入口 ======
    const dungeonCard = document.createElement('div');
    dungeonCard.className = 'chapter-card';
    dungeonCard.style.cursor = 'pointer';
    dungeonCard.style.borderLeft = '4px solid #8b5cf6';
    dungeonCard.innerHTML = `
      <div class="chapter-header">
        <div>
          <div class="chapter-title">🌀 虚空之塔 (深渊)</div>
          <div style="font-size:0.72rem;color:#8b5cf6;margin-top:2px;">无尽爬塔，必掉5星遗物</div>
        </div>
        <div style="font-size:0.8rem;color:#8b5cf6">前往 ▶</div>
      </div>`;
    dungeonCard.onclick = () => window.GG.UIManager.showPage('abyss');
    page.appendChild(dungeonCard);
  }

  return { init, render };
})();
