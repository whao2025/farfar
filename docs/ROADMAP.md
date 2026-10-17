# freepdf 项目路线图

## 当前版本：v0.4 (PDF编辑核心完成)

## 产品定位（编辑/改字）
> **编辑 PDF 的「识别字体 / 改字」主要对象是文字型 PDF**（如 Excel 导出、含文本层与嵌入字体的报表）；图片/扫描型走 OCR **作为兜底保留**。**表格型文字 PDF 的文本块与字号/字体恢复是优先打磨点**（listTextObjects 块定位精度、FontMatcher 精确匹配嵌入字体、PdfServiceRewriter 复用 fontInfo 原位替换）。

### ✅ 已完成 (v0.1-v0.4)
- [x] PDF查看/编辑/转换基础框架
- [x] 记账功能(解析/分类/确认/统计)
- [x] PDF编辑核心：fontInfo修复、screenToPdf坐标换算、Overlay点击放置、死代码清理
- [x] 缓存优化：HR 99.9%、AGENTS.md纪律化
- [x] 构建警告清零：153 → 0（try/catch + canIUse 全量收敛）

### 🔄 进行中 (v0.5) - 当前冲刺
- [x] 文字型 PDF 改字精度打磨 v0.5（页面点选定位已落地）：
  - [x] 改字入口从"序号列表对话框"改为**页面点选**：进入改字(tool=4) → 拉取当前页文本块矩形 → 虚线框标注 → 点击块 → 内联编辑面板（原文预填 + 字号折叠可选）
  - [x] `TextBlockInfo` 扩展 x/y/width/height/fontName；`runListTextObjects` 用 `charRects` 求块包围盒（P0 真机核验坐标系），无 charRects 按字号估宽兜底
  - [x] 字体/字号保留：worker ≥fontInfo 复用原位替换；主线程 FontMatcher 判定回退，面板显示"原字体（已匹配XX）/将回退"提示
  - [x] 预览浮层 derived from ops：确认后块框显示新文字，undo 自动清预览
  - [ ] M1 真机：click 命中 precision + charRects 坐标系核验（P0 遗留）
- [ ] 真机全流程验收 (TEST_CHECKLIST.md 7项)
- [ ] ProfileTab 我的栏目完善 (About/Feedback/Storage/Backup/Help/License)
- [ ] ProfileTab 字段理顺 + 编译0警告

### 🎨 UI 玻璃化打磨（未完成进程，2026-08-11 批）
> 依据官方规范 + 线上案例（custom-dialog-gathers/SwitchChart/MultiDeviceMusic，来自 gitee harmonyos_samples/codelabs 迁移版）参考（评审已核验），4 阶段必做 + 可选。每阶段一个 Conventional Commit（`feat(ui): …`），改动集中完成，遵守 DeepSeek 前缀缓存纪律。
- [x] 阶段1 Token 校准：SDK `common.d.ts` 实测五档 `BlurStyle`（COMPONENT_ULTRA_THIN=8/THIN=9/REGULAR=10/THICK=11/ULTRA_THICK=12），`GlassTokens.ets` 五档映射已核（BLUR→REGULAR、BLUR_TOOLBAR→ULTRA_THIN、BLUR_BUTTON→THIN、BLUR_PANEL→THICK、BLUR_MODAL→ULTRA_THICK）；全量 `backgroundBlurStyle(GlassTokens.*)` 28 处引用已 grep，无硬编码新增。
- [x] 阶段2 记账卡片：`BudgetCard.ets` 进度填充两处（渐变条/分段点）挂 `.animation({duration:600, curve: curves.springMotion(0.6,0.9,0)})` + `import curves from '@ohos.curves'`；`TrendCard.ets` 不迁 Canvas，新增 `barGradient()`（今日 ACCENT_BLUE→SKY / 超支 DANGER→WARN / 最高柱 PURPLE→CYAN / 其余 NEUTRAL）+ 超支日金额标红 + 柱 `.animation(springMotion)`。
- [x] 阶段3 弹窗收敛：`RecentFilesPanel.ets` 两处原生 `showDialog` 改 `openCustomDialog` 玻璃自绘（`confirmDialog()` @Builder + `openConfirmDialog/closeConfirmDialog`，取消/删除双按钮 + GlassButton），`resp.index!==1` 语义等价迁移（`pendingConfirm` 回调 + `doDelete/doBatchDelete` 抽出）；`closeCustomDialog` 已包 try/catch（编译 0 警告）。禁 `CustomDialogController`。
- [x] 阶段4 悬浮球按压：`SmartReachBar.ets` 三 Ball 加 `stateStyles({pressed})`（scale 0.9 + brightness 1.1 + opacity 0.9）；**未给 Ball 加个体手势**；motion 双订阅原样保留。
- [ ] （可选）阶段5 底部导航：`Home.ets` 已自绘 `capTabBar()`（`barHeight(0)`+透明底），indicator 已有隐式动画（`Home.ets:465` `.animation`），仅评估是否换 `springMotion` 调曲线；**Tabs 保活放弃**（无官方 keep-alive，改文档化各 tab init 幂等）。

**禁抄清单**：`ImmersiveMaterial`/`systemMaterial`/`backdropBlur`（API26+）、系统 `isDarkMode` 取色（须走 `@StorageProp('darkMode')`+GlassTokens）、第三方图表库/SwitchChart 整抄（自绘）、`HdsTabs`（编译器 10905201）、`dialog_hub`/`ui-viewer`（不入依赖）。

### 🔺 鸿蒙 7 / API 26 升级（2026-10-18 启动）
> 方案与行为变更影响分析见 [docs/HARMONYOS7_MIGRATION.md](HARMONYOS7_MIGRATION.md)（已逐条对照源码）。
- [x] 官方升级方案落盘 + API 26 行为变更影响审计（结论：代码几乎无必改项，风险在 Dialog/Toast 默认沉浸材质观感与新编译器告警）
- [ ] 工具链升级：DevEco Studio 26.0.0.851 / Command Line Tools 26.0.0.851（SDK 26.0.0 内嵌）—— **当前阻塞：需登录华为账号下载，本机只有 6.1.1 + SDK 24**
- [ ] 配置迁移：targetSdkVersion→`26.0.0`、modelVersion→`26.0.0`、targetAPIVersion→`26.0.0`（compatibleSdkVersion 建议保持 `6.1.1(24)`）
- [ ] 编译修复 + API Change Assistant（24→26）+ codelinter 清零
- [ ] HarmonyOS 7.0 新设备全量回归 + 6.x 老设备冒烟；结果回写 TEST_CHECKLIST

### 📅 规划中 (v0.6+)
| 功能 | 优先级 | 预计工时 | 依赖 | 会话 |
|---|---|---|---|---|
| 打印功能 (@kit.PrintKit) | 🔴 高 | 3-5天 | PDF查看稳定 | NEW会话 |
| 扫描/OCR (@kit.ScanKit + CoreVisionKit) | 🔴 高 | 5-7天 | PDF转图稳定 | NEW会话 |
| 去手写/笔迹识别 | 🟡 中 | 7-10天 | 扫描完成 | NEW会话 |
| 云同步/备份 | 🟢 低 | 待定 | 本地稳定 | 后续 |

### 里程碑
- M1 (08-15)：真机验收通过 → v0.5 发布
- M2 (08-31)：打印/扫描集成 → v0.6 发布
- M3 (09-15)：去手写/云同步 → v0.7 发布