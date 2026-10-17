# freepdf 真机验收清单

> 每次真机前：`hvigorw clean assembleDebug` → 拉最新代码 → 按项勾选

- [ ] **1. 加文本**  
  点击页面任意位置 → 弹输入框 → 确定 → 文字落在点击位置（pt 精度，距左/距底）

- [ ] **2. 加高亮**  
  点击页面 → 拖拽矩形 → 高亮跟随手指、颜色可选、保存后位置不漂

- [ ] **3. 改字**  
  点「改字」工具 → 页面上出现文字块虚线框 → 点选某块 → 面板预填原文 → 确定 → 块框显示新模式文字预览 → 保存后原位替换、字体沿用原字体（有提示）

- [ ] **4. 插页**  
  工具栏插页 → 新空白页出现 → 能在新页继续加字/高亮、索引不乱

- [ ] **5. 合并**  
  选另一个 PDF → 追加到末尾 → 翻页正常、批注丢失有 Toast 提示

- [ ] **6. 组合流程**  
  加字 → 加高亮 → 撤销 → 重做 → 保存 → 重新打开验证无丢失

- [ ] **7. 保存导出**  
  保存 → 导出到文件管理器 → 用系统阅读器打开无乱码、页数一致

> ProfileTab 我的栏目：About/Feedback/Storage/Backup/Help/License（Phase 1-3 另列清单）

---

## 回归锚点（每轮新增功能追加）

| 日期 | 验证人 | 新增项 | 备注 |
|---|---|---|---|
| 2026-08-07 | | fontInfo/screenToPdf/Overlay/死代码清理 | 四轮合并 |
| 2026-08-09 | | 改字页面点选 + 块矩形(charRects)+字号折叠 | 真机重点：click 命中精度、charRects 坐标系（P0） |
| 2026-08-10 | | 图片记账 img-ocr 链路 + 规则 JSON 单一源 + ML 强制覆盖 | 见下方 G1-G10，P0 重点 G5（ML useMl 日志） |

---

## 图片记账 → ConfirmPage 链路（2026-08-10 新增，P0）

> 前置：debug 包装机，`--short|--checkpoint` 无；本清单关注**链路完整**（选图→OCR→确认→落库）与 **ML 强制覆盖**（img-ocr 必须先等模型就绪再解析）。

- [ ] **G1. 图库球入口**：记账 tab 右侧 SmartReachBar → 滑出 → 点「图库」球 → 系统 PhotoViewPicker 打开（含图库内拍摄按钮）
- [ ] **G2. 多选识别**：选 2~3 张真实小票/账单图 → 确认 → 短暂「加载智能分类…」→「识别到 N 条记录」→ 自动进 ConfirmPage
- [ ] **G3. 行/块保序**：多图结果按图序出现 `--- 第 N 页 ---` 分页标记，且页面显示「识别到 N 条」，ConfirmPage 无障碍把标记行当商户（merchant 栏不得出现 `--- 第…页---`）
- [ ] **G4. 元信息排除**：含「咖啡因/热量/共2件/已下架」的营销/营养行不被识别为商户或分类条目
- [ ] **G5. ML 覆盖（核心）**：选一张规则关键词未覆盖的账单图（如字号标题「门店招牌菜」），ConfirmPage 分类由 ML 判定；用 logcat 查 `ML classify input=… useMl=true` 与 `warmup ok` 日志；首次进入时 statusMsg 出现「加载智能分类…」（等待模型而非空转）
- [ ] **G6. 开关语义**：mlOptions 关闭时 PDF/文本记账 ML 不生效（无 ML 日志），图片记账仍强制 ML（有日志）——即「图片强制、其余开关」分叉正确
- [ ] **G7. 单条调整**：ConfirmPage 点「调整」→ 支出/收入切换 + CategoryPicker 改分类 → 只影响该条（keyGenerator 含 category，刷新不串条）
- [ ] **G8. 落库刷新**：勾选保存 → 返回记账 tab → BudgetCard/TrendCard 统计即时更新（recordRefreshTick bump）
- [ ] **G9. 空识别**：拍/选纯场景图（无人、无文字）→ Toast「未识别到文字」且不进入 ConfirmPage
- [ ] **G10. 取消安全**：picker 取消 → 无跳转无崩溃；识别中途返回 → 无 textRecognition 二次初始化崩溃（OcrLock 互斥）

> 通过标准：G1-G10 全过；G5 日志含 `useMl=true` 且至少 1 条 ML 改判「其他→真实类」；回归锚点段含 2026-08-10 记录。

