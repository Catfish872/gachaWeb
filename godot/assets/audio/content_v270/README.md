# 烬金灯火 · 2.7 音频

原创记谱与程序化音色合成，未使用外部旋律、录音或采样包。不是现场演奏录音，也不是音乐模型生成。归属当前 gachaWeb 内容包；不改变既有 CC0 音乐与其署名许可。

| ID | 曲名 | 结构 | 用途 |
|---|---|---|---|
| lantern_road | 烬金灯途 | D 小调，80 BPM，24 小节 / 72 秒 | 新主线、灰雪驿路 |
| lantern_hall | 铜廊流火 | D 小调，96 BPM，28 小节 / 70 秒 | 铜火内廊 |
| lantern_core | 炉心长明 | D 小调，112 BPM，32 小节 / 68.57 秒 | 炉心、章节 Boss |

温暖拨弦、低弦持续音、玻璃/链铃旋律动机，内廊和炉心增加低鼓律动。八小节和声展开，分段旋律应答；三轨共享动机但速度、配器密度与旋律音区不同。循环点为完整音频首尾，音符余尾与空间反射环绕写入开头，不使用尾部静音截断。混音约 -22 LUFS，峰值低于 -10 dBFS，留出战斗反馈空间。

## 接入

路径均为 `res://assets/audio/content_v270/{id}.ogg`。沿用现有音乐池与一秒交叉淡化；地图主题变化时换曲，补给、背包、祝福、弹窗不重置游标。不要替换旧主题地图曲库。

八个短反馈：`wick_ignite` 点灯、`chain_swing` 链挥、`thread_gather` 火丝、`ember_detonate` 被动引爆、`selin_basic` 普攻、`selin_skill` 技能、`selin_ultimate` 大招、`lantern_reveal` 章节灯印揭示。最后一个不是稀有掉落提示，不覆盖现有稀有度音效。

`ember_detonate` 在一次行动中只响一次（即使命中多敌），相对效果总线 -10 dB；其他效果建议 -3 dB。普通音效同时最多两声，低优先级引爆最多一声。大招不与同一角色的普攻/技能音重复触发。BGM不必为每个小反馈反复压低。

## 再生成与核验

在 Godot 目录执行：

```sh
python tools/audio/build_lantern_audio.py
python tools/audio/verify_lantern_audio.py
```

依赖 Python、numpy、scipy 与 ffmpeg/libvorbis。固定随机种子 270。Manifest 给出节拍、调性、路径、精确时长与循环点；verification.json 给出解码后峰值/RMS/LUFS与循环接缝检查。核验脚本额外在 `/tmp/lantern-v270-preview.wav` 生成三曲各八秒的试听拼接。静态检查通过不代表人耳审美验收，当前未标记主观试听通过。
