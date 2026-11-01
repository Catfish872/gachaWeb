# 2.4 最终本地回归

2026-11-01 09:41 UTC，完整49套Godot测试及正常主场景生命周期通过；错误日志严格检查保留。运行前后生产与验证源码哈希一致，详见 `start-manifest.json` / `final-manifest.json`。

- Production SHA256: `f8c802bb0a089511950bed8896186dfde60be1eef2c7baa4d31f51c90c62b0db`
- Verification SHA256: `d22ef9d0381914af9cd6b718baaa41829fccefacfb71fe44ffdb8ac4af48c609`
- 生产范围700文件；排除既定3未发布实验OGG及其imports，所有5份原始MP3均保留。发布者仍须按最终差分清单核对。

证据：`aggregate.log`、`suite-results.json`、`scene-lifecycle.log`。额外手机尺寸533项、输入15项、Android驱动离线51项通过。`warehouse-scroll-gl.log` 为实际桌面OpenGL34项，不是Android模拟器结果。

## 已闭合真实缺陷

- 用药后详情旧按钮、实际估值显示、复杂背包排列、已选择物资UI与命中。
- 初始及满养成三人队战斗立绘在回合/盾/状态变化时尺寸保持；843项。
- 回收全价说明两Label重叠；最终161项及截图完整。
- 新无限深渊daily卡撑高横屏页面；修后mobile533项通过。
- 仓库grid内纵向拖动后首tap被吞：取消父滚动接管时的grid指针状态；修前33项1失败，修后34项及实际GL通过。对应前后日志保留。

原先一次GL横向放置拖动偶发异常未重复出现，旧日志保留；最终三轮同fixture完整UID/事件轨迹均通过，没有用延迟或删除断言掩盖。不可将后来确定的纵向滚动缺陷宣称为该偶发的已证根因。

## 原生Android门槛

新driver已加入真实购药→两个精确UID多选→取消→移动模式横划不提交→单点指定格移动→实际纵向滚动超过5物理像素后首次点选。探针只读，保留正确Object.notification无super路径；自然长扫描后台暂停与三轮生命周期/签名门槛仍在。

本地结果不代表上述新流程已经Android通过。发布CI仍必须真实运行，失败时保留原门槛并诊断。
