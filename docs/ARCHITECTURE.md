# 开发地图

用户改梯度 → 绑定选择元素 → 引擎校验与事务 → 版本适配 → EUI 原生刷新。

## 改哪里

| 模块 | 职责 |
|---|---|
| Model / Bindings | 梯度、中心矩形、布局规则；不读 EUI |
| Runtime | WoW 接口版本、屏幕坐标、定时与战斗、后置钩子 |
| Store / Journal | 用户档位、版本标记的接管记录、所有权、条件恢复 |
| Engine | 预览、应用、取消、上下文、失败隔离与事务 |
| UI | 自己的梯度编辑器和参考框；不读取 EUI 私有字段 |
| Integrations/EUI/Compatibility | 精确版本清单、能力检查、恢复契约 |
| Integrations/EUI/ActionBars / Cooldowns / Elements | 组件解析、字段、原生刷新、位置、变更通知 |
| Integrations/EUI/SettingsHost | v9.4 官方插件页；v9.3 旧入口；折叠生命周期 |
| Integrations/EUI/NativeControls | 原尺寸控件替换成梯度入口，属于私有契约 |

版本共享同一契约时复用实现；不要为每次补丁复制整套适配器。替换原尺寸入口是必需项，不能因拆层改成两套数值设置。

## 数据和失败边界

- SavedVariables 名称不变。schema 2 的每个配置包含 `settings / enabled`（用户意图），以及 `applied = {contracts, leases, points}`（实际接管记录）。
- schema 1 全量校验后原子迁移，标记原写入者为 EUI 9.3；来源未知的记录留存，不按当前安装版本猜测来源。旧插件不能直接读取新 schema。
- 所有权要求同一运行期的表身份一致，且值仍等于最后投影值。重载后仅能重新解析并比较值，无法检测同值换表。
- 某个原生模块存在租约冲突时冻结该模块；健康模块可以继续，但必须检查冻结组的实际边界。缺少边界、关联锚定或布局重叠则停止关联修改。
- 不知道如何恢复时保留记录，而不是盲写旧值。“暂停接管”和“恢复原设置”不是同一件事。
- 写入限非战斗。一次布局事务失败时回滚本次数值与位置；能力缺失在写入前判定。无逐帧全屏扫描。
- v9.4 设置页注册是官方 API；元素、原控件与折叠适配仍是私有依赖。完整发布要求两部分都通过实机验收。

## 验证

`npm run check` 检查 Lua 5.1 语法及 EUI 依赖隔离；`npm test` 运行模拟测试；`npm run package` 重跑检查并逐字节核验 ZIP。

源码审阅与版本状态见 [兼容记录](COMPATIBILITY.md)。实际游戏验收见 [清单](IN_GAME_CHECKLIST.md)；Fengari 模拟不能证明 taint、真实框体或上游 UI 正常。
