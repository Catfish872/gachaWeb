// 战斗界面 UI — 渲染和交互
window.GG = window.GG || {};
window.GG.BattleUI = (function () {
    const BE = () => window.GG.BattleEngine;
    const BA = () => window.GG.BattleAnimator;
    const EB = () => window.GG.EventBus;
    const SD = () => window.GG.SkillData;
    const CD = () => window.GG.CharacterData;
    const SS = () => window.GG.StatusSystem;
    const GE = () => window.GG.GameEngine;
    const RN = window.GG.RarityConfig;

    let _el = {};       // DOM 元素缓存
    let _unitEls = {};  // 单位 ID -> 单位 DOM 元素
    let _currentStageId = null;
    let _animating = false;
    let _resultModalShown = false;
    let _transitioningAbyssNext = false;

    // ===== 打开战斗界面 =====
    function open(stageId, isAbyss = false) {
        _currentStageId = stageId;

        // 战前对话检测（仅普通关卡）
        // 体力不足时 GE().enterStage 会提示；不在此预扣体力，
        // 避免玩家先看剧情再看“体力不足”的尴尬
        if (!isAbyss) {
            const preKey = stageId + '_pre';
            if (window.GG.DialogueUI?.hasScript(preKey)) {
                window.GG.DialogueUI.start(preKey, () => _enterBattleFlow(stageId, false));
                return;
            }
        }

        _enterBattleFlow(stageId, isAbyss);
    }

    // 实际进入战斗流程（战前对话结束后或无战前对话时调用）
    function _enterBattleFlow(stageId, isAbyss) {
        if (!isAbyss) {
            const result = GE().enterStage(stageId);
            if (!result.success) {
                window.GG.UIManager.showToast(result.error, 'error');
                return;
            }
        }
        const screen = document.getElementById('battle-screen');
        if (!screen) { _buildBattleScreen(); }

        _unitEls = {};
        _animating = false;
        _resultModalShown = false;
        _transitioningAbyssNext = false;
        render();
        document.getElementById('battle-screen').style.display = 'flex';
        _bindEvents();
        _syncAutoButton();
        _syncSpeedButton();
        _addLog({ type: 'system', message: '⚔️ 战斗开始！' });
        // Bug2修复：等 UI 事件绑定完后再触发第一回合
        // 若第一个行动者是敌人，此前没有任何代码触发其行动导致永久卡死
        BE().startBattle();
    }

    // 尝试执行章节五星角色赠送（幂等：已领取则返回 null）
    function _tryGrantChapterGift(stageId) {
        const result = window.GG.ChapterGiftSystem?.checkAndGrant(stageId);
        if (result) {
            const msg = result.isNew
                ? `🎁 获得 ${result.charName}！`
                : `🎁 ${result.charName} 碎片+${result.shardsGained}`;
            window.GG.UIManager?.showToast(msg, 'success');
        }
        return result;
    }

    function _escapeHtml(value) {
        return String(value ?? '').replace(/[&<>'"]/g, ch => {
            if (ch === '&') return '&' + 'amp;';
            if (ch === '<') return '&' + 'lt;';
            if (ch === '>') return '&' + 'gt;';
            if (ch === "'") return '&' + '#39;';
            if (ch === '"') return '&' + 'quot;';
            return ch;
        });
    }

    function _rarityMeta(rarity) {
        return window.GG.AbyssData?.rogue?.rarityMeta?.[rarity] || { label: rarity || '未知', color: '#e5e7eb', icon: '◇' };
    }

    function _groupAbyssRewards(rewards) {
        return (rewards || []).reduce((map, reward) => {
            const key = reward.id || reward.name || 'unknown';
            if (!map.has(key)) map.set(key, { reward, count: 0 });
            map.get(key).count++;
            return map;
        }, new Map());
    }

    function _renderAbyssEchoPanel(state) {
        const panel = document.getElementById('battle-abyss-echo-panel');
        if (!panel) return;

        const isAbyss = !!state?.stageConfig?.isAbyss;
        panel.hidden = !isAbyss;
        if (!isAbyss) {
            panel.innerHTML = '';
            return;
        }

        const wasOpen = !!panel.querySelector('.battle-abyss-echo-details')?.open;
        const openAttr = wasOpen ? ' open' : '';
        const rewards = window.GG.AbyssSystem?.getSelectedRewards?.() || [];
        if (!rewards.length) {
            panel.innerHTML = `
                <details class="battle-abyss-echo-details"${openAttr}>
                    <summary class="battle-abyss-echo-summary">
                        <span>🌀 已选回响</span>
                        <strong>0</strong>
                    </summary>
                    <div class="battle-abyss-echo-empty">暂未获得回响，通关构筑节点后会在这里显示。</div>
                </details>`;
            return;
        }

        const listHtml = Array.from(_groupAbyssRewards(rewards).values()).reverse().map(({ reward, count }) => {
            const meta = _rarityMeta(reward.rarity);
            return `
                <div class="battle-abyss-echo-item" style="--echo-color:${_escapeHtml(meta.color)}" title="${_escapeHtml(reward.description || '')}">
                    <span class="battle-abyss-echo-icon">${_escapeHtml(reward.icon || meta.icon || '◇')}</span>
                    <span class="battle-abyss-echo-name">${_escapeHtml(reward.name || reward.id || '未知回响')}</span>
                    ${count > 1 ? `<span class="battle-abyss-echo-count">×${count}</span>` : ''}
                </div>`;
        }).join('');

        panel.innerHTML = `
            <details class="battle-abyss-echo-details"${openAttr}>
                <summary class="battle-abyss-echo-summary">
                    <span>🌀 已选回响</span>
                    <strong>${rewards.length}</strong>
                </summary>
                <div class="battle-abyss-echo-list">${listHtml}</div>
            </details>`;
    }

    // ===== 构建战斗 DOM =====
    function _buildBattleScreen() {
        const div = document.createElement('div');
        div.id = 'battle-screen';
        div.innerHTML = `
      <div class="battle-header">
        <div class="battle-turn-info" id="battle-turn-info">第 1 回合</div>
        <div class="battle-stage-name" id="battle-stage-name" style="font-size:0.75rem;color:#94a3b8"></div>
        <div style="display:flex; gap:10px;">
            <button class="btn btn-ghost" id="btn-battle-auto" style="padding:4px 10px;font-size:0.75rem">🤖 自动: 关</button>
            <button class="btn btn-ghost" id="btn-battle-speed" style="padding:4px 10px;font-size:0.75rem">⏩ 速度: 1X</button>
            <button class="btn btn-ghost" id="btn-battle-exit" style="padding:4px 10px;font-size:0.75rem">撤退</button>
        </div>
      </div>
      <div class="action-timeline" id="action-timeline"></div>
      <div class="battle-abyss-echo-panel" id="battle-abyss-echo-panel" hidden></div>
      <div class="battle-area">
        <div class="enemy-row" id="enemy-row"></div>
        <div class="ally-row" id="ally-row"></div>
      </div>
      <div class="battle-log" id="battle-log"></div>
      <div class="skill-bar" id="skill-bar"></div>
    `;
        div.style.display = 'none';
        document.body.appendChild(div);
    }

    // ===== 渲染当前战斗状态 =====
    function render() {
        const state = BE().getState();
        if (!state) return;

        // 更新战斗头部
        const turnInfo = document.getElementById('battle-turn-info');
        if (turnInfo) turnInfo.textContent = `第 ${state.turn} 回合`;

        // 渲染敌方
        const enemyRow = document.getElementById('enemy-row');
        if (enemyRow) {
            enemyRow.innerHTML = '';
            state.enemies.forEach(e => {
                const card = _createUnitCard(e, false);
                enemyRow.appendChild(card);
                _unitEls[e.id] = card;
                if (e.isBoss && e.currentHp === e.maxHp) card.classList.add('boss-appear');
            });
        }

        // 渲染我方
        const allyRow = document.getElementById('ally-row');
        if (allyRow) {
            allyRow.innerHTML = '';
            state.allies.forEach(a => {
                const card = _createUnitCard(a, true);
                allyRow.appendChild(card);
                _unitEls[a.id] = card;
            });
        }

        // 渲染技能栏
        _renderSkillBar(state);

        // 渲染深渊已选回响
        _renderAbyssEchoPanel(state);

        // 渲染行动时间轴
        _renderTimeline(state);
    }

    function _createUnitCard(unit, isAlly) {
        const data = isAlly ? CD()[unit.id] : {};
        const hpPct = Math.max(0, Math.round(unit.currentHp / unit.maxHp * 100));
        const card = document.createElement('div');
        card.className = `unit-card ${unit.isBoss ? 'is-boss' : ''} ${isAlly ? 'ally-card' : ''} ${unit.currentHp <= 0 ? 'unit-dead' : ''}`;
        card.dataset.unitId = unit.id;

        // 元素颜色
        const elColors = { fire: '#ef4444', water: '#3b82f6', wind: '#22c55e', thunder: '#eab308' };
        const elColor = elColors[unit.element] || '#94a3b8';
        const hpBarClass = hpPct <= 25 ? 'danger' : hpPct <= 50 ? 'warning' : '';

        // 状态图标
        const statusIcons = (unit.statuses || []).map(s => {
            const cfg = SS().getRegistry()[s.id];
            const duration = Number.isFinite(Number(s.duration)) ? Math.max(0, Math.ceil(Number(s.duration))) : 0;
            const durationBadge = duration > 0 ? `<span class="status-duration">${duration}</span>` : '';
            return `<div class="status-badge status-icon ${cfg?.colorClass || ''}" title="${cfg?.label || s.id}（${duration || s.duration}回合）"><span class="status-symbol">${cfg?.icon || '?'}</span>${durationBadge}</div>`;
        }).join('');

        // 头像
        let avatarHtml;
        if (unit.image) {
            avatarHtml = `<img class="unit-avatar-img" src="${unit.image}" alt="${unit.name}">`;
        } else if (!isAlly) {
            avatarHtml = unit.icon || '👾';
        } else {
            // 用元素 emoji 代表角色
            const elEmoji = { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' };
            avatarHtml = elEmoji[unit.element] || '⭐';
        }

        card.innerHTML = `
      <div class="status-icons">${statusIcons}</div>
      <div class="unit-avatar">
        <div class="unit-element-bg" style="background:${elColor}"></div>
        ${unit.image ? `<img class="unit-avatar-img" src="${unit.image}" alt="${unit.name}">` : `<span style="position:relative;z-index:1">${!isAlly ? (unit.icon || '👾') : ({ fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' }[unit.element] || '⭐')}</span>`}
        ${unit.isBoss ? '<div style="position:absolute;top:4px;left:4px;background:rgba(239,68,68,0.8);border-radius:4px;padding:1px 5px;font-size:0.55rem;font-weight:700;color:#fff">BOSS</div>' : ''}
      </div>
      <div class="unit-info">
        <div class="unit-name">${unit.name}</div>
        <div class="hp-bar"><div class="hp-bar-fill ${hpBarClass}" style="width:${hpPct}%"></div></div>
        <div class="hp-text">${unit.currentHp}/${unit.maxHp}</div>
        ${isAlly ? `<div class="energy-bar ${unit.energy >= 100 ? 'energy-full' : ''}"><div class="energy-bar-fill" style="width:${unit.energy}%"></div></div>` : ''}
      </div>
    `;
        return card;
    }

    function _renderSkillBar(state) {
        const skillBar = document.getElementById('skill-bar');
        if (!skillBar) return;
        const actor = BE().getCurrentActor();
        if (!actor || !actor.isAlly) {
            skillBar.innerHTML = '<div style="flex:1;text-align:center;font-size:0.8rem;color:#94a3b8;padding:14px">⏳ 等待...</div>';
            return;
        }
        skillBar.innerHTML = '';
        actor.skills.forEach(skillId => {
            const sd = SD()[skillId];
            if (!sd) return;
            const cd = actor.cooldowns?.[skillId] || 0;
            const isUlt = sd.type === 'ultimate';
            const unavail = !window.GG.SkillSystem.isSkillAvailable(skillId, actor) || state.isAuto;
            const btn = document.createElement('button');
            btn.className = `skill-btn ${sd.type === 'normal' ? 'normal-skill' : sd.type === 'skill' ? 'special-skill' : 'ult-skill'}`;
            btn.disabled = unavail;
            btn.dataset.skillId = skillId;
            btn.innerHTML = `
        <span class="skill-icon">${sd.icon || '⚔️'}</span>
        <span class="skill-name">${sd.name}</span>
        ${cd > 0 ? `<span class="skill-cd">CD:${cd}</span>` : ''}
        ${isUlt ? `<span style="font-size:0.6rem;color:${actor.energy >= 100 ? '#fbbf24' : '#6b7280'}">[${actor.energy}/100]</span>` : ''}
      `;
            btn.addEventListener('click', () => onSkillClick(skillId, btn));
            skillBar.appendChild(btn);
        });
    }

    function _renderTimeline(state) {
        const tl = document.getElementById('action-timeline');
        if (!tl) return;
        const elEmoji = { fire: '🔥', water: '💧', wind: '🌿', thunder: '⚡' };
        tl.innerHTML = '';
        const currentActor = BE().getCurrentActor();
        (state.roundRobin || []).forEach((unit) => {
            if (unit.currentHp <= 0) return;
            const div = document.createElement('div');
            div.className = `timeline-unit ${unit.isAlly ? 'ally' : 'enemy'} ${unit === currentActor ? 'active' : ''}`;
            div.innerHTML = `
        <div class="timeline-unit-icon">${unit.isAlly ? (elEmoji[unit.element] || '⭐') : (unit.icon || '👾')}</div>
        <div style="font-size:0.5rem;color:#94a3b8">${unit.name.slice(0, 3)}</div>
      `;
            tl.appendChild(div);
        });
    }

    // ===== 技能点击处理 =====
    function onSkillClick(skillId, btn) {
        if (_animating) return;
        const sd = SD()[skillId];
        _animating = true;
        // 技能按钮按下动画
        if (btn) BA().pulse(btn, 'skill-btn-pressed', 250);
        // 必杀技全屏特效
        if (sd?.type === 'ultimate') {
            const actor = BE().getCurrentActor();
            BA().triggerUltimate(actor?.element || 'fire');
            setTimeout(() => _doSkill(skillId), BE().getScaledDelay?.(400) || 400);
        } else {
            _doSkill(skillId);
        }
    }

    function _doSkill(skillId) {
        const result = BE().playerAction(skillId);
        if (!result) { _animating = false; return; }

        // 播放动画
        BA().playAnimationSequence(result.animations, _unitEls, () => {
            _animating = false;
            _refreshUnits();
        });

        // 写日志
        result.log.forEach(entry => _addLog(entry));
    }

    function _refreshUnits() {
        const state = BE().getState();
        if (!state) return;

        // 更新单位 HP 和状态（不重建 DOM，只更新数值）
        [...state.allies, ...state.enemies].forEach(unit => {
            const card = _unitEls[unit.id];
            if (!card) return;
            const hpPct = Math.max(0, Math.round(unit.currentHp / unit.maxHp * 100));
            const hpFill = card.querySelector('.hp-bar-fill');
            const hpText = card.querySelector('.hp-text');
            if (hpFill) {
                hpFill.style.width = hpPct + '%';
                hpFill.className = `hp-bar-fill ${hpPct <= 30 ? 'hp-low' : ''}`;
            }
            if (hpText) hpText.textContent = `${unit.currentHp}/${unit.maxHp}`;
            if (unit.isAlly) {
                const enFill = card.querySelector('.energy-bar-fill');
                if (enFill) enFill.style.width = unit.energy + '%';
                const enBar = card.querySelector('.energy-bar');
                if (enBar) enBar.className = `energy-bar ${unit.energy >= 100 ? 'energy-full' : ''}`;
            }

            // 死亡判断（仅首次进入死亡状态时播放）
            if (unit.currentHp <= 0) {
                if (!card.dataset.deadAnimated) {
                    card.dataset.deadAnimated = '1';
                    BA().pulse(card, 'anim-dying', 600);
                    setTimeout(() => card.classList.add('unit-dead'), BE().getScaledDelay?.(650) || 650);
                }
            } else {
                delete card.dataset.deadAnimated;
                card.classList.remove('unit-dead');
            }

            // 状态图标更新
            const statusIconsEl = card.querySelector('.status-icons');
            if (statusIconsEl) {
                statusIconsEl.innerHTML = (unit.statuses || []).map(s => {
                    const cfg = SS().getRegistry()[s.id];
                    const duration = Number.isFinite(Number(s.duration)) ? Math.max(0, Math.ceil(Number(s.duration))) : 0;
                    const durationBadge = duration > 0 ? `<span class="status-duration">${duration}</span>` : '';
                    return `<div class="status-badge status-icon ${cfg?.colorClass || ''}" title="${cfg?.label || s.id}（${duration || s.duration}回合）"><span class="status-symbol">${cfg?.icon || '?'}</span>${durationBadge}</div>`;
                }).join('');
            }
        });

        // 更新技能栏和时间轴
        _renderSkillBar(state);
        _renderTimeline(state);
        const turnInfo = document.getElementById('battle-turn-info');
        if (turnInfo) turnInfo.textContent = `第 ${state.turn} 回合`;
    }

    function _addLog(entry) {
        const logEl = document.getElementById('battle-log');
        if (!logEl) return;
        let text = '';
        let cls = '';
        if (entry.type === 'damage') {
            const critText = entry.isCrit ? '【暴击】' : '';
            const elemText = entry.elementMult > 1 ? '⚡克制！' : entry.elementMult < 1 ? '🛡️不克制' : '';
            cls = entry.isEnemy ? 'log-enemy' : (entry.isCrit ? 'log-crit' : 'log-damage');
            text = `${entry.attacker} → ${entry.targetName}: ${critText}${elemText} -${entry.damage}`;
        } else if (entry.type === 'heal') {
            cls = 'log-heal'; text = `${entry.unit} 恢复了 ${entry.amount} 点生命`;
        } else if (entry.type === 'status') {
            const sReg = SS().getRegistry()[entry.statusId];
            cls = 'log-status'; text = `${entry.unit} 陷入了 ${sReg?.label || entry.statusId}（${entry.duration}回合）`;
        } else if (entry.type === 'status_dmg') {
            const sReg = SS().getRegistry()[entry.statusId];
            cls = 'log-enemy'; text = `${entry.unit} 因 ${sReg?.label || entry.statusId} 受到 ${entry.damage} 点伤害`;
        } else if (entry.type === 'skip') {
            cls = 'log-skip'; text = `${entry.unit} 无法行动（${entry.reason}）`;
        } else if (entry.type === 'system' || entry.type === 'phase_change') {
            cls = 'log-system'; text = entry.message || `${entry.unit} 进入了第二阶段！`;
        } else if (entry.type === 'miss') {
            cls = 'log-skip'; text = `${entry.targetName} ${entry.reason || '闪避'}`;
        } else { return; }

        const line = document.createElement('div');
        line.className = cls; line.textContent = text;
        logEl.appendChild(line);
        logEl.scrollTop = logEl.scrollHeight;
    }

    function _syncAutoButton() {
        const autoBtn = document.getElementById('btn-battle-auto');
        if (!autoBtn) return;
        const isAuto = !!BE().getState()?.isAuto;
        autoBtn.innerHTML = isAuto ? '<span style="color:#fbbf24">🤖 自动: 开</span>' : '🤖 自动: 关';
    }

    function _syncSpeedButton() {
        const speedBtn = document.getElementById('btn-battle-speed');
        if (!speedBtn) return;
        const speed = BE().getBattleSpeed?.() || 1;
        speedBtn.innerHTML = `⏩ 速度: ${speed}X`;
    }

    function _enterNextAbyssFloor(floorFallback = 1) {
        if (_transitioningAbyssNext) return;
        _transitioningAbyssNext = true;

        close();
        const next = window.GG.GameEngine.enterAbyssLayer();
        if (!next?.success) {
            _transitioningAbyssNext = false;
            window.GG.UIManager?.showToast?.(next?.error || '进入下一层失败', 'error');
            window.GG.UIManager?.showPage?.('abyss');
            return;
        }

        // 与 AbyssUI.handleStart 一致：切后台页后直接打开战斗UI
        window.GG.UIManager?.showPage?.('stages');
        const stageId = next?.battleState?.stageConfig?.id || `abyss_${next?.battleState?.stageConfig?.floor || floorFallback + 1}`;
        open(stageId, true);
    }

    // ===== 事件绑定 =====
    function _bindEvents() {
        EB().on('battle:victory', onVictory);
        EB().on('battle:defeat', onDefeat);
        EB().on('battle:abyss_victory', onAbyssVictory);
        EB().on('battle:boss_phase2', onBossPhase2);
        // 关键修复：敌方回合结束后引擎切回 player_turn，需刷新 UI
        EB().on('battle:player_turn', onPlayerTurn);
        // 敌方行动时更新单位状态（显示受击后血条等）
        EB().on('battle:action', onBattleAction);
        EB().on('battle:skip', onSkip);
        // 自动战斗响应
        EB().on('battle:auto_action', onAutoAction);

        EB().on('battle:speed_changed', _syncSpeedButton);

        const exitBtn = document.getElementById('btn-battle-exit');
        if (exitBtn) exitBtn.onclick = close;
        const autoBtn = document.getElementById('btn-battle-auto');
        if (autoBtn) {
            autoBtn.onclick = () => {
                BE().toggleAutoBattle();
                _syncAutoButton();
                _refreshUnits(); // 刷新技能栏（自动状态下禁用手动技能）
            };
        }
        const speedBtn = document.getElementById('btn-battle-speed');
        if (speedBtn) {
            speedBtn.onclick = () => {
                BE().cycleBattleSpeed?.();
                _syncSpeedButton();
            };
        }
    }

    function onPlayerTurn(actor) {
        // 敌方回合全部结束后，轮到玩家，刷新技能栏 + 单位状态
        _refreshUnits();
    }

    function onAutoAction(actorId, skillId) {
        // 自动行动应只在我方回合执行，避免异步延迟导致的错相位卡住
        const state = BE().getState();
        const actor = BE().getCurrentActor();
        if (!state || state.phase !== 'player_turn' || !actor || !actor.isAlly || actor.id !== actorId) {
            return;
        }

        const sd = window.GG.SkillData[skillId];
        if (!sd) {
            _animating = false;
            return;
        }

        _animating = true;
        const delay = BE().getScaledDelay?.(sd.type === 'ultimate' ? 400 : 300) || (sd.type === 'ultimate' ? 400 : 300);

        if (sd.type === 'ultimate') {
            BA().triggerUltimate(actor.element || 'fire');
        }

        setTimeout(() => {
            try {
                _doSkill(skillId);
            } catch (err) {
                _animating = false;
                console.error('[BattleUI] 自动战斗执行失败:', err);
            }
        }, delay);
    }

    function _showSkillNameFx(actor, skillId) {
        const card = _unitEls?.[actor?.id];
        if (!card) return;
        const sd = SD()?.[skillId] || window.GG.EnemySkillData?.[skillId] || { name: '普通攻击', icon: '⚔️' };

        document.querySelectorAll(`.skill-name-fx[data-unit-id="${actor.id}"]`).forEach(el => el.remove());

        const rect = card.getBoundingClientRect();
        const fx = document.createElement('div');
        fx.className = `skill-name-fx battle-float-layer ${actor?.isAlly ? 'ally' : 'enemy'}`;
        fx.dataset.unitId = actor.id;
        fx.style.left = `${rect.left + rect.width / 2}px`;
        fx.style.top = `${Math.max(12, rect.top - 18)}px`;
        fx.innerHTML = `
            <span class="skill-name-fx-icon">${sd.icon || '⚔️'}</span>
            <span class="skill-name-fx-text">${sd.name || '技能'}</span>`;
        document.body.appendChild(fx);
        setTimeout(() => fx.remove(), BE().getScaledDelay?.(1050) || 1050);
    }

    function onBattleAction(actor, skillId, result) {
        _showSkillNameFx(actor, skillId);

        // 敌方执行完一个技能后，播放动画并刷新血条
        if (!actor.isAlly && result) {
            BA().playAnimationSequence(result.animations, _unitEls, () => {
                _refreshUnits();
            });
            result.log.forEach(entry => _addLog(entry));
        }
    }

    function onSkip(unit) {
        _addLog({ type: 'skip', unit: unit.name, reason: '控制效果' });
    }

    function onVictory(rewards) {
        if (_resultModalShown) return;
        _resultModalShown = true;
        setTimeout(() => {
            _showResultModal(true, rewards, false);
            if (_currentStageId) GE().markStageCleared(_currentStageId, BE().getState()?.turn || 0);
        }, BE().getScaledDelay?.(600) || 600);
    }

    // ====== 新增：深渊专用胜利处理 ======
    function onAbyssVictory(data) {
        if (_resultModalShown) return;
        _resultModalShown = true;
        setTimeout(() => {
            const isAuto = !!BE().getState()?.isAuto;
            const floor = BE().getState()?.stageConfig?.floor || data?.floor || 1;
            const choices = Array.isArray(data?.choices) ? data.choices : [];
            if (data?.nextStep?.type === 'reward' && choices.length) {
                _showAbyssRewardChoices(data, floor);
                return;
            }
            if (isAuto) {
                _enterNextAbyssFloor(floor);
                return;
            }
            _showResultModal(true, data?.rewards, true);
        }, BE().getScaledDelay?.(600) || 600);
    }

    function onDefeat(config) {
        if (_resultModalShown) return;
        _resultModalShown = true;
        // 如果是从深渊发出的 defeat，带有 isAbyss: true
        const isAbyss = config?.isAbyss || false;
        setTimeout(() => _showResultModal(false, null, isAbyss), BE().getScaledDelay?.(600) || 600);
    }

    function onBossPhase2(enemy) {
        const card = _unitEls[enemy.id];
        if (card) BA().pulse(card, 'boss-phase2', 800);
        _addLog({ type: 'system', message: `⚠️ ${enemy.name} 进入了狂暴模式！` });
    }

    function _rarityMeta(rarity) {
        const meta = window.GG.AbyssData?.rogue?.rarityMeta?.[rarity] || {};
        return {
            label: meta.label || rarity || '白',
            color: meta.color || '#e5e7eb',
            icon: meta.icon || '◇',
        };
    }

    function _renderAbyssRewardCard(choice) {
        const meta = _rarityMeta(choice.rarity);
        const characterName = choice.characterId ? (CD()?.[choice.characterId]?.name || choice.characterId) : '';
        const poolText = choice.pool === 'character' && characterName ? `${characterName} 入池` : '通用选项';
        return `
            <button class="abyss-reward-card rarity-${_escapeHtml(choice.rarity || 'white')}" data-choice-id="${_escapeHtml(choice.choiceId || choice.id)}" style="--reward-color:${_escapeHtml(meta.color)}">
                <div class="abyss-reward-card-top">
                    <span class="abyss-reward-icon">${_escapeHtml(choice.icon || meta.icon)}</span>
                    <span class="abyss-reward-rarity">${_escapeHtml(meta.icon)} ${_escapeHtml(meta.label)}</span>
                </div>
                <div class="abyss-reward-name">${_escapeHtml(choice.name || '未知回响')}</div>
                <div class="abyss-reward-target">${_escapeHtml(choice.target || poolText)} · ${_escapeHtml(poolText)}</div>
                <div class="abyss-reward-desc">${_escapeHtml(choice.description || '')}</div>
            </button>`;
    }

    function _showAbyssRewardChoices(data, floor) {
        EB().off('battle:victory', onVictory);
        EB().off('battle:defeat', onDefeat);
        EB().off('battle:abyss_victory', onAbyssVictory);

        document.querySelectorAll('.battle-result-overlay').forEach(el => el.remove());
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay battle-result-overlay abyss-reward-overlay';
        const choices = Array.isArray(data?.choices) ? data.choices : [];
        const isBossGoldReward = choices.length > 0 && choices.every(choice => choice?.rarity === 'gold');
        overlay.innerHTML = `
            <div class="abyss-reward-modal">
                <div class="abyss-reward-kicker">第 ${floor} 层通关 · ${isBossGoldReward ? '首领赏金' : '构筑节点'}</div>
                <div class="abyss-reward-title">${isBossGoldReward ? '选择一个金色深渊回响' : '选择一个深渊回响'}</div>
                <div class="abyss-reward-subtitle">自动战斗已暂停。选择后效果立即写入本局深渊，并对全队生效。</div>
                <div class="abyss-reward-grid">
                    ${choices.map(_renderAbyssRewardCard).join('')}
                </div>
                <div class="abyss-reward-hint">角色构筑只决定是否入池；一旦选择，奖励就是当前深渊局的全队效果。</div>
            </div>`;
        document.body.appendChild(overlay);

        overlay.querySelectorAll('.abyss-reward-card').forEach((card, idx) => {
            card.addEventListener('click', () => {
                const choiceId = card.dataset.choiceId;
                if (!choiceId || card.disabled) return;
                overlay.querySelectorAll('.abyss-reward-card').forEach(btn => { btn.disabled = true; });
                const result = window.GG.AbyssSystem?.chooseReward?.(choiceId, choices[idx]);
                if (!result?.success) {
                    overlay.querySelectorAll('.abyss-reward-card').forEach(btn => { btn.disabled = false; });
                    window.GG.UIManager?.showToast?.(result?.error || '选择奖励失败', 'error');
                    return;
                }
                window.GG.UIManager?.showToast?.(`获得深渊回响：${result.reward?.name || '未知奖励'}`, 'success');
                overlay.remove();
                _showResultModal(true, data?.rewards, true);
            });
        });
    }

    function _showResultModal(isVictory, rewards, isAbyss = false) {
        // 清理战斗事件监听
        EB().off('battle:victory', onVictory);
        EB().off('battle:defeat', onDefeat);
        EB().off('battle:abyss_victory', onAbyssVictory);

        document.querySelectorAll('.battle-result-overlay').forEach(el => el.remove());
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay battle-result-overlay';

        let rewardHtml = '';
        if (isVictory && rewards) {
            rewardHtml = `
            <div style="margin:16px 0;text-align:left">
                ${rewards.gold ? `<div class="reward-item">🪙 获得金币 <strong>+${rewards.gold}</strong></div>` : ''}
                ${rewards.diamonds ? `<div class="reward-item">💎 获得星尘晶 <strong>+${rewards.diamonds}</strong></div>` : ''}
                ${rewards.exp ? `<div class="reward-item">✨ 获得经验 <strong>+${rewards.exp}</strong></div>` : ''}
                ${rewards.relicDrop ? `<div class="reward-item" style="color:#fbbf24">💎 获得遗物 <strong>[${rewards.relicDrop.rarity}星] ${(window.GG.RelicSlots || []).find(s => s.id === rewards.relicDrop.slotId)?.name || ''}</strong></div>` : ''}
            </div>`;
        }

        // 深渊模式胜利弹窗专用结构
        if (isAbyss && isVictory) {
            const floor = BE().getState()?.stageConfig?.floor || 1;
            overlay.innerHTML = `
            <div class="battle-result-modal result-popup victory abyss-result">
                <div class="result-title">🌀 虚空之塔 第 ${floor} 层 通关！</div>
                ${rewardHtml}
                <div style="display:flex;gap:10px;margin-top:16px;flex-direction:column;">
                    <button class="btn btn-primary" id="btn-abyss-next">⚔️ 继续挑战 第 ${floor + 1} 层</button>
                    <button class="btn btn-ghost" id="btn-abyss-leave">🏕️ 暂离休息 (保存状态)</button>
                </div>
            </div>`;
            document.body.appendChild(overlay);

            // 继续下一层
            overlay.querySelector('#btn-abyss-next').onclick = () => {
                const nextBtn = overlay.querySelector('#btn-abyss-next');
                const leaveBtn = overlay.querySelector('#btn-abyss-leave');
                if (nextBtn) nextBtn.disabled = true;
                if (leaveBtn) leaveBtn.disabled = true;

                overlay.remove();
                _enterNextAbyssFloor(floor);
            };
            // 暂离
            overlay.querySelector('#btn-abyss-leave').onclick = () => {
                overlay.remove();
                close();
                window.GG.UIManager.showPage('abyss');
            };
            return;
        }

        // 默认结算弹窗（普通关卡胜利 / 失败）
        overlay.innerHTML = `
      <div class="battle-result-modal result-popup ${isVictory ? 'victory' : 'defeat'}">
        <div class="result-title">${isVictory ? '🏆 胜利！' : '💀 失败'}</div>
        <p style="color:#94a3b8;font-size:0.85rem;margin-bottom:8px">${isVictory ? '所有敌人已被击败！' : '队伍全灭，再接再厉！'}</p>
        ${rewardHtml}
        <div style="display:flex;gap:10px;margin-top:16px">
          ${isVictory ? '' : `<button class="btn btn-primary" id="btn-retry">再次挑战</button>`}
          <button class="btn btn-ghost" id="btn-back-stages" style="flex:1">返回关卡</button>
        </div>
      </div>`;
        document.body.appendChild(overlay);

        // 普通关卡胜利后自动触发战后对话（若有）
        if (isVictory && !isAbyss && _currentStageId) {
            const postKey = _currentStageId + '_post';
            const hasPost = !!(window.GG.DialogueUI?.hasScript(postKey));
            if (hasPost) {
                // 先隐藏结算弹窗
                overlay.style.display = 'none';
                // 隐藏战斗界面，避免遮挡对话遮罩（双保险：z-index 已提升，此处确保 battle-screen 不在顶层）
                const screen = document.getElementById('battle-screen');
                if (screen) screen.style.display = 'none';
                const giftHookFn = () => _tryGrantChapterGift(_currentStageId);
                window.GG.DialogueUI.start(postKey, () => {
                    // 对话结束后再次安全检查（跳过时 giftHook 可能未触发）
                    _tryGrantChapterGift(_currentStageId);
                    close();
                    window.GG.UIManager.showPage('stages');
                }, { giftHook: giftHookFn });
            } else {
                // 无战后对话，直接检查赠送
                _tryGrantChapterGift(_currentStageId);
            }
        }

        overlay.querySelector('#btn-back-stages')?.addEventListener('click', () => {
            overlay.remove();
            close();
            // 失败如果是深渊强制退回深渊大厅
            window.GG.UIManager.showPage(isAbyss ? 'abyss' : 'stages');
        });
        overlay.querySelector('#btn-retry')?.addEventListener('click', () => {
            overlay.remove(); close();
            if (isAbyss) window.GG.UIManager.showPage('abyss'); // 全灭必须从头开始，退回深渊主页点手动重置
            else open(_currentStageId);
        });
    }

    function close() {
        const screen = document.getElementById('battle-screen');
        if (screen) screen.style.display = 'none';
        BE().endBattle();
        EB().off('battle:victory', onVictory);
        EB().off('battle:defeat', onDefeat);
        EB().off('battle:player_turn', onPlayerTurn);
        EB().off('battle:action', onBattleAction);
        EB().off('battle:skip', onSkip);
        EB().off('battle:auto_action', onAutoAction);
        EB().off('battle:boss_phase2', onBossPhase2);
        EB().off('battle:speed_changed', _syncSpeedButton);
        _transitioningAbyssNext = false;
    }

    return { open, close };
})();
