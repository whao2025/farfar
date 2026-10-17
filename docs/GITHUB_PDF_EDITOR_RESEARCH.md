# GitHub PDF 编辑工具调研 · 鸿蒙适配评估（2026-10-18）

> 目的：为 freepdf 寻找可借鉴/可集成的开源 PDF 编辑方案，并按 **HarmonyOS NEXT 应用要求**评估可行性。
> 方法：GitHub API 实取 stars/语言/许可证 + README 核对 + 官方 PDFKit d.ts 对照（未使用任何第三方代码）。

## 0. 约束基线

- 应用形态：纯本地 HarmonyOS NEXT 单机 App（ArkTS/ArkUI，target API 26，compatible 6.1.1(24)），**无联网/登录/服务端**。
- 允许的技术：ArkTS/ArkUI；C/C++/Rust 可通过 **NDK(CMake)+NAPI** 打包成 .so；ArkWeb 组件（Web 技术）技术上可用。
- 上架要求（AGC）：单机 APP 不得含联网/统计 SDK；第三方组件需在隐私政策/声明中如实披露；**许可证必须合规**；包体与性能受审核关注。
- 编辑需求：①已有文字内容修改（改字）②加字/图/高亮/标注 ③页面操作（插删/合并/旋转）。

## 1. 候选清单（GitHub 实测，2026-10-18）

