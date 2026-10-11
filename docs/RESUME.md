# 续接记录

更新：2026-10-12。已执行兼容架构改造；不要重新搭工程，也不要删除“原尺寸项变成档位入口”这个核心要求。

## 当前交付

- 版本：0.2.0-alpha，目标 WoW 12.1（120100）与 EUI 9.3 / 9.4。
- 核心模型、游戏运行层、设置宿主、动作条、冷却组、原尺寸控件适配已分离。私有 EUI 依赖集中在 Integrations/EUI。
- v9.4 使用官方 Plugin API 注册独立设置分区；v9.3 保留旧内嵌入口。
- 保留三档文字/图标/矩形、五组绑定、预览/应用/取消/恢复、原尺寸入口替换；没有退成两套数值输入。
- Store schema 2 分离用户档位和带来源标记的接管记录；schema 1 校验后迁移。未知来源/版本不盲恢复，模块混装和控件失效会暂停。
- 独立模块可部分工作；无法证明冻结组边界、关联锚定和整体重叠时停止关联事务。
- 无 EUI 时仍加载保存数据与状态命令。仍不提供脱离 EUI 的目标元素。
- 未改 IconNameTooltip、项目根 README、tools。GitHub 仓库采用用户确认的产品名 dingying-focus（定影·聚焦）；插件目录和 SavedVariables 名称保持 EllesmereUIGradient。

## GitHub 与上传方式

- 公开源码仓库：[sirius-qfk/dingying-focus](https://github.com/sirius-qfk/dingying-focus)，分支 main。
- 本次通过已登录的 Arc 浏览器分目录提交；本机 Git 仍受 Xcode 许可阻挡，本地没有初始化 Git，也未配置远程或自动同步。后续本地修改不会自动上传。
- 上传范围是本插件源码、文档、兼容契约、开发脚本和测试；排除 node_modules、dist、系统缓存及旁边的 Tooltip 项目。
- 源码上传不等于发布安装包；尚未创建 GitHub Release，也未完成游戏内验收。

## 验证结果

- Lua 5.1 语法：17 个运行文件、5 个测试文件通过。
- 25 单元 + 17 集成 + 24 生命周期 + 28 兼容测试，共 **94 项模拟测试**。
- v9.4 的 24 个官方源文件与固定 Git blob SHA 匹配；记录在 contracts/eui-9.4.json。
- 安装包：dist/EllesmereUIGradient-0.2.0-alpha.zip。保留旧 0.1.0-alpha 包；新包不含 EUI 源码、Node 依赖和测试。
- **未在真实 WoW 客户端测试或安装。不要称“完整兼容已验收”或“更新永不受影响”。**

## 下次先做什么

1. 备份 WTF，在测试配置验证 v9.4 的官方设置页、15 个原尺寸入口、缓存/折叠与实际 Resize；再回归 v9.3。
2. 重点观察 EUI 是否发出插件违规/更新提示。官方 Plugin API 不支持接管原控件和私有元素；现实现仍属实验性私有适配。失败就不能完整发布，不得改成双输入降级或绕过上游保护。
3. 完成 [游戏验收清单](IN_GAME_CHECKLIST.md)，包括 taint、真实战斗、重载、配置切换、旧数据升级/恢复。没有客户端就保留“待验证”，请求具体报错与截图后修复。
4. 修复后执行 `npm run package`，确保交付最新 ZIP；真实验收通过后才考虑移除 alpha。

## 入口与环境

- [简版产品](MVP.md) · [安装使用](../README.md) · [开发地图](ARCHITECTURE.md) · [兼容记录](COMPATIBILITY.md)
- 源码缓存：/private/tmp/eui-compat-audit.bvathQ；可运行 `npm run audit:upstream -- /private/tmp/eui-compat-audit.bvathQ`。临时目录丢失就重新获取固定 v9.4，别误用 main。
- Node 可用；测试使用 Fengari 0.1.4 和 luaparse 0.3.1。游戏不需要 Node。
- Git/brew 曾受 Xcode license 阻挡，不代用户接受许可。
- 后续 authored 修改使用 apply_patch。保留目录名 EllesmereUIGradient 和 SavedVariables 名称以免丢配置。
