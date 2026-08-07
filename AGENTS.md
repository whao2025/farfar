# freepdf 项目开发指南

> 本项目为 **纯本地** HarmonyOS NEXT 单机应用（ArkTS / API 23 稳定基线），包名 `com.freepdf.app`，无联网/支付/登录/第三方 SDK。上架勾选"单机 APP"，无需 ICP 备案。项目根为 `D:\freepdf`，分支 master 尚未有提交（一切文件未跟踪）。图标要求 512×512 PNG Alpha 实心。
> 本文内容已按源码逐一核对修正（深色键 / Splash / RecordDatabase / utils 导出签名 / 组件 props）。

## 技术栈与关键配置
- 语言/框架：ArkTS + ArkUI（声明式 UI），`@Entry`/`@Component`+`@struct` 结构体，`@Builder`/`@BuilderParam` 封装局部 UI。
- 构建：hvigor，`build-profile.json5` 里 `targetSdkVersion`/`compatibleSdkVersion` 均为 `6.1.1(24)`，`products.default.signingConfig` 为单一字段，需手动在 `debug`/`release` 间切换（release 链：freepdf.p12 / freepdf_release.cer / freepdf_releaseRelease.p7b；debug 链：freepdf_debug.p12 别名 debugkey）。`strictMode.caseSensitiveCheck = true`。
- 已装依赖：`@ohos/lottie@2.0.14`。⚠️ **仅装机未使用** —— Splash 实际是 Canvas+Animator 手绘字母动画（见下），不要把 lottie 写成 Splash 实现。
- 系统能力：PDF 用 `@kit.PDFKit`（PdfView、pdfService、pdfViewManager），文件 `@kit.CoreFileKit`（fileIo/picker），图片 `@kit.ImageKit`，相册 `@kit.MediaLibraryKit`（photoAccessHelper），数据库 `@kit.ArkData`（relationalStore / preferences），UI `@kit.ArkUI`（window/display/router），动作 `@kit.AbilityKit`（common），隐私 `@kit.AppGalleryKit`（privacyManager）。

## 目录结构（entry/src/main/ets）
- `pages/`：Home、PDFViewer、PDFEditPage、PDFConvertPage、BookkeepingConfirmPage、ProfilePrivacyPage、Splash。
- `pages/tabs/`：底部导航四 tab —— EditTab(编辑)/ConvertTab(转化)/BookkeepingTab(记账)/ProfileTab(我的)。
- `components/`：7 个 —— GlassButton、GlassToolbar、PdfEditToolItem、RecentFilesPanel、AutoRecordConfirm、BookkeepingSummary、DailyBarChart。（⚠️ **无 GlassPanel**）
- `utils/`：AmountParser、AutoCategorizer、BudgetPreferences、DarkModeStore、ImportLibrary、PDFConvertUtils、PDFEditUtils、PDFImportUtils、PDFOCRUtils、PickerSaveUtils、RecordDatabase。
- `ocr/`：OCR 服务抽象层 —— `OCRTypes.ets`（OCRResult/OCRPage/TextBlock/TextLine/OCRProgress/OCROptions）、`OCRService.ets`（接口 `recognize(pdfPath,options?,onProgress?)` + 工厂 `createOCRService()`）、`CoreVisionOCR.ets`（`@kit.CoreVisionKit` textRecognition 逐页识别，进度回调/失败重试 MAX_RETRY=2/finally release，块坐标转 PDF 左下原点，fontSize/confidence 为占位默认）。⚠️ CoreVisionOCR 的 TextBlock.fontSize 恒 12、confidence 恒 1（SDK 该版本无这些字段，接口已预留）。
- `pdf/`：PDF 文本回写抽象层 —— `PDFRewriter.ets`（接口 `rewrite(src,out,edits)` + `TextEdit{pageIndex,blockIndex,newText,newSize}` + `RewriteResult`）、`PdfServiceRewriter.ets`（@Concurrent worker：getGraphicsObjects 按序定位第 blockIndex 个 TEXT 对象 → deleteGraphicsObject → 复用 fontInfo 或 'HarmonyOS Sans' 重插 → saveDocument，finally releaseDocument；工厂 `createPDFRewriter()`）。
- `layout/`：智能排版引擎（纯函数、无副作用、字体匹配结果缓存）—— `FontMatcher.ets`（`FontMatchResult{fontName,fontPath?,similarity,fallback}` + `matchFont(ocrFontName?)`：精确→Levenshtein 模糊(≥0.6)→视觉特征(serif/mono/bold 关键词)→回退 'HarmonyOS Sans'；`FontCache` Map 上限 64 条、满即清）、`ParagraphReconstructor.ets`（`Paragraph{id,text,x,y,width,height,fontSize,fontName?,confidence,blockIds}` + `reconstruct(blocks)`：按 y/x 排序→同行合并(重叠≥0.3 且纵向邻近)→行内按 x 排序+gap 判空格→段几何/平均置信度）、`LayoutEngine.ets`（`LayoutResult{paragraphs,tables,images,pageWidth,pageHeight}` + `reconstructLayout(page)` 纯函数；`matchFonts(page)` 返回 `FontMapEntry[]`；`detectTables` 按 y 行分组+≥3 行+≥2 列；`detectImages` 面积>均值6倍 判图）。
- `model/`：RecordModel.ets。`theme/`：GlassTokens.ets、Breakpoint.ets。`entryability/`：EntryAbility.ets。

