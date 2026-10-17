# farfar · freepdf

纯本地 HarmonyOS NEXT 应用（ArkTS / ArkUI，包名 `com.freepdf.app`），**无联网、无登录、无第三方 SDK**。

## 功能

- **PDF 查看 / 编辑**：文本型 PDF 页面点选改字（单块 + 多选批量 / 批量撤回）、加字、加图、高亮、文字标注、插删页、合并、撤销
- **PDF 转换**：PDF ↔ 图片、PDF 转 txt
- **记账**：PDF/图片 OCR 导入 → 规则分类 + 端侧 ALBERT 分类（rawfile 内置 .ms 模型）→ 确认落库 → 预算/趋势统计
- **UI**：玻璃拟态、深色模式、折叠式最近文件、星标置顶

## 构建

要求 **DevEco Studio 26.0.0.851**（HarmonyOS SDK 26.0.0，API 26）。

```powershell
# 默认 release；-Clean 可选
.\scripts\build.ps1 -Mode release -Clean
```

- targetSdkVersion: `26.0.0`（鸿蒙 7）
- compatibleSdkVersion: `6.1.1(24)`（兼容鸿蒙 6.x）

## 文档

| 文件 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 架构 / 约定 / 已知坑（开发前必读） |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 路线图与待办 |
| [docs/TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md) | 真机验收清单 |
| [docs/HARMONYOS7_MIGRATION.md](docs/HARMONYOS7_MIGRATION.md) | 鸿蒙 7 / API 26 适配方案 |
| [PUBLISH_GUIDE.md](PUBLISH_GUIDE.md) | 华为应用市场上架指南 |

## 校验脚本

```bash
node scripts/verify_parser.js    # 记账规则数据与分类行为
node scripts/verify_rewrite.js   # 改字纯逻辑
python scripts/verify_docs.py    # 文档一致性
```
