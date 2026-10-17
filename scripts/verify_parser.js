#!/usr/bin/env node
/**
 * 记账规则数据验证（只读，无副作用）。
 * 单一事实源：entry/src/main/resources/rawfile/ml/record_model.json
 * 验证：
 *  1) JSON 语法与结构完整性（expense/income categories、merchantMap 全带 keywords、黑名单等）
 *  2) 最长命中分类行为（复刻 utils/AmountParser.ets 的 classify 口径，防止子串误判回归）
 *  3) 收入判定词与规则一致
 *  4) CategoryInfo.icon 在 SDK sysResource.js symbol 段的参考校验（历史上存在 SF 风格 icon 未进 HM symbol 段，
 *     仅警告不阻断；如需启用请先核对 utils 侧对缺失 icon 的兜底）
 * 运行：node scripts/verify_parser.js
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const MODEL = path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'ml', 'record_model.json');

const INCOME_WORDS = ['收入', '到账', '工资', '奖金', '薪水', '薪酬', '利息', '理财', '基金', '分红', '存入'];

// ---------- 1. 结构与黑名单完整性 ----------
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(MODEL, 'utf8'));
} catch (e) {
  console.error('MALFORMED_JSON ' + e.message);
  process.exit(1);
}

const problems = [];
const need = ['expenseCategories', 'incomeCategories', 'merchantMap', 'merchantExclude', 'merchantExcludeMeta', 'refundKeywords', 'totalLabels'];
for (const k of need) {
  if (!Array.isArray(cfg[k]) || cfg[k].length === 0) problems.push('空/缺 ' + k);
}
for (const c of [...(cfg.expenseCategories || []), ...(cfg.incomeCategories || [])]) {
  if (!c.name) problems.push('分类缺 name');
  if (c.name !== '其他' && (!Array.isArray(c.keywords) || c.keywords.length === 0)) problems.push('分类 ' + (c.name || '?') + ' 缺 keywords');
  if (typeof c.icon !== 'string' || c.icon.length === 0) problems.push('分类 ' + (c.name || '?') + ' 缺 icon');
}
for (const m of (cfg.merchantMap || [])) {
  if (!m.name) problems.push('merchantMap 条目缺 name');
  if (Array.isArray(m.keywords) && m.keywords.length === 0) problems.push('merchant ' + (m.name || '?') + ' keywords 空数组');
  if (!Array.isArray(m.keywords) && !m.category) problems.push('merchant ' + (m.name || '?') + ' 既无 keywords 也无 category');
}
// 短商户名是长名的子串属正常父子链（extractMerchant 取最长精确名），仅打印统计不算失败
let subs = 0;
for (const a of (cfg.merchantMap || [])) {
  for (const b of (cfg.merchantMap || [])) {
    if (a.name !== b.name && a.name.includes(b.name)) subs++;
  }
}

if (problems.length > 0) {
  console.error('STRUCT_FAIL');
  for (const p of problems) console.error('  - ' + p);
  process.exit(1);
}
console.log('STRUCT_OK expense=' + cfg.expenseCategories.length + ' income=' + cfg.incomeCategories.length + ' merchantMap=' + cfg.merchantMap.length + ' meta=' + cfg.merchantExcludeMeta.length + ' subImgPts=' + subs);

// ---------- 2. 最长命中分类（复刻 AmountParser.classifyNaive） ----------
function classify(text) {
  const isIncome = INCOME_WORDS.some(k => text.includes(k));
  const cats = isIncome ? cfg.incomeCategories : cfg.expenseCategories;
  let best = '其他';
  let bestLen = 0;
  for (const c of cats) {
    for (const kw of c.keywords) {
      if (text.includes(kw) && kw.length > bestLen) { best = c.name; bestLen = kw.length; }
    }
  }
  return best;
}

const fixtures = [
  ['咖啡厅 小程序的点单记录 标签', '餐饮', '长词「咖啡厅」属餐饮，不得被娱乐劫持'],
  ['美式咖啡 12元', '餐饮', '短词「美式」/「咖啡」'],
  ['泡芙 买2送1', '餐饮', '烘焙并入餐饮后归餐饮'],
  ['杨枝甘露 中杯', '餐饮', '新增「杨枝甘露」'],
  ['羊肉串 烤馕 12串', '餐饮', '烧烤聚合词「羊肉串/烤馕」'],
  ['海底捞火锅 优惠', '餐饮', '「火锅」在餐饮'],
  ['农夫山泉 矿泉水 2瓶', '餐饮', '品牌矿泉水归餐饮（农夫山泉）'],
  ['农夫山泉芝麻店 消费', '餐饮', '商户行含农夫山泉命中餐饮'],
  ['零食大礼包 满99减', '餐饮', '「零食」在餐饮'],
  ['电影院 电影票', '娱乐', '「电影院」最长命中娱乐'],
  ['滴滴打车 行程 支付', '交通', '「滴滴打车」/「行程」'],
  ['话费充值 50元', '通讯', '「话费」'],
  ['宝宝奶粉 尿不湿 湿巾', '购物', '母婴用品应归购物类'],
  ['工资 8000 元 已到账', '工资', '收入判定词→income categories'],
  ['本月账单 已出账', '其他', '不应被误分'],
  ['--- 第 1 页 ---', '其他', 'BookOcr 分页标记不分类'],
  ['--- 第 2 页 ---', '其他', '多块/多图页标记不分类'],
];

let fxFail = 0;
for (const [input, expect, note] of fixtures) {
  const got = classify(input);
  const ok = got === expect;
  if (!ok) fxFail++;
  console.log((ok ? 'FX_OK   ' : 'FX_FAIL ') + got + " <- '" + input + "'  (" + note + ')');
}
if (fxFail > 0) {
  console.error('FIXTURE_FAIL count=' + fxFail);
  process.exit(1);
}
console.log('FIXTURE_OK count=' + fixtures.length);

// ---------- 2b. 商户行上下文捕获（复刻 AmountParser.extractMerchant 口径，防分页/元信息行被当商户） ----------
function hasCategoryKeyword(t) {
  for (const c of cfg.expenseCategories) {
    if (c.name === '其他') continue;
    for (const k of c.keywords) { if (t.includes(k)) return true; }
  }
  return false;
}
function isMerchantBodyRow(t0) {
  const t = String(t0).trim();
  if (t.length < 4) return false;
  if (/^[\-￥¥]?\d/.test(t)) return false;
  for (const w of cfg.merchantExcludeMeta) { if (t.includes(w)) return false; }
  if (/共\s*\d+\s*件|^---\s*第\s*\d+\s*页\s*---/.test(t)) return false;
  return true;
}
function extractMerchantMock(text) {
  let best = null;
  for (const e of cfg.merchantMap) {
    if (text.includes(e.name) && (best === null || e.name.length > best.length)) best = e.name;
  }
  if (best) return best;
  const stripped = String(text).trim().replace(/^(?:微信支付|支付宝|银联|云闪付)\s*/, '');
  if (stripped.length === 0) return null;
  for (const w of cfg.merchantExclude) { if (stripped.includes(w)) return null; }
  for (const w of cfg.merchantExcludeMeta) { if (stripped.includes(w)) return null; }
  if (/共\s*\d+\s*件|^---\s*第\s*\d+\s*页\s*---/.test(stripped)) return null;
  if (hasCategoryKeyword(stripped) || isMerchantBodyRow(stripped)) return stripped.substring(0, 20);
  if (/支付|收款|商户|付款给|消费于|购于/.test(stripped) && !/^[\-￥¥]?\d/.test(stripped)) return stripped.substring(0, 20);
  return null;
}