## UI / 视觉规范
- 全部组件采用 **Glass 玻璃拟态**：背景统一 **`backgroundBlurStyle` + 手动 halo/边框**，**勿用 `backdropBlur`、`systemMaterial`、`ImmersiveMaterial`（后者 API 26+ 不可用）**。
- 深色模式用 **`@StorageProp('darkMode')`**（⚠️ 键名是 `darkMode`，不是 `freepdf_dark_mode`）布尔；颜色取 `GlassTokens.TEXT_DARK/TEXT_LIGHT/BG_DARK/BG_LIGHT/BORDER_DARK/BORDER_LIGHT/BLUR_*/SHADOW`。
- 图标优先系统 symbol：`$r('sys.symbol.xxx')`。已确认存在：wallet、person、square_and_pencil、arrow_left_arrow_right、gearshape、character_textbox、picture_fill、highlighter_line、square_and_pencil_fill、plus_circle、trash_fill、pencil_line、doc、rectangle_on_rectangle_fill、xmark、checkmark_square。**不存在**：chart_pie、banknote、person_crop_circle、photo_fill 系列、product_badge 等 —— 引用前核对 SDK `build-tools\ets-loader\sysResource.js` 的 `symbol:` 段（缩进 8 空格）。

## 深色模式 / AppStorage 全键
全屏跨页状态键（EntryAbility 主要在 `onWindowStageCreate` 写入）：

| 键 | 写入方 | 读取方 | 含义 |
|---|---|---|---|
| `darkMode` | EntryAbility（含 DarkModeEnvCallback） | 全体组件 `@StorageProp('darkMode')` | boolean 深色 |
| `userDarkModeOverride` | EntryAbility | DarkModeEnvCallback / 深色同步 | true 时忽略系统跟随 |
| `fileFilterMode` | EntryAbility、tabs/EditTab | Edit/Convert 面板 | 'all'：全部/星标过滤 |
| `recentRefreshTick` | Edit 各保存链 bump | RecentDocsPanel `@Watch` | 驱动最近文档刷新 |
| `windowWidth` | EntryAbility | — | 窗口宽 px |
| `breakpoint` | EntryAbility | 自适应 | 'sm'/'md'/'lg'（Breakpoint） |
| `foldStatus` | EntryAbility（display.on） | — | 折叠屏状态 |

- 手动深色持久化：`DarkModeStore.load(context):DarkModeOverride（'system'|'light'|'dark'）`，prefs `freepdf_settings` 键 `darkModeOverride`。隐私授权 `ensurePrivacyConsent` → `privacyManager.requestAppPrivacyConsent`。

## 底部导航与路由
- 四 tab（编辑/转化/记账/我的）。编辑 tab 三入口（首页/新建/打开）；转化 tab：PDF转图/图转PDF/PDF转txt/PDF转记账（`pdfToCredit` 4 种 mode）。
- 页面注册：`resources/base/profile/main_pages.json`（Home/PDFViewer/PDFEditPage/PDFConvertPage/BookkeepingConfirmPage/ProfilePrivacyPage/Splash）。
- 跳转：`this.getUIContext().getRouter().pushUrl({url, params})` / `back()` / `back(-1)`。Splash 用 `router.replaceUrl('pages/Home')`。
- 页面 params：
  - `PDFViewerParams { filePath?: string }`
  - `EditPageParams { filePath?: string; newDoc?: boolean }`（PDFEditPage）
  - `ConvertPageParams { mode?: string }`（'pdfToImage'|'imageToPdf'|'pdfToText'|'pdfToCredit'）
  - `ConfirmPageParams { source?: string; text?: string; mode?: 'full'|'compact' }`

