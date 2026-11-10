# 雷系音乐路由审阅

2026-11-10：根据用户选曲，三雷卡池通过 `raisa_reveal`、`vika_reveal`、`eve_reveal` 共用 Wasteland Overdrive，分别保留播放状态。雷城城郊与旧城采用 Electric City - Part 1，裂隙核心采用 Electric City - Part 2，天文台和沉塔的剧情及普通战斗场景采用 Dark Shrine Loop。

首领上下文统一选择 `thunder_boss`，对应 Colossal Boss Battle Theme，覆盖第五章、搜打撤、深渊，以及按首领敌人编号识别且缺少背景字段的战斗。搜打撤和深渊的非战斗探索保留三个区域的原有深度路由，分别使用 Electric City - Part 1、Electric City - Part 1、Electric City - Part 2。`thunder_audio.gd` 提供五首选定录音的映射及鸣谢，运行资源已重新导入。

验证使用 Godot 4.6.3 headless、Dummy 音频驱动和独立的可写 XDG 目录。`test_thunder_music_v290.gd` 通过 80 项检查，覆盖五首录音互异、全部音乐标识的解码、三雷卡池切换、功能页继承、暂停恢复、普通战斗、三种首领上下文和返回主页；实际播放器流的时长逐一对照新资产清单，确认使用重新导入的选定录音。`test_summon_music_v280.gd` 通过 97 项检查；`test_thunder_world_v290.gd` 通过 497 项检查；`test_thunder_world_ui_v290.gd` 通过 42 项检查。最终日志无错误或警告。测试为无声驱动运行验证，主观听感由试听确认流程覆盖。
