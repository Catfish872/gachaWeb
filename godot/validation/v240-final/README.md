# 2.4 最终本地回归

2026-11-01 09:56 UTC，完整52套Godot测试及正常主场景生命周期通过；错误日志严格检查保留。运行前后生产与验证源码哈希一致，详见 `start-manifest.json` / `final-manifest.json`。

- Production SHA256: `7bc2da653f34001b116e42ddabaa9ecc0e376fff0df1d4ff5996d55e9f499794`
- Verification SHA256: `70c0a11b0a451e42c559f0ee8515527c76b86798eed0ce665f2f6a3ba8a99126`
- 生产范围702文件；排除既定3未发布实验OGG及其imports，所有5份原始MP3均保留。发布者仍须按最终差分清单核对。

证据：`aggregate.log`、`suite-results.json`、`scene-lifecycle.log`。额外手机尺寸843项（包含Atlas原图/精确region覆盖）、输入15项、Android驱动离线54项通过。`warehouse-scroll-gl.log` 为实际桌面OpenGL34项，不是Android模拟器结果。

## 已闭合真实缺陷

- 用药后详情旧按钮、实际估值显示、复杂背包排列、已选择物资UI与命中。
- 初始及满养成三人队战斗立绘在回合/盾/状态变化时尺寸保持；843项。
- 回收全价说明两Label重叠；最终161项及截图完整。
- 新无限深渊daily卡撑高横屏页面；修后mobile533项通过。
- 仓库grid内纵向拖动后首tap被吞：取消父滚动接管时的grid指针状态；修前33项1失败，修后34项及实际GL通过。对应前后日志保留。

原先一次GL横向放置拖动偶发异常未重复出现，旧日志保留；最终三轮同fixture完整UID/事件轨迹均通过，没有用延迟或删除断言掩盖。不可将后来确定的纵向滚动缺陷宣称为该偶发的已证根因。

## 头像与移动网更新

头像素材132、实际UI172、更新检查/安全80、更新布局57项已纳入52套。小卡使用人工审阅的Atlas裁剪，大战斗/对话立绘仍保留完整源图。Android实际Request允许计费网络，漫游保持单独保护；探针报告setter调用结果，driver将其作为必测。此证据不是已经完成的蜂窝APK下载。URL/大小/SHA256/安装确认安全门槛保留。

## 原生Android门槛

新driver已加入真实购药→两个精确UID多选→取消→移动模式横划不提交→单点指定格移动→实际纵向滚动超过5物理像素后首次点选。探针只读，保留正确Object.notification无super路径；自然长扫描后台暂停与三轮生命周期/签名门槛仍在。

## CI25 原生终态（2026-11-01 10:10 UTC）

正式提交 `e1275e3b37c0b8a5a6ab7ab848860c1c0c960f9e`，运行 `41295372451`：实际Android验证成功。独立核查434帧probe、JSON和截图，详见 `native-ci25-review.json`。

- 真实购入两个UID均独立勾选；取消多选不改资产。
- 移动模式横划保留坐标；明确单点才把同一药囊从(1,0)移到(4,1)。
- 仓库实际纵向滚动34.67物理像素后，第一次点击即切到药囊UID，无第二次补点。
- Back单条notification关闭菜单，overlay=0；三轮后台恢复全通过。
- 自然搜索首个尝试即覆盖：同UID暂停约6.8秒，恢复进度仍为0.315789473684211。
- 实际DownloadManager.Request允许metered，仍不允许roaming；没有执行蜂窝APK下载或绕过系统安装确认。
- 渲染器为Mobile/Vulkan，SwiftShader。原生环境为Android API35、x86_64模拟器，不是用户实体S23+。

本轮签名与正式发布由发布代理另行核实并记录；QA未改生产或降低任何原生门槛。
