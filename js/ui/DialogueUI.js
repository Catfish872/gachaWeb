// 剧情对话 UI 引擎 —— 立绘展示 / 逐句推进 / 旁置跳过 / 打字机效果
// 脚本数据结构（DialogueData）：
//   key: "stageId_timing"，timing = 'pre' | 'post'
//   脚本为数组，每条目：
//     { speaker, text, portrait, element?, giftHook? }
//     - speaker: 'narrator' 为旁白；其它为角色 id 或名称
//     - portrait: 立绘标识，对应 CharacterData[id].image；null 则隐藏立绘区（旁白/无立绘）
//     - element: 元素着色标记（fire/water/thunder/wind），用于说话人名称着色
//     - giftHook: true 表示播放到此条目时触发赠送回调（用于赠送角色剧情）
window.GG = window.GG || {};
window.GG.DialogueUI = (function () {
    const CD = () => window.GG.CharacterData;
    const S = () => window.GG.SaveSystem;
    const EB = () => window.GG.EventBus;
    const DD = () => window.GG.DialogueData;

    let _overlay = null;
    let _scriptKey = null;       // 当前播放的脚本 key（用于标记已读）
    let _script = null;          // 当前播放的脚本数组
    let _index = 0;              // 当前台词索引
    let _onComplete = null;      // 全部播放完的回调
    let _typewriterTimer = null; // 打字机定时器
    let _isTyping = false;       // 打字机是否进行中
    let _currentPortraitId = null; // 当前显示的立绘 id（用于切换淡入淡出）
    let _giftHookFn = null;      // 赠送钩子回调（由触发方注入）

    const TYPE_SPEED = 32;      // 每字毫秒数
    const PORTRAIT_FADE = 250;  // 立绘切换淡出时间

    // 获取脚本：支持传入脚本数组或脚本 key（查 DialogueData）
    function _resolveScript(scriptOrKey) {
        if (Array.isArray(scriptOrKey)) return scriptOrKey;
        if (typeof scriptOrKey === 'string') return DD()?.[scriptOrKey] || null;
        return null;
    }

    // 标记剧情已读
    function _markSeen(scriptKey) {
        if (typeof scriptKey !== 'string') return;
        const save = S().get();
        if (!save.dialogueSeen) save.dialogueSeen = {};
        const wasSeen = !!save.dialogueSeen[scriptKey];
        save.dialogueSeen[scriptKey] = true;
        if (!wasSeen) S().save();
    }

    // 开启对话
    // scriptOrKey: 脚本数组或 DialogueData 的 key
    // onComplete: 全部播放完的回调
    // options: { giftHook: fn(stageId) } 赠送钩子回调
    function start(scriptOrKey, onComplete, options = {}) {
        const script = _resolveScript(scriptOrKey);
        if (!script || script.length === 0) {
            // 无脚本，直接完成
            typeof onComplete === 'function' && onComplete();
            return;
        }
        // 避免重复打开
        if (_overlay) { close(); }

        _script = script;
        _scriptKey = (typeof scriptOrKey === 'string') ? scriptOrKey : null;
        _index = 0;
        _onComplete = onComplete || null;
        _giftHookFn = options.giftHook || null;
        _currentPortraitId = null;

        _build();
        _renderLine();
    }

    // 构建 DOM
    function _build() {
        const overlay = document.createElement('div');
        overlay.className = 'dialogue-overlay';
        overlay.innerHTML = `
            <div class="dialogue-chapter-label" id="dialogue-chapter-label"></div>
            <button class="dialogue-skip-btn" id="dialogue-skip-btn">跳过 ⏩</button>
            <div class="dialogue-portrait-area" id="dialogue-portrait-area">
                <img class="dialogue-portrait" id="dialogue-portrait" style="display:none" alt="">
            </div>
            <div class="dialogue-box">
                <div class="dialogue-speaker" id="dialogue-speaker"></div>
                <div class="dialogue-text" id="dialogue-text"></div>
                <div class="dialogue-continue-hint" id="dialogue-continue-hint">▶ 点击继续</div>
            </div>
        `;
        document.body.appendChild(overlay);
        _overlay = overlay;

        // 点击推进（点击遮罩任意处）
        overlay.addEventListener('click', (e) => {
            // 跳过按钮单独处理
            if (e.target.id === 'dialogue-skip-btn') return;
            _advance();
        });

        // 跳过按钮
        overlay.querySelector('#dialogue-skip-btn').addEventListener('click', (e) => {
            e.stopPropagation();
            skip();
        });

        // 阻止冒泡，避免遮罩点击推进
        overlay.querySelector('.dialogue-box').addEventListener('click', (e) => {
            e.stopPropagation();
            _advance();
        });
    }

    // 渲染当前行
    function _renderLine() {
        if (!_overlay || !_script) return;
        const line = _script[_index];
        if (!line) { _finish(); return; }

        // 章节标签（取脚本 key 不可得，此处用通用占位）
        const label = _overlay.querySelector('#dialogue-chapter-label');
        if (label) label.textContent = line._chapterLabel || '';

        // 说话人
        const speakerEl = _overlay.querySelector('#dialogue-speaker');
        speakerEl.className = 'dialogue-speaker';
        if (line.speaker === 'narrator' || !line.speaker) {
            speakerEl.classList.add('narrator');
            speakerEl.textContent = '旁白';
        } else {
            speakerEl.textContent = line.speakerName || _resolveSpeakerName(line.speaker);
            if (line.element) speakerEl.classList.add('element-' + line.element);
        }

        // 立绘
        _updatePortrait(line.portrait);

        // 台词打字机
        _typewriter(line.text || '');

        // 隐藏"继续"提示（打字机进行中）
        const hint = _overlay.querySelector('#dialogue-continue-hint');
        hint.classList.add('hidden');

        // 赠送钩子：播放到此行时触发（独立于点击推进，确保赠送发生在剧情中段）
        if (line.giftHook && typeof _giftHookFn === 'function') {
            _giftHookFn();
        }
    }

    // 解析说话人名称：若 speaker 是角色 id，取 CharacterData 名称
    function _resolveSpeakerName(speaker) {
        const char = CD()?.[speaker];
        return char?.name || speaker;
    }

    // 切换立绘
    function _updatePortrait(portraitId) {
        const area = _overlay.querySelector('#dialogue-portrait-area');
        const img = _overlay.querySelector('#dialogue-portrait');

        // 无立绘：隐藏
        if (!portraitId) {
            img.style.display = 'none';
            area.classList.remove('is-encore');
            _currentPortraitId = null;
            return;
        }

        const char = CD()?.[portraitId];
        const src = char?.image;

        // 无立绘资源：隐藏并占位（无立绘角色）
        if (!src) {
            img.style.display = 'none';
            area.classList.remove('is-encore');
            _currentPortraitId = null;
            return;
        }

        // 同一立绘不重复切换
        if (_currentPortraitId === portraitId) {
            img.style.display = '';
            return;
        }

        // 切换：旧立绘淡出再换源淡入
        const doSwap = () => {
            img.src = src;
            img.style.display = '';
            img.classList.remove('exiting');
            // 强制重排以重启动画
            void img.offsetWidth;
        };

        if (_currentPortraitId && img.style.display !== 'none') {
            img.classList.add('exiting');
            setTimeout(doSwap, PORTRAIT_FADE);
        } else {
            doSwap();
        }
        _currentPortraitId = portraitId;
        area.classList.remove('is-encore');
    }

    // 打字机效果
    function _typewriter(text) {
        _clearTypewriter();
        _isTyping = true;
        const textEl = _overlay.querySelector('#dialogue-text');
        let i = 0;
        const render = () => {
            if (i <= text.length) {
                textEl.innerHTML = text.slice(0, i) + '<span class="dialogue-cursor"></span>';
                i++;
                _typewriterTimer = setTimeout(render, TYPE_SPEED);
            } else {
                // 打完
                textEl.innerHTML = text;
                _isTyping = false;
                _typewriterTimer = null;
                // 显示"继续"提示
                const hint = _overlay.querySelector('#dialogue-continue-hint');
                if (hint) hint.classList.remove('hidden');
            }
        };
        render();
    }

    function _clearTypewriter() {
        if (_typewriterTimer) {
            clearTimeout(_typewriterTimer);
            _typewriterTimer = null;
        }
        _isTyping = false;
    }

    // 推进：点击时若打字机进行中则瞬间显示完整文本，否则进入下一句
    function _advance() {
        if (!_overlay) return;
        if (_isTyping) {
            // 瞬间显示完整当前文本
            _clearTypewriter();
            const line = _script[_index];
            const textEl = _overlay.querySelector('#dialogue-text');
            textEl.innerHTML = line?.text || '';
            const hint = _overlay.querySelector('#dialogue-continue-hint');
            if (hint) hint.classList.remove('hidden');
            return;
        }
        _index++;
        if (_index >= _script.length) {
            _finish();
        } else {
            _renderLine();
        }
    }

    // 完成
    function _finish() {
        // 标记剧情已读
        if (_scriptKey) _markSeen(_scriptKey);
        const cb = _onComplete;
        close();
        if (typeof cb === 'function') cb();
    }

    // 跳过整段对话
    function skip() {
        if (!_overlay) return;
        _clearTypewriter();
        _finish();
    }

    // 关闭并清理
    function close() {
        _clearTypewriter();
        if (_overlay) {
            _overlay.remove();
            _overlay = null;
        }
        _script = null;
        _scriptKey = null;
        _index = 0;
        _onComplete = null;
        _giftHookFn = null;
        _currentPortraitId = null;
    }

    // 查询某 key 是否存在对话脚本
    function hasScript(scriptOrKey) {
        return !!_resolveScript(scriptOrKey);
    }

    // 查询某剧情 key 是否已读（重复进入不重复触发赠送判定可用）
    function isSeen(scriptKey) {
        if (typeof scriptKey !== 'string') return false;
        return !!S().get()?.dialogueSeen?.[scriptKey];
    }

    return {
        start,
        skip,
        close,
        hasScript,
        isSeen,
    };
})();