const merchantCases = [
  ['--- 第 1 页 ---', null, '分页标记不得作为商户上下文'],
  ['--- 第 2 页 ---', null, '页标记非商户'],
  ['咖啡因 28mg', null, '元信息行（营养/计量）非商户'],
  ['美团外卖 午餐', '美团外卖', 'merchantMap 最长命中（美团外卖 > 美团）'],
  ['农夫山泉芝麻店', '农夫山泉芝麻店', 'merchantMap 品牌商户命中'],
  ['微信支付 禾牛肉饭', '禾牛肉饭', '剥离支付通道前缀后按品名行捕获'],
];
let mFail = 0;
for (const [input, expect, note] of merchantCases) {
  const got = extractMerchantMock(input);
  const ok = got === expect;
  if (!ok) mFail++;
  console.log((ok ? 'MR_OK   ' : 'MR_FAIL ') + JSON.stringify(got) + " <- '" + input + "'  (" + note + ')');
}
if (mFail > 0) {
  console.error('MERCHANT_FAIL count=' + mFail);
  process.exit(1);
}
console.log('MERCHANT_OK count=' + merchantCases.length);

// ---------- 3. icon 存在性（探测 SDK, 缺失则警告不阻断） ----------
let symbolOk = true;
let missing = 0;
try {
  const candidates = [
    'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\hms\\ets\\sysResource.js',
    'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\ets\\build-tools\\ets-loader\\sysResource.js',
    'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\ets\\sysResource.js',
  ];
  const sysRes = candidates.find(p => fs.existsSync(p));
  if (sysRes) {
    const src = fs.readFileSync(sysRes, 'utf8');
    const icons = [...(cfg.expenseCategories || []), ...(cfg.incomeCategories || [])].map(c => c.icon);
    for (const icon of icons) {
      if (!src.includes(icon)) {
        symbolOk = false;
        missing++;
        console.warn('ICON_MISSING ' + icon);
      }
    }
    console.log((symbolOk ? 'ICON_OK' : 'ICON_WARN') + ' checked=' + icons.length + (missing ? ' missing=' + missing : ''));
  } else {
    console.warn('ICON_SKIP sysResource.js 未找到');
  }
} catch (e) {
  console.warn('ICON_SKIP ' + e.message);
}

console.log('VERIFY_DONE');