# PDF ↔ Word 高质量转换：GitHub 方案调研与最佳方案

> 目的：以开源项目为参照，结合 HarmonyOS 纯本地约束，给出可落地的"最好方案"。调研数据 2026-10-18 实取 GitHub API；不复制任何代码，只借鉴算法思想并用 ArkTS 重写。

## 1. 调研对象（stars / 语言 / 许可证 / 可学习点）

| 项目 | ★ | 语言 | 许可证 | 可学习点 | 对鸿蒙可用性 |
|---|---|---|---|---|---|
| KnifeLemon/Filee | 3.5k | C# | MIT | PDF→DOCX 内置管线：基线成行、栏缝/多栏阅读顺序、段落/列表/标题、页眉页脚剔除、扫描页转整页图片、WordprocessingML 直写 | 算法可借鉴；C# 运行时不可用 |
| dothinking/pdf2docx | 3.5k | Python | MIT | **最接近的蓝本**：RawPage 抽字符/线/矩形/图片 → Layout(Sections/Columns) → Blocks(文本/图片/表格) → docx；含表格检测与图片抽取、字体映射 | 算法可借鉴；Python 不可用 |
| jsvine/pdfplumber | 10.8k | Python | MIT | 字符/线/矩形/曲线原语 + 表格抽取策略（线和文本两种） | 原语思路可借鉴 |
| camelot / tabula-java | 3.8k/2k | Python/Java | MIT | 表格识别算法（lattice：线网格；stream：空白对齐） | 算法可借鉴 |
| VikParuchuri/marker | 40.5k | Python | Apache-2.0 | ML 管线：版面检测 + OCR + 表格识别 → Markdown/JSON，质量上限参考 | 模型可评估转 MSL |
| VikParuchuri/surya | 21.5k | Python | Apache-2.0 | OCR / 版面分析 / 阅读顺序 / 表格识别模型（90+ 语言） | 模型可评估转 MSL |
| PaddleOCR | 91.3k | Python/C++ | Apache-2.0 | PP-OCR + **PP-Structure**（版面/表格/公式） | det/rec/layout/table 模型可转 MSL |
| docling-project/docling | 69k | Python | MIT | 文档转换管线：版面模型 + 表格结构 + 阅读顺序 | 模型/思路可借鉴 |
| grobid | 5.2k | Java | Apache-2.0 | 学术文档章节/阅读顺序启发式 | 仅算法 |
| opendatalab/MinerU | 82k | Python | 非宽松（NOASSERTION） | 高质量版面/公式/表格 | **许可证风险，避开** |
| py-pdf/PyMuPDF | 10.9k | Python | AGPL-3.0 | 抽取/redaction 强 | **AGPL，避开** |

## 2. 核心结论：最合适的方案是"两阶段架构"

### 阶段 1（现在就能做，价值最大）：纯 ArkTS 确定性版面引擎

数据源全部来自系统 `@kit.PDFKit`（已内置、不增包体、无网络、无第三方 SDK）：
- `getGraphicsObjects()`：`OBJECT_TEXT`（文本+基线+字号+字体+颜色）、`OBJECT_IMAGE`（含 pixelMap）、`OBJECT_PATH`（矢量图形，仅暴露 bbox/clipRect）。

流水线（借鉴 Filee + pdf2docx 的思想，代码全部自研）：
1. **成行**：按基线聚类（容差随字号），按 x 排序，按字宽估算补空格/制表位；
2. **多栏**：竖直"栏缝"检测 + 横跨行分段 + 段内先左后右（Filee ReadingOrder / pdf2docx Sections 思路）；
3. **段落/标题/列表**：列表正则、缩进/行距/短行断段、字号中位数×1.25 判标题、粗斜体由字体名推断；
4. **表格检测（当前最大缺口）**：从 `OBJECT_PATH` 的细长 bbox 聚类出横线/竖线网格（横向线：高<2pt；纵向线：宽<2pt），网格闭包即单元格 → 输出 `w:tbl`（pdf2docx/camelot lattice 思路）；**验证点**：真机打印 PATH 对象 bbox 结构后确认字段语义；
5. **图片**：`ImageObject.pixelMap` 编码 PNG → docx `word/media` + `w:drawing`（替代目前"整页图片"的粗粒度方案）；
6. **页眉页脚**：跨页重复文本 + 页码模式剔除；
7. **DOCX 输出**：`w:sectPr` 纸张/页边距、`w:pPr` 行距/居右/居中、`w:rPr` 字号/粗细/颜色、`w:tbl` 表格、`w:drawing` 图片、页间分页符。

