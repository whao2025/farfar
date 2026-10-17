# 开发指南

## 构建

- CLI 构建统一用 `.\scripts\build.ps1 -Mode release [-Clean]`（内建 `DEVECO_SDK_HOME` env，勿裸跑 `hvigorw`）。详见 `PUBLISH_GUIDE.md`。
- 验收标准：`BUILD SUCCESSFUL`、`WARN 0`、`ERROR 0`。

## 测试与校验脚本

| 脚本 | 用途 | 运行 |
|---|---|---|
| `scripts/verify_parser.js` | 记账规则数据（record_model.json）结构与分类行为 | `node scripts/verify_parser.js` |
| `scripts/verify_rewrite.js` | 多选改字纯逻辑（id/映射/字体复用/选择/撤回/错误前缀/切页/性能） | `node scripts/verify_rewrite.js` |
| `scripts/verify_docs.py` | 开发文档一致性 | `python scripts/verify_docs.py` |

> 约定：改动纯逻辑后先跑对应 verify 脚本再构建；脚本只读无副作用。

## 改字功能使用指南

### 功能入口

PDFEditPage 底部工具条第 5 项「改字」（tool=4）。该功能面向**文字型 PDF**（含文本层与嵌入字体，如 Excel 导出报表）；图片/扫描型走 OCR 兜底。

### 两种改字方式

1. **单块改字（原有）**：进入改字模式后页面显示文本块虚线框，点击文字区域 → 内联编辑面板（原文预填、字号折叠默认沿用原字号、字体提示原字体/回退）→ 确认后块框显示新文字预览。
2. **多选改字（新增）**：进入改字模式后自动弹出 `RewriteSelectDialog`：
   - 顶部「全选」/「全不选」（`sys.symbol.checkmark` / `sys.symbol.xmark` + 文字），计数显示 `已选/总数`。
   - 每行：`sys.symbol.character_textbox` 图标 + 文字预览 + 字号 + 原字体；复选框勾选/取消。
   - 「下一步」→ `RewriteEditDialog`：统一输入新文字与字号（空字号沿用各块原字号），只读展示首个选中块的原字体。
   - 「确定」→ 生成同批 op（统一 `batchId`），块框预览更新为统一新文字。

### 批量撤回

- 顶部「撤回」按钮：若最近一步是批量改字（op 带 `batchId`）→ 弹 `RewriteUndoDialog`。
- 对话框布局与选择对话框一致：列出本批次改字 op（页码 / 新文字 / 原文字），支持多选，确认后**按勾选倒序删除**选中 op，其余保留；被撤回块预览自动清空。
- 普通操作撤回仍为单步弹出。

### 数据流

- `listTextObjectsAsync` → `TextBlockInfo{index, id, text, size, x, y, width, height, fontName?}`；`id = ${pageIndex}_${objIdx}`（同页唯一，ForEach key 用）。
- `applyEditsAsync` `rewriteText` 分支：`xs=块序号`（定位第 N 个 TEXT 对象）、`nums=新字号`、`texts=新文字`；回写时 `style.fontInfo = 原 TextObject.fontInfo`（**不改字体**，缺失才回退 `HarmonyOS Sans`）。
- 保存落库走 `addEditedFile`（imports/ 置顶 recent.json）+ `saveSandboxFile` 导出。

### 边界行为

- 无文本页 / 扫描版：toast「改字错误：此页无文本或为扫描版，无法修改」。
- 未选中任何块点「下一步」：toast「改字错误：请至少选择一个文本块」。
- 新文字为空 / 字号非正整数：`RewriteEditDialog` 内联红色错误「改字错误：…」。
- **切页**：自动退出改字模式、清空选择态并重新加载新页块（`onPageChangedForRewrite`）。
- 所有改字 toast 统一「改字错误：」前缀 + 300ms 防抖（`showRewriteError`/`toastDebounced`）。

### 改字相关状态（PDFEditPage）

| 状态 | 含义 |
|---|---|
| `rewriteBlocks: TextBlockInfo[]` | 当前页文本块 |
| `selectedIds: string[]` | 多选改字选中的块 id |
| `batchId: string` | 当前批次统一 id |
| `showSelectDialog/showEditDialog/showUndoDialog` | 三个弹窗可见性 |
| `undoEntries/undoChecked` | 批量撤回列表与勾选态 |
| `editText/editSizeText/editErrorMsg` | 编辑弹窗输入与错误 |

### 组件

- `components/RewriteSelectDialog.ets`、`RewriteEditDialog.ets`、`RewriteUndoDialog.ets`：Glass 样式（`backgroundBlurStyle(GlassTokens.BLUR_MODAL)` + BG/BORDER + SHADOW），禁 `backdropBlur`/`systemMaterial`/`ImmersiveMaterial`。
- 图标只使用 SDK `sysResource.js` symbol 段已确认项：`checkmark`、`xmark`、`character_textbox`（`close`/`text` 不存在，勿引用）。
