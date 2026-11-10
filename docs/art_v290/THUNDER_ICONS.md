# 雷城图标资源

本期配套图标共 42 张，采用与 2.8 版一致的手绘奇幻道具风格，覆盖莱莎、维珂、伊芙的 15 张技能与被动图标、12 张专属及共享祝福图标，以及三套遗物的 15 个部位。莱莎使用银甲、紫晶、雷刃，维珂使用黄铜、青绿皮革、弩箭与罗盘，伊芙使用象牙白、浅金、晴光伞与水滴宝石。

游戏资源位于 `godot/assets/content_v290/icons/skills/`、`blessings/`、`relics/`。每张图片均为独立生成的原创图像，统一以 384 × 384 的透明 PNG 交付，保留原始透明度；主体按比例适配 320 像素范围后居中留边。运行时图像合计 4,700,075 字节。

`thunder-icons-manifest.json` 保存稳定标识、对应名称、文件路径、原始文件名、原图与运行时文件的 SHA-256。完整生成描述保存在 `tools/thunder_icon_prompts_v290.json`，生成工具为内置图像生成工具。原始生成文件保持原位，交付目录包含游戏运行所需的全部图标文件。

从原始生成目录复现标准尺寸的命令为 `python tools/prepare_thunder_icons_v290.py --source-root /path/to/generated_images`，依赖 ImageMagick。验证命令为 `python tools/verify_thunder_icons_v290.py --sheets`，依赖 Pillow；它检查全部 42 条数据引用、文件唯一性、尺寸、透明度、留边和校验和。

验证记录与三张预览图位于 `godot/validation/v290-thunder/icons/`。预览同时展示 192 像素和 64 像素的显示效果，已逐张检查主体完整性、缩小后的辨识度与各套装配色。状态图标由独立的战斗状态资源接入。