**Word→PDF**（同一引擎反向）：解析 docx 的 `w:p/w:r/w:tbl/w:drawing` + `w:sz/w:b/w:i/w:color/w:jc`，用 PDFKit 渲染文本（字号/加粗/颜色/对齐/自动换行/分页）；表格边框用 1×1 线图对象拉伸绘制（PDFKit 无矢量线 API）；图片用 `addImageObject`。

### 阶段 2（可选，补扫面和复杂版面）：模型增强
- 候选模型（许可证干净）：**Surya**（版面/阅读顺序/表格，Apache-2.0）或 **PP-Structure**（版面/表格，Apache-2.0）；OCR 用 **PP-OCR**（Apache-2.0，det+cls+rec）。
- 路径：ONNX → `converter_lite` → MSL `.ms` → NAPI/ArkTS 推理（复用现有 `BillClassifier` 的 MSL 接入方式）。
- 用途：扫描页 OCR（替代 CoreVisionKit 提升中文/低质）、复杂表格结构、公式/图表区域。
- 成本/风险：包体 +10~20MB、真机性能、ONNX→MSL 算子兼容（关键：Det 的 GridSample、Rec 的 transformer 算子）、模型下载源。

## 3. 许可证与鸿蒙合规结论

| 维度 | 结论 |
|---|---|
| 算法借鉴（MIT/Apache-2.0） | 安全：pdf2docx(MIT)、Filee(MIT)、pdfplumber(MIT)、camelot/tabula(MIT)、marker/surya/PaddleOCR(Apache-2.0)；**只学思路、ArkTS 重写，不引入原代码** |
| 需避开 | MinerU（NOASSERTION）、PyMuPDF/MuPDF（AGPL）、Java/Python/Go 运行时方案（鸿蒙不可运行） |
| 单机 APP | 所有转换本地完成，无联网；不新增第三方 SDK，隐私声明无需新增数据项 |
| 包体 | 阶段 1 纯 ArkTS 零新增；阶段 2 模型 +10~20MB |

## 4. 落地路线与验收（代码级，不依赖截图）

| 步骤 | 内容 | 验收（代码/产物层面） |
|---|---|---|
| S1 | PATH 对象 bbox 探测 + 表格网格聚类 + `w:tbl` 输出 | 用文字型表格 PDF 输出 docx，解压检查 `word/document.xml` 含 `<w:tbl>`、行列数与 PDF 一致 |
| S2 | 图片提取（ImageObject.pixelMap → PNG）替代整页图片 | docx 内 `word/media/*.png` 数量=PDF 内图片数，XML 有对应 `w:drawing` |
| S3 | 多栏路由增强 + 跨页页眉页脚重复去重 | 双栏 PDF 输出顺序正确（XML 中段落顺序 = 期望阅读顺序） |
| S4 | Word→PDF 表格/图片渲染 | 用 S1 产物反向转换，PDF 页面文字/表格内容完整 |
| S5（可选） | Surya/PP-Structure → MSL | 扫描样张 OCR CER 基线对比 |

## 5. 为什么这是"最好方案"
- **纯本地**：阶段 1 完全用系统 PDFKit + ArkTS，无网络、无第三方 SDK、不增包体，符合单机应用要求；
- **质量来源正确**：PDF→Word 的质量瓶颈是版面重建（Filee/pdf2docx 已验证），不是 OCR；表格/多栏/样式才是差距所在；
- **可验证**：每一步都能用 docx XML 结构与 PDF 对象数做断言，不依赖人眼看截图；
- **可渐进**：阶段 2 模型只在扫描件/复杂表格上叠加，失败可回退，不影响已有能力；
- **许可证干净**：只借鉴 MIT/Apache 算法，避开 AGPL/GPL 与不可运行语言。
