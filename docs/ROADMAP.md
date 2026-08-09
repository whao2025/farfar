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
- [ ] 文字型 PDF 改字精度打磨（表格型文字 PDF 文本块/字号/字体恢复优先）
- [ ] 真机全流程验收 (TEST_CHECKLIST.md 7项)
- [ ] ProfileTab 我的栏目完善 (About/Feedback/Storage/Backup/Help/License)
- [ ] ProfileTab 字段理顺 + 编译0警告

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