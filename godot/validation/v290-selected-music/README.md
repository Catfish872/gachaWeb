# 用户选定雷队音乐

用户明确选定 Wasteland Overdrive 作为抽卡音乐，取消先前的抽卡候选，其余试听曲采用。

探索城门与街区采用 Electric City Part 1，裂隙核心采用 Electric City Part 2。观测塔、沉没雷塔采用 Dark Shrine Loop。雷队三人抽卡共享 Wasteland Overdrive；首领战独立采用 Colossal Boss Battle Theme。既有角色技能音效保持原样。

当前运行路由与署名位于 scripts/thunder_audio.gd。五首完整录音及许可证记录位于 assets/audio/content_v290/manifest.json 与 LICENSES.txt。原始素材、来源网页与下载校验位于 tools/audio/thunder_selected_sources/。构建命令为 python tools/audio/build_selected_thunder_audio.py。

保留作者完整循环、原速和乐器；首尾各5毫秒平滑，仅固定增益对齐至-22 LUFS并转为Ogg Vorbis。源文件、输出哈希、时长、采样数、响度、真峰值与接缝指标记录于 verification.json。技术检测与用户选择分开记录；助手未宣称主观听辨验收。

许可：Electric City为Tsorthan Grove的CC BY 4.0作品；Dark Shrine Loop为qubodup与yd的CC0作品；两首Matthew Pablo作品为CC BY 3.0，鸣谢保留其姓名、官网、曲名、许可、来源及改动说明。

先前三首Jonathan Shaw和Cinematic intro soundtrack均退出雷队运行路由。历史来源资料保留供追溯。此次仅开发接入及验证，未打包发布。

验证：test_selected_thunder_audio_v290.gd 共84项通过，含5首源哈希、直接解码、导入缓存时长、响度、峰值、接缝、别名映射与完整鸣谢。运行前已重新导入Godot资源，日志 assets-test.log 与 import.log 均无错误。
