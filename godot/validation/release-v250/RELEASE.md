# 2.5.0 正式发布记录

2026-11-01 15:32:03 UTC 发布，版本 2.5.0（20500）。固定正式渠道、包名与签名保持。

- 提交与标签：`28e15c46079995db7c05c84d3a0427c8907f660f` / `android-v2.5.0`
- [正式发布页](https://github.com/Catfish872/gachaWeb/releases/tag/android-v2.5.0) / [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.5.0/universal.apk)
- [签名发布 CI28](https://github.com/Catfish872/gachaWeb/actions/runs/41321550221)：两个任务成功。
- APK 138305721 字节；SHA256 `b776f6511faf8b3db79ab3e94e91179c1d1b28b97a652bcd8c3d01a024ac0004`。
- 固定证书 SHA256 `10fae1fe7586e79e17dc925b42fcba5b2bfe2907729df113bce917cc521c8f56`；APK 签名 v2/v3、包名、版本、权限、SDK、ARM 架构与资源检查通过。

## 已验证范围

生产 753 文件 SHA256 `99c8bfc8c85ab678dfb5ab9bab7814f172600bffc0495fa30f011b0c7804962b` 与已完成的 86 套本地回归、实际桌面界面审阅和最终经济报告一致。经济为 3328 路线、126970 场战斗、零审计错误，证据见 [经济报告](../expedition-v250/ECONOMY.md)。

[Android CI27](https://github.com/Catfish872/gachaWeb/actions/runs/41320178121) 使用 API35 x86_64 模拟器和 Mobile/Vulkan，实际走过仓库手势、物品锁、搜索暂停、地图与自动回图、抽卡后台恢复、十连跳过、套装推荐及定向选择。同目录 JSON 为该次真实运行证据。该次流程在主线关卡探针遗漏面板控件处停止；Android 遗物实战获得、推荐预览取消及其后的三个恢复场景未完成，整体原生任务记录为失败。桌面流程和探针的定向检查为另一个验证层级。

CI28 对生产文件精确枚举并校验上述固定总哈希及版本后复用已有证据，直接执行固定签名构建；没有重跑原生交互。该复用仅匹配此版本和此 753 文件内容，其他版本或生产变更进入常规验证路径。发布结论为固定签名 APK 已通过构建校验并正式上传，原生覆盖边界如上保留。

## 后续检查策略

按修改范围执行必要回归及界面视觉审阅，代码完成后的测试安排以十分钟为预算，复用相同生产哈希的有效证据。未执行场景明确记录，签名和发布身份检查持续保留。