## 记账功能（Bookkeeping）— 本地规则驱动
流程：BookkeepingTab → BookkeepingConfirmPage.parseText() → `AutoCategorizer.categorizeBatch(text,'pdf-text')` → `AmountParser.parse` → 正则 + 关键词分类 → 用户确认 → 落 `recordDb`（relationalStore RDB）。
- `model/RecordModel.ets`：
  - `enum RecordStatus {PENDING=0,CONFIRMED=1,DELETED=2}`
  - `type RecordType='expense'|'income'`、`type RecordSource='pdf-text'|'pdf-ocr'`、`type BudgetType`
  - 接口 `CategoryInfo{name,keywords,icon}`、`BookkeepingRecord{id:number|null, amount, type, category, note, merchant:string|null, timestamp, dateStr, confidence, source, status, createdAt}`、`ParsedAmount{amount,type:'expense'|'income'|'refund',category,confidence}`、`Suggestion extends ParsedAmount{note, merchant?, date?, timestamp?, source}`、`WeekDaySpending{day,dateStr,amount,isToday}`、`BudgetConfig{daily,weekly,monthly}`
  - 常量 `EXPENSE_CATEGORIES`(8)/`INCOME_CATEGORIES`(3)/`REFUND_KEYWORDS`/`TOTAL_LABELS`
- utils 三件套：
  - `AmountParser`（静态类）：`parseLine(line):ParsedAmount|null`、`parse(text,source='pdf-text'):Suggestion[]`、`parseAmountOnly(text):number|null`、`isRefund(text)`、`getCategoryFromText(text)`；内部 `TOTAL_LABELS` 正则、`normalizeAmount`（识别 `[-￥]?\d+([.,]\d+)?`，金额 <99999、上限基准）、`classify`（关键词→EXPENSE/INCOME）、`calculateConfidence`、`extractMerchant`、`dateToTimestamp`。
  - `AutoCategorizer`（静态类）：`getCategories():CategoryInfo[]`、`categorizeBatch(text,source):Promise<CategorizationResult>`、`validateSuggestion`、`filterValid(suggestions)`、`getSuggestionsForEdit(text)`；内部 `buildSummary`（按类汇总）、`loadMerchantMap`。导出 `autoCategorizer`。
  - `CategorizationResult{suggestions,summary}`。
  - `RecordDatabase`：单例 `recordDb = RecordDatabase.getInstance()`。方法 `init(ctx)`、`insert(record)`、`batchInsert(records)`、`getAll(status?)`、`getByDateRange(start,end)`、`getByCategory`、`getWeeklyStats`、`getMonthlyStats`、`update`、`updateStatus`、`delete`、`clearAll`、`close`。⚠️ **无 `insertData`/`updateData`**。