### 自动化真机结果（2026-08-10，Mate 70 CLS-AL30 / hdc + uitest）
| 项 | 结果 | 证据 |
|---|---|---|
| G1 图库球入口 | ✅ | SmartReachBar 拖出→点图库球→PhotoViewPicker 弹出，`hotos:PickerUIExtensionAbility` 日志 + 截图确认 |
| G2 多选识别 | ✅(1 图) | `isMultiPick is true`（上限9）；选中 position33(微信账单图)提交→`selectResult`→OCR 完成 |
| G3 行/块保序 | ✅ | OCR 输出逐块 `--- 第 N 页 ---` 标记，金额/商户行按原始行序（hilog 见证） |
| G4 元信息排除 | ⚠️ 待人工 | 自动化样本未含「咖啡因/共X件」行；verify_parser MR 用例已覆盖（5/5 绿） |
| G5 ML 覆盖 | ✅(机制) | Fresh 启动 `BillClassifier initialized`+`warmup ok 餐饮 0.350/0.213`；img-ocr 解析触发 `ML classify input="…储蓄卡(6986)支付"-> 理财 conf=0.229 catOk=false useMl=false`（类别守卫正确拦截收入污染）。**未见 useMl=true 样本**（样本集信度未过门槛） |
| G6 开关分叉 | ⚠️ 待人工 | PDF/文本记账解析存在于 img-ocr 之外的路径，未单独开关对照 |
| G7 单条调整 | ✅(渲染) | ConfirmPage `调整/收起` 切换 + `支出|收入` + CategoryPicker `餐饮/交通/购物` chips 渲染正常（多次 dump 见证） |
| G8 落库刷新 | ✅ | 记账 tab 统计随多次保存变化：已用 ¥2.1w→¥2.2w、本周 ¥46→¥114 |
| G9 空识别 toast | ⚠️ 待人工 | 代码路径存在（`未识别到文字`）；未现场触发 |
| G10 取消安全 | ✅ | picker 取消/超时多次返回无崩溃；OcrLock 互斥运行期可见 |

> 备注：`useMl=true`（规则=其他 且 ML conf≥0.30、margin≥0.03、类别匹配）当前账单样本均未满足，属模型对样本信度问题非链路故障；建议后续用「规则关键词未覆盖的餐饮/交通账单」重拍验证。

## 用户反馈回归（2026-08-11，真机手动）
- **现象**：ConfirmPage 展开「调整」后，分类 chip 点击无反应（分类一直「其他」，`[分类]` 标签不变）；此前 G7 仅验证到「渲染正常」未验点击。
- **根因**：`BookkeepingConfirmPage.ets:333` 在 CategoryPicker 组件外部施加 `.hitTestBehavior(HitTestMode.Block)`，而 CategoryPicker 根是横向 `Scroll`（CategoryPicker.ets:58）——Block 施加在 Scroll 根会将该子树整体排除出命中测试，chip 的 `onClick`（:52-54）永不触发。`支出/收入` 是普通 Text（自带 onClick+Block）故仍有效；`suggestions` 仅 :72/:99 两处赋值，排除异步 ML 覆盖。
- **修复**（review 已批，W1 冗余项未做）：
  - :333 删除 `.hitTestBehavior(HitTestMode.Block)`（根修）；
  - :344 整行 onClick 加守卫 `if (this.activeCatIdx !== idx)`（防删 Block 后 chip 点击冒泡误翻复选框）；
  - 其余 Block（Checkbox :264 / 调整 :280 / 支出·收入 :312/:325）原样保留；
  - 词表（前一问题）：餐饮 keywords +「农夫山泉」，merchantMap +「农夫山泉芝麻店」（record_model.json + RecordModel.ets fallback + verify_parser.js：FIXTURE 17/17、MERCHANT 6/6 绿）。
- **复验清单 G11（待真机，img-ocr 图库球链路）**：
  - [ ] 点非「其他」chip → `[分类]` 标签即时变化 + 对应 chip 高亮移动 + 复选框**不**误翻转（反证冒泡护栏）
  - [ ] 切「支出/收入」→ chip 列表按新类型联动切换
  - [ ] 收起后点整行 → 复选框照常 toggle（收起态回归为零）
  - [ ] 横向滑动 chip 条 → 滚动正常、松手不误点
  - [ ] 智能球（ManualEntry）/PDF 球两条入口各冒烟一次（parseText :71 与 ensureMlForImg :48 无连带影响）
  - [ ] 账单含「农夫山泉/农夫山泉芝麻店」→ 归餐饮（非其他）