| 项目 | Stars | 技术/语言 | License | 编辑能力 | 鸿蒙可行性 | 结论 |
|---|---|---|---|---|---|---|
| [ElasticPDF/elasticpdf](https://github.com/ElasticPDF/elasticpdf) | 14 | 仓库仅 README/演示视频（**无源码**） | NOASSERTION（官网为商业产品） | 宣称文本/图片编辑 | 无源码，只能商业授权 + Web 嵌入 | ❌ 不可用 |
| [OpenAEC-Foundation/open-pdf-studio](https://github.com/OpenAEC-Foundation/open-pdf-studio) | 922 | Rust 引擎（Tauri 2）+ Web 前端 | **LGPL-3.0** | 批注/标记/测量/CAD；非"改字" | Tauri 不支持 OHOS；Rust 引擎理论上可交叉编译，但需重写 UI 与桥接，工作量大；LGPL 需允许重链接 | ⚠️ 仅作交互/架构参考 |
| [mozilla/pdf.js](https://github.com/mozilla/pdf.js) | 54k | JavaScript | Apache-2.0 | 阅读 + **标注编辑器**（高亮/自由文本/墨迹/签名）；**不能改 PDF 已有文字** | 依赖 DOM/Canvas，只能跑 ArkWeb；包体大、性能与单机审核体验风险 | ⚠️ 交互模式可参考 |
| [Hopding/pdf-lib](https://github.com/Hopding/pdf-lib) | 8.6k | TypeScript | **MIT** | 创建/叠加内容、表单、页面；**不能改原文字**，但适合"白底覆盖 + 新文字" | 纯 JS、无 DOM；ArkTS 中运行需 JS 互操作与打包验证（有不确定性） | ⚠️ 覆盖式改字的候选后端 |
| [ArtifexSoftware/mupdf](https://github.com/ArtifexSoftware/mupdf) | 3k | C | **AGPL-3.0** | 渲染、文本提取、注释、redaction/对象级编辑能力最强 | 可用 OHOS NDK 交叉编译 .so（需 sysroot/CMake 适配）；但 AGPL 要求**整个应用开源**或购买商业授权 | ⚠️ 能力最强、许可证最重 |
| [pymupdf/PyMuPDF](https://github.com/pymupdf/PyMuPDF) | 10.9k | Python 绑定 | AGPL-3.0 | 同 MuPDF | 鸿蒙无 Python 运行时 | ❌ |
| [pdfium](https://pdfium.googlesource.com/pdfium)（Chromium） | — | C++ | BSD-3 | 渲染/表单/文本提取；**不改字**；社区有 OHOS FFI 移植（[ClosedHarmony/pdfium_dart](https://github.com/ClosedHarmony/pdfium_dart)，0★） | 可 NDK 移植，但收益只是渲染（官方 PDFKit 已覆盖），成本高 | ❌ 不建议 |
| [pdfcpu/pdfcpu](https://github.com/pdfcpu/pdfcpu) | 8.8k | Go | Apache-2.0 | 页面/水印/表单/优化；不改字 | Go 无官方 OHOS 目标，交叉编译不可行 | ❌ |
| [qpdf/qpdf](https://github.com/qpdf/qpdf) | 5.5k | C++ | Apache-2.0 | 内容保持型转换（加密/合并/拆分） | 可 NDK 编译；页面操作 PDFKit 已覆盖，收益低 | ⚠️ 备选 |
| [xournalpp](https://github.com/xournalpp/xournalpp) | 15.5k | C++/GTK | GPL-2.0 | 手写批注（非 PDF 内容编辑） | GTK 依赖 + GPL，鸿蒙不可行 | ❌ |
| [pdfarranger](https://github.com/pdfarranger/pdfarranger) | 6k | Python/GTK | GPL-3.0 | 页面重排/合并/裁切 | 无 Python 运行时 | ❌ |
| [Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF) | 94k | Java/Docker | — | 服务端 Web 应用 | 单机 App 不可用（需服务器） | ❌ |
| [apache/pdfbox](https://github.com/apache/pdfbox) | 3.1k | Java | Apache-2.0 | PDF 解析/生成 | 鸿蒙无 JVM | ❌ |

### HarmonyOS 生态已有的 PDF 项目（均为阅读/标注，无"改字"）
- OpenHarmony-SIG/officeservice_open_pdf（官方 PDF 服务样例，gitcode）
- JustPDF、PageArk（ArkTS + PDFKit 阅读器）、ohrengine（MIT，PDF/EPUB 解析）、zotero-harmony（AGPL，PDF 阅读+标注）

## 2. 核心结论

1. **没有"开源 + 可商用 + 支持改已有文字 + 能直接跑鸿蒙"的现成工具**。
   - 真正能改字的开源库只有 MuPDF（AGPL）；pdf-lib/pdf.js 只能叠加/标注；pdfium 不能改字；ElasticPDF 仓库无源码。
2. **官方 PDFKit 仍是鸿蒙上最合规、最省包体的编辑内核**（系统内置渲染/文本对象/批注/页面 API）。
3. 若要做"改字"，只有两条路：
   - **A. 继续 PDFKit + 覆盖式方案**（不删原文字对象，用 FreeText/白底+新文字盖住），改动小、合规、包体不变；PDFKit 的 `TextStyle.fontInfo` 只有 `fontName`（无 registerFont API），删后重插文字在真机上不可见，已验证。
   - **B. 引入 MuPDF（AGPL）**：NDK 交叉编译 + NAPI 封装 + 与 PdfView 协同，2–4 周；**必须开源整个应用**或购买商业授权——与"无第三方 SDK/单机"定位需要和用户确认。
4. 不建议引入 pdf.js/pdfium/Stirling/qpdf/xournalpp 等：要么不可行（Java/Python/Go/服务端/GTK），要么与需求不匹配（只渲染/只标注）。

## 3. 与鸿蒙应用要求的符合性逐项

| 要求 | 评估 |
|---|---|
| ArkTS/ArkUI 原生 | 官方 PDFKit 完全符合；纯 JS 库（pdf-lib）需额外验证 ArkTS↔JS 互操作 |
| 本地 native .so | HarmonyOS 支持 C/C++/Rust（NDK/CMake/NAPI），MuPDF/pdfium/qpdf 可移植 |
| 单机 APP（无联网/统计） | 开源本地库均无联网，符合；需在隐私声明中披露第三方组件 |
| 许可证 | MIT/Apache/BSD 风险低；**LGPL** 需可重链接/源码获取；**GPL/AGPL** 需整个应用同协议开源 |
| 包体 | pdfium/mupdf .so arm64 约 10–25MB；PDFKit 系统内置、不增包体 |
| 上架审核 | Web 方案（ArkWeb）不违规但体验/审核解释成本高；建议原生 |

## 4. 建议

- **短期（已做/在做）**：继续用 PDFKit；本轮已修好坐标换算、高亮拖拽、标注可见、保存链路（真机验证通过）。"改字"按用户要求**暂停**。
- **若要恢复改字**：优先 A 方案（覆盖式，合规且快）；B 方案（MuPDF）仅在用户愿意开源/购买授权时考虑。
- **可借鉴**：pdf.js Annotation Editor 的交互（拖拽高亮/自由文本）、pdf-lib 的"叠加内容"模型——仅借鉴思路，不引入代码。

## 5. 数据来源

- GitHub REST API 实取 stars/license/language（2026-10-18）
- 各仓库 README（raw.githubusercontent.com）
- HarmonyOS SDK 26 `@hms.officeservice.pdfservice.d.ts`（PDFKit API 核对）
