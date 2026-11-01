# Android CI26 定向修复

精确提交 c9c8d0f82305d58a017a8ba3026ab62c812e9e22，run 41319276822。原生自动回图已有 completed-room-auto-return 图及 JSON 成功证据，但之后驱动退出到主界面再返回遗境时，真实 UI 正常保留背包标签。末态 phase=room，屏幕为背包，只有探索/背包/构筑标签与背包操作；房间专属 ExtractionAdvance 不存在。

根因是测试驱动混淆模型 phase 与当前显示子页，不是自动回图或房间按钮丢失。修复仅涉及 smoke_test.py 和对应 Python 驱动测试：回图助手先经真实 ADB 点击探索标签，等待新 seq 的地图或房间操作，再根据实际 phase 点击前往地图。已经显示地图时不多点；不放宽资产、可交互内容或地图真实显示断言。

定向 Python 驱动检查 101 项通过，包含 bag/build × room/route、拒绝旧 seq、已显示地图无需点击；py_compile 通过。此为离线驱动契约，不替代下一次正式 Android 真实输入验证。生产 753 个文件与原 86 套绿色快照逐文件相同；只更新两个验证文件，不重复无关全量。

生产 SHA256: 99c8bfc8c85ab678dfb5ab9bab7814f172600bffc0495fa30f011b0c7804962b

更新后验证 SHA256: 9cb6bc6f424ce20d7784101e4ebbfcb1ef5edef46e85bfd72032582ddbaa47cf