- `BudgetPreferences`：单例 `budgetPrefs`；`init/getMonthlyBudget/setMonthlyBudget/getBudgetConfig（daily=monthly/30, weekly=monthly/(30/7), monthly）`.getDailyBudget/getWeeklyBudget/isFirstLaunch/setLaunched/close`；prefs `freepdf_budget_prefs` 键 `monthly_budget`/`launched_before`。

## PDF 编辑与转换
- `PDFEditUtils`：`EditTextOp/EditImageOp/EditHighlightOp/EditTextAnnotOp/EditInsertBlankOp/EditDeletePageOp/EditMergeOp/EditRewriteTextOp`（union `EditOp`，各带判别 `op` 字段）+ `EditResult{success,error?,newPageCount?}`；`extractTextAsync(srcPath):Promise<string>`（文本型全文提取）、`listTextObjectsAsync(srcPath,pageIndex):Promise<TextObjectResult>`、`applyEditsAsync(srcPath,outPath,ops:EditOp[],newDoc):Promise<EditResult>`。
- PDF 编辑页操作：添加文本/图片/高亮/文字标注、改字(listTextObjects→选块→改字)、插删页、合并；支持 undo(ops 栈)、撤销/返回。⚠️ OCR 模式：工具条第 9 项「OCR」→ `ocrMode` 状态，`createOCRService().recognize` 识别当前页 → Overlay 叠加 `ocrBlockBox`（块坐标 px→PDF 左下原点，可点击）→ `promptTextInput` 编辑 → `placeAt` 生成 addTextOp；`ocrBusy/ocrProgress/ocrBlocks` 状态驱动。
- `PDFConvertUtils`（`@Concurrent`，可空生命周期，PdfDocument 用 let|null，releaseDocument 放 finally 并判空）：`pdfToImages`/`imagesToPdf`/`pdfToText`/`pdfToTxt`；目标追加模式需 safeIndex 枚举。
- `PDFOCRUtils`（端侧 OCR 兜底，`@kit.CoreVisionKit` 的 `textRecognition`）：`extractTextWithOCRFallback(pdfPath,textOnly)`（文字型优先，纯页标记或空则回退 OCR）、`ocrPdfAsync(pdfPath)`（逐页 `getPagePixelMap→recognizeText→release`）；接口 `OCRLineInfo{text,top,left,width,height}`、`OCRPageResult{ok,lines,value}`；recognizeText 先 SafetyKit 判授权前 `initOcrSafe()/releaseOcrSafe()` 兜底 try/catch。PDFConvertPage `pdfToCredit` 导入用。
- 编辑落库策略：`addEditedFile(context,outPath,baseName)` 复制进 imports/ 置顶 `recent.json` → `reloadPDF()` 重载预览 → `saveSandboxFile` 导出 → `bumpRefresh` 刷新 `recentRefreshTick`。
- `ImportLibrary.ets`（具名导出）：`ImportFileItem {name,path,star,time,starPinTime?}`（`starPinTime` 星标视图独立置顶时间戳，老数据兼容）；`importPDFToLibrary`/`loadRecentFiles`/`saveRecentFiles`/`toggleStar`/`toggleStarPin`（星标置顶开关）/`pinStarBatch`（批量星标置顶）/`moveToTop`（全局 unshift）/`moveToTopBatch`/`deleteImports`/`deleteImport`/`addEditedFile`/`formatRelativeTime`。目录常量 `imports/` + `recent.json`。
- `PdfView({controller,pageFit,showScroll})`，controller 需 `release()`；翻页/页数监听 `registerPageCountChangedListener`/`registerPageChangedListener`。

## ArkTS 严格模式强制约束（关键！）
1. `build()` 组件树内**禁止 `const` 局部变量**（报 "Only UI component syntax..."），逻辑封装到 `@Builder`/方法。
2. `@State` 字段**不能命名为 `opacity`**（与基类冲突）。已用 `splashOpacity`、`haloOpacity`。
3. 对象 spread/rest（`...obj`）禁用。
4. Canvas/CanvasRenderingContext2D/Animator/Curve/FlexAlign/Color 等 **UI 全局符号不能从 `@kit.ArkUI` import**（not exported；仅 display/router 可导）。
5. `Display` 无 `density` 字段用 `densityPixels`；`Configuration` 无 `density`。
6. 子组件阻断父 `onClick` 用 `.hitTestBehavior(HitTestMode.Block)`（`ClickEvent` 无 `stopPropagation`，后者在 MouseEvent/TouchEvent）。

## 组件 & 编辑常量（props / 导出方式）
- **GlassButton**：`@Prop label`、`@Prop dark`、`@Prop blurStyle`(默认 `GlassTokens.BLUR_BUTTON`)、`@Prop heightVp`(48)、`@Prop fontSize`(16)、`@Prop widthVp`(0=100%)、`onClickHandler`。**无 halo 大圆**——点击反馈为 `.clickEffect({level:LIGHT, scale:0.98})` 轻量缩放（悬浮胶囊感），glass 背景/blur/边框/shadow。具名导出。
- **GlassToolbar**：`@Prop dark`、`@Prop heightVp`(64)、`@BuilderParam content`（自定 children）。具名导出。
- **PdfEditToolItem**：`@Prop label`、`@Prop icon`(Resource)、`@Prop actived`、`@Prop dark`、`onClickHandler`。紧凑尺寸：圆形按钮 36、图标 fontSize 20、标签 10、列宽 56、标签带 `textOverflow(Ellipsis)`。active 用 `sys.color.comp_background_tertiary`。具名导出。
- **RecentFilesPanel**：`@Prop searchMode`、`@Prop keyword`、`@StorageProp('fileFilterMode')@Watch filterMode`、`@StorageProp('darkMode') dark`、`@StorageProp('recentRefreshTick')@Watch refreshTick`、`@Link selectModeActive`。具名导出。⚠️ 折叠卡 + 星标独立置顶：`getVisibleShown()`（默认前 4 项，`@State expanded` 展开/收起，>4 项且非选择模式显示「展开全部 (N)/收起」）；`getVisibleFiles()` 在 `starred` 模式按 `starPinTime` 置顶前（新→旧）+ 非置顶按 `time` 倒序；置顶分派：starred→`toggleStarPin`/`pinStarBatch`，all→`moveToTop`/`moveToTopBatch`；选择模式自动展开。
- **AutoRecordConfirm**：`@Prop suggestions: Suggestion[]`、`@Event saveRecords`/`closeDialog`。具名导出。（⚠️ **当前源码零引用，仅供未来逐条确认流程复用**，勿强行接入；如弃用可直接删。）
- **BookkeepingSummary**：具名导出（`export struct`）；自管 `@State dailyBudget/weeklyBudget/monthlyBudget/actualDaily/actualWeekly/actualMonthly` 画三重环形。
- **DailyBarChart**：具名导出（`export struct`）无 props，`@State weekData: WeekDaySpending[]` 内部查 db；` @State isLoading/totalExpense`。

### theme/GlassTokens.ets（导出类，静态只读）
- `BLUR_BUTTON` 等 `BlurStyle` 层级、`BLUR_TOOLBAR`、`BLUR_PANEL`、`BLUR_MODAL` 常量。
- 颜色：`BG_LIGHT`/`BG_DARK`、`BORDER_LIGHT`/`BORDER_DARK`、`TEXT_LIGHT`/`TEXT_DARK`、`HALO_LIGHT`/`HALO_DARK`、`SHADOW`。圆角/间距。

### theme/Breakpoint.ets
- `SM=600`/`MD=840` 断点。方法 `static calcFromPx(px, density): 'sm'|'md'|'lg'`（≥MD→lg、≥SM→md、否则 sm）。供 EntryAbility → `AppStorage('breakpoint')`，tabs 用 `@StorageProp('breakpoint')`。

## 页面职责注意
- `Home.ets`：底部四 tab 总容器（无 params）。底部 HdsTabs 用 `barFloatingStyle` + `barOverlap(true)`（悬浮胶囊 Tab，`@kit.UIDesignKit`）。
- **返回键策略**（全局约定）：`PDFConvertPage`、`BookkeepingConfirmPage` 顶部**无返回按钮**（仅居中标题，返回靠系统手势）；`PDFViewer` 顶部仅「编辑」按钮（`widthVp:64` 固定窄宽靠右）；`PDFEditPage` 顶部按钮 label **恒为「撤回」**（有操作撤回、无操作点击返回，不再显示"返回"字样）；`ProfilePrivacyPage` 保留「← 返回」。
- `EditTab`：搜索 / 选择模式（RecentFilesPanel）、深浅模式。⚠️ 全部/星标切换必须用 `setFilter(mode)`（内部 `AppStorage.setOrCreate('fileFilterMode', mode)`），**勿直接赋值 `this.filterMode`**（@StorageProp 本地赋值不写回 AppStorage → 筛选不生效，曾因此 bug）。
- `ConvertTab`：`@StorageProp('fileFilterMode')` 过滤聚合，全部/星标显式 `AppStorage.setOrCreate('fileFilterMode', ...)`，Dark。
- `BookkeepingTab`：init `recordDb`/`budgetPrefs`，算统计，渲染 `BookkeepingSummary`+`DailyBarChart`，「导入 PDF」push `PDFConvertPage {mode:'pdfToCredit'}`。
- `PDFViewer`：PdfController + 监听页数，`filePath` 来自 params。
- `PDFEditPage`：params `{filePath,newDoc}`；`isNewDoc`；8 工具项；undo stack；保存链。
- `PDFConvertPage`：params `{mode}`；扫描分发；pdfToCredit→push ConfirmPage。
- `BookkeepingConfirmPage`：params `{source,text,mode}`；`AutoCategorizer` → `recordDb` save。

## Splash（非 lottie）
- 纯 ArkTS Canvas 手绘：字母渐变飞入（LETTERS: f/r/e/e/p/d/f），用 `Canvas`+`RenderingContextSettings`+`CanvasRenderingContext2D`+`Animator`，`GRAD_COLORS` 渐变，时间轴 `DURATION/FADE/STAY`，完成后 `router.replaceUrl('pages/Home')`。不用 lottie。

## 待办 / 后续（可选）
- 深色键 bug 已修（记账系改用 darkMode）。
- 默认值/export 规范化（default/具名导出已统一为具名）、死代码已清理（`GradientStrokeHelper`/`HelloPathData` 已删）。导出一致性规范：**普通组件用 `export struct X`；@Entry 页面（pages/*.ets 及 Splash）保持 `struct X` 不显式导出**（export struct 配 @Entry 会触发 ACE preview 警告）。
- 最近文件增强已完成：折叠卡（默认 4 项 + 展开全部）、星标视图独立置顶（`starPinTime`，与全局置顶解耦）、EditTab 星标筛选修复（setFilter 写回 AppStorage）。
- 官方 DeepSeek 缓存优化：见下方「DeepSeek 前缀缓存 · 命中率诊断与戒律」。

## 会话/缓存约定（本会话）
- 本会话专注 freepdf 开发，使用 DeepSeek 前缀缓存提升效率；任何文件改动遵循此处规范。
- 变更前先 `git diff`（提交时），提交信息用 Conventional Commits：`type(scope): description`（feat/fix/refactor/docs/chore）。不 push --force。
- **质量优先**：缓存优化不得以牺牲 code 质量/改 bug 能力为代价 → **不改 thinking 相关配置**，只在纪律层面约束。

### DeepSeek 前缀缓存 · 命中率诊断与戒律（2026-08-07 实测 · 官方 kv_cache/thinking_mode 文档已核对）
- 官方机制：前缀缓存是**自动、按 token0 逐字节精确前缀**的，无缓存开关/键；存储以「完整 prefix unit」为单位、按固定 token 间隔持久化；构建秒级；命中价约为未命中 **1/50**；best-effort disk cache，空闲 **数小时~数天** 后被逐出。
- 命中率 = `cache.read / (input + cache.read)`。全未命中 = `input` 高达 20万+ 而 `cache.read≈0`。
- 「几乎全未命中」四层根因：
  1. **一次性超大注入破坏前缀**：单轮塞入 20–23 万 token（Read/bash/大文件全文回灌），自注入点向后整段前缀失效 → 呈「部分命中/全漏」交替。
  2. **长空档缓存被逐出（TTL）**：09:21→23:44 空 14h，此后全冷启动重写。
  3. **tool 轮 `reasoning_content` 协议强制回填**：DeepSeek 文档——携带 `tools` 的请求后续**必须完整回传 `reasoning_content` 否则 400**；故 tool 轮回填是**必要协议成本，不可消**（质量优先取舍）；仅「两 user 消息间无 tool 调用」的轮次可省该回传。
  4. **编辑 AGENTS.md 本身重置前缀**：自改动点向后全部失效 → 改动必须集中在冷启动一次性完成，勿中途反复微调。
- 隔离：缓存按 account/model/user_id 隔离；子代理（@explore/@review）使用独立缓存池（从零开始）。
- 戒律：
  1. **当天连续工作**，避免 >2h 空档；空档后先用一个小请求（如 `/help`）预热再跑大任务。
  2. **禁止会话内塞入超大 tool/文件输出**——大文本分页/摘要，切勿一次性注入 10万+ token。
  3. **AGENTS.md 改动与缓存段同步在会话冷启动一次性完成**；勿中途新增/重命名/删除 .ets 文件（重置于 git 文件树子块）。
  4. 避免 `/compact` 与频繁 `/new`（重锚前缀）；少用子代理（独立缓存池）。
  5. **只读大文件分批**：单文件 Read 一次一个（≤7k token）；禁 `Get-ChildItem -Recurse`/`git status`/build 输出回灌（freepdf 全未跟踪，其输出随文件增删漂移）。
  6. 插件动态注入先验证再定论：已证 `opencode-adaptive-thinking` 用 `experimental.chat.system.transform` 注入 system **尾部**、会话内稳定 → 不动作；勿臆测禁插件。
  7. 命中率口径：`prompt_cache_hit_tokens/(hit+miss)`；同日+文件静止+未压缩，次轮起应 ≥90%；首轮/跨天必 miss 属预期（数据落在 AGENTS.md 自文档化内容之外，参考 `docs/DEEPSEEK_CACHE_NOTES.md`）。

### DeepSeek 缓存监控（只读工具）
- `scripts/ds_cache_monitor.py`（sqlite3 `mode=ro`，纯只读）：`--recent N` / `--session <id> --tail N` / `--watch <s>` / `--checkpoint` / `--provider deepseek|all|opencode` / `--since HOURS` / `--json`。
- 命中率 = `cache.read/(cache.read+input)`（input 为未命中新 token；cache.write 恒 0；双零行剔除；token 加权）。
- 官方会话判定：session.model 的 JSON `providerID` == `deepseek`（Zen = `opencode`，不计，两者前缀不衔接）。
- 完整口径/根因矩阵/成本对账：`docs/DEEPSEEK_CACHE_NOTES.md`。