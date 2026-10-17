# 变更日志

所有显著变更按时间倒序记录。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与语义化版本。

## [0.6.0-edit-fix] - 2026-10-18

### 修复（PDF 编辑全链路，待真机复验）
- **点击编辑全部失效的根因**：`onOverlayTouch` 在 `TouchType.Up` 只读 `event.touches`（Up 时可能为空）。改为统一取 `changedTouches`（回退 `touches`），文本/图片/高亮/标注/改字的点选恢复。
- **高亮改为拖拽矩形**：Down/Move/Up 记录起止点、实时预览，松手按真实矩形落 op；顶部颜色/宽度控制区不再误触发放置（原为点击固定 200×30）。
- **扫描/图片型 PDF 支持"改字"**：`listTextObjects` 无文本层时不再直接报错，自动转 OCR；点识别块后以 **FreeText 白底注释覆盖原文字 + 写新文字**（新增 `EditFreeTextOp`）；OCR 补 try/catch/失败提示。
- **标注在页面上可见**：`addTextAnnot` 由 TEXT 便签注释（PdfView 不渲染）改为 **FreeText 注释**（浅黄底 + 文字）。
- **改字保留原文字颜色**：回写时读取 `GraphicsObject.fillColor` 写入 `TextStyle.textColor`，修复改字后文字变黑。
- **文本块包围盒按官方语义修正**：`PdfRect.left/right` 为 x 坐标、`top/bottom` 为 y 坐标（之前误当"距页边距离"，导致块框/命中偏移）。

### 依赖
- 鸿蒙 7 / API 26（targetSdkVersion `26.0.0`，compatibleSdkVersion `6.1.1(24)`），DevEco Studio 26.0.0.851。

## [0.5.1] - 2026-08-11

### 新增
- **多选改字**：PDFEditPage 改字工具（tool=4）现支持批量选择文本块后统一改字。
  - `RewriteSelectDialog`：全选/全不选 + 多选块列表（文字预览 / 字号 / 原字体），复选框用 `sys.symbol.checkmark` / `sys.symbol.xmark`。
  - `RewriteEditDialog`：统一输入新文字与字号，只读展示首个选中块的原字体，错误提示前缀「改字错误：」。
  - `RewriteUndoDialog`：检测到批量改字时撤回弹出，按勾选倒序删除选中 op，支持全选/全不选。
  - 同批改字 op 使用统一 `batchId`（`EditRewriteTextOp.batchId?`）供批量撤回分组。
  - 页面切换自动退出改字模式并重新加载新页块；保留原单块点选改字入口不动。

### 变更
- `PDFEditUtils.ets`：`TextBlockInfo` 增加 `id`（`${pageIndex}_${objIdx}`，同页唯一）与 `fontName?`（只读展示）；改字回写复用原 `TextObject.fontInfo`，不改字体。
- 改字相关 toast 统一「改字错误：」前缀 + 300ms 防抖。
- `scripts/verify_rewrite.js` 新增：id/fontName 生成、rewriteText/addText 入栈映射、字体复用、全选/全不选/部分选择、批量撤回、错误前缀与防抖、切页安全、性能（100 页×300 块）共 26 项断言。

### 文档
- `DEVELOPMENT.md` 新增「改字功能使用指南」。

## [0.5.0] - 2026-08-09

### 新增
- 文字型 PDF 改字改为页面点选定位：进入改字（tool=4）拉取当前页文本块矩形，虚线框标注，点击块内联编辑（原文预填 + 字号折叠可选）。
- `TextBlockInfo` 扩展 x/y/width/height/fontName；`runListTextObjects` 用 `charRects` 求块包围盒。
- 字体/字号保留：worker 复用 fontInfo 原位替换；主线程 FontMatcher 判定回退，面板显示字体提示。
- 预览浮层 derived from ops：确认后块框显示新文字，undo 自动清预览。

### 修复
- 构建警告清零：全量 153 → 0（try/catch + canIUse 全量收敛）。

## [0.4.0] - 2026-08-07

### 新增
- PDF 编辑核心：fontInfo 修复加字不可见、screenToPdf 坐标换算公式、Overlay 点击放置文本/高亮/标注/图片。
- 记账功能：解析/分类/确认/统计（BudgetCard + TrendCard）。
- OCR 互斥（OcrLock）+ 图库选图记账 + 本地 ML 分类器（ALBERT 微调端侧模型）。

## [0.3.0] - 早期

### 新增
- PDF 查看 / 编辑 / 转换基础框架；底部四 tab（编辑/转化/记账/我的）。
