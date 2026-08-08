# 本地 ML 分类功能实现指南

## 📁 文件清单

### Python 脚本（训练与转换）
- `scripts/export_dataset.py` - 导出和准备训练数据
- `scripts/train_albert.py` - 微调 ALBERT-tiny-chinese 模型
- `scripts/convert_to_ms.py` - 将 ONNX 模型转换为 MindSporeLite 格式

### ArkTS 文件
- `entry/src/main/ets/utils/DatasetExportUtil.ets` - 数据库导出工具
- `entry/src/main/ets/utils/ml/BillClassifier.ets` - ML 推理层
- `entry/src/main/ets/components/MLOptionsSwitch.ets` - 设置页开关组件
- `entry/src/main/ets/pages/tabs/ProfileTab.ets` - 已修改（添加智能分类开关）
- `entry/src/main/ets/utils/RuleCategorizer.ets` - 已修改（注入 ML 钩子）

## 🚀 使用步骤

### 步骤 1：安装 PyTorch（5 分钟）
```powershell
py -3 -m pip install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu121
```

### 步骤 2：安装其他依赖（2 分钟）
```powershell
py -3 -m pip install transformers datasets accelerate
```

### 步骤 3：在应用中记账（10 分钟）
1. 用 DevEco Studio 编译安装应用到真机/模拟器
2. 打开应用，记账 **≥10 条**（任意分类，任意金额）
3. 确保每条记录的 `status = CONFIRMED`

### 步骤 4：导出数据（5 分钟）
> ⚠️ 数据库默认 WAL 日志模式：应用运行时部分已确认记录可能仍缓存在 `-wal` 文件里未落盘。直接 pull 主文件会导致静默丢数据。

```powershell
# 先强制停止应用，确保 WAL 已合并
adb shell am force-stop com.freepdf.app
adb pull /data/app/el2/100/database/com.freepdf.app/rdb/freepdf_accounting.db .
```

### 步骤 5：准备训练数据（10 分钟）
```powershell
# 直接从 SQLite 数据库读取（status=CONFIRMED，过滤空 note）
py -3 scripts/export_dataset.py --from-db freepdf_accounting.db --train data/train.jsonl --val data/val.jsonl --labels data/labels.json
```

**验收标准**：
- 输出显示 type×category 交叉分布
- 每分类实例数 ≥20（数据量不足时提示建议值）
- `data/train.jsonl` 和 `data/val.jsonl` 文件已创建

### 步骤 6：训练模型（30-60 分钟）
```powershell
py -3 scripts/train_albert.py --train data/train.jsonl --val data/val.jsonl --labels data/labels.json
```

**验收标准**：
- `models/albert_finetuned/` 目录已创建
- 验证准确率 ≥90%
- 模型文件已生成

### 步骤 7：转换模型（5 分钟）
```powershell
# 安装 MindSpore Lite converter（从官方下载）
# 下载地址：https://www.mindspore.cn/lite/docs/en/master/use/converter/converter.html

# 运行转换命令
py -3 scripts/convert_to_ms.py
```

**验收标准**：
- `models/albert_finetuned.ms` 文件已创建
- 文件大小 ≤8 MB

### 步骤 8：部署模型到应用（10 分钟）
1. 将以下文件复制到 `entry/src/main/resources/rawfile/`：
   - `models/albert_finetuned.ms`
   - `vocab.txt`（从 `models/albert_finetuned/` 拷贝）
   - `labels.json`（**必须从 `models/albert_finetuned/labels.json` 拷贝**——该文件含 `invLabelMap` 驼峰键，设备端读取；勿拷 `data/labels.json`，那是 snake_case 的中间文件，设备端读不到）

2. 重新编译应用：
```powershell
hvigorw assembleHap
```

### 步骤 9：测试功能（10 分钟）
1. 打开应用，进入「我的」页面
2. 开启「智能分类」开关
3. 导入 PDF 或拍照记账
4. 查看分类结果

**验收标准**：
- 开关正常工作
- ML 预测正确率 ≥90%
- 推理速度 ≤50ms
- 失败时自动回退到规则分类

## 🔧 配置说明

### MindSpore Lite 依赖
在 `build-profile.json5` 中添加：
```json5
"dependencies": [
  "@kit.ArkUI": {
    "name": "ArkUI"
  },
  "@kit.MindSporeLiteKit": {
    "name": "MindSporeLite"
  }
]
```

### 隐私政策更新
在 `entry/src/main/resources/rawfile/privacy-policy.html` 中添加：
```html
<h2>3. 智能分类功能</h2>
<p>freepdf 提供「智能分类」功能，使用本地训练的机器学习模型辅助识别账单分类。</p>
<p><strong>数据使用：</strong>模型仅在本地运行，不收集、不上传任何用户数据。</p>
<p><strong>隐私保护：</strong>模型文件完全存储在设备本地，不涉及第三方云服务。</p>
<p><strong>模型信息：</strong>当前使用 ALBERT-tiny-chinese 微调模型，推理速度 ≤50ms。</p>
```

## 📊 验收清单

- [ ] Python 环境：PyTorch 2.5.x 安装成功
- [ ] 数据集：每类 ≥20 条（建议），总计建议 ≥800 条
- [ ] 训练：val 准确率 ≥90%，loss <0.5
- [ ] 转换：.ms 模型 ≤8 MB
- [ ] 部署：所有文件已复制到 rawfile/
- [ ] 编译：应用编译通过，无错误
- [ ] 测试：开关正常工作
- [ ] 预测：ML 预测正确率 ≥90%
- [ ] 性能：推理速度 ≤50ms
- [ ] 回退：失败时自动回规则
- [ ] 隐私：政策已更新

## ⚠️ 常见问题

### Q1: PyTorch 安装失败
**A**: 确保使用 Py3.14 的 nightly 版本：
```powershell
pip install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu121
```

### Q2: 模型转换失败
**A**: 确保下载了匹配 SDK 6.1.1(24) 的 converter_lite.exe

### Q3: 编译错误
**A**: 检查 MindSporeLite 依赖是否正确添加到 build-profile.json5

### Q4: ML 分类不工作
**A**: 确保以下文件已复制到 rawfile/（文件名须完全一致）：
- albert_finetuned.ms
- vocab.txt
- labels.json（从 `models/albert_finetuned/` 拷贝，非 `data/labels.json`）

### Q5: 推理速度慢
**A**: 确保使用 CPU 推理，检查模型大小是否正确

## 📞 支持

如有问题，请查看：
- 记账功能文档：`AGENTS.md`
- DeepSeek 缓存监控：`scripts/ds_cache_monitor.py`
- 隐私政策：`privacy-policy.html`
