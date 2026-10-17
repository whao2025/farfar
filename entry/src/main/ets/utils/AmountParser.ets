import {
  ParsedAmount,
  Suggestion,
  RecordSource,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES,
  REFUND_KEYWORDS,
  TOTAL_LABELS,
  MERCHANT_MAP,
  MERCHANT_EXCLUDE,
  MERCHANT_EXCLUDE_META
} from '../model/RecordModel';

interface MoneyCandidate {
  amount: number;
  raw: string;
  index: number;
  hasLabel: boolean;
  label: string;
  hasSymbol: boolean;
  hasDecimal: boolean;
}

interface LineContext {
  refund: boolean;
  date: string | null;
  merchant: string | null;
}

interface ParsedEntry {
  raw: string;
  label: string | null;
  money: MoneyCandidate | null;
  type: 'expense' | 'income' | 'refund';
  category: string;
  dateStr: string | null;
  confidence: number;
}

let TOTAL_RE: RegExp | null = null;

function buildTotalRe(): RegExp {
  if (TOTAL_RE) {
    return TOTAL_RE;
  }
  const joined = TOTAL_LABELS.join('|');
  TOTAL_RE = new RegExp(`(${joined})[:：\\s]*([\\-￥¥]?\\d+(?:,\\d{3})*(?:\\.\\d{1,2})?)`, 'i');
  return TOTAL_RE;
}

const DATE_RE = /\d{4}[-/年]\d{1,2}(?:[-/月]\d{1,2})?/;
const TIME_RE = /\d{1,2}:\d{2}(?::\d{2})?/;
const PHONE_RE = /\d{7,14}/;
const ORDER_RE = /(?:单号|流水号|订单号|编号|号码)[:：]?\s*\d+/i;
export const PAGE_MARKER_RE = /^---\s*第\s*\d+\s*页\s*---$/;
// 计量词后缀（营养/数量单位）→ 数字是克数/件数而非金额，如「163 kcal」「≈62.1 mg/杯」「共1件」
const UNIT_TAIL_RE = /^\s*(?:kcal|mg\/杯|mg|ml|g\/杯|g|kg|件|份|杯|袋|盒|克|毫升|h|小时|分钟)/i;
const INCOME_WORDS = ['收入', '到账', '工资', '奖金', '薪水', '薪酬', '利息', '理财', '基金', '分红', '存入'];
const MERCHANT_META_RE = /共\s*\d+\s*件|^---\s*第\s*\d+\s*页\s*---/;

export class AmountParser {
  static parseLine(line: string): ParsedAmount | null {
    const entry = AmountParser.parseEntry(line);
    if (!entry.money) {
      return null;
    }
    const amount = entry.type === 'refund' ? -Math.abs(entry.money.amount) : entry.money.amount;
    return {
      amount: amount,
      type: entry.type,
      category: entry.category,
      confidence: entry.confidence
    };
  }

  static parse(text: string, source: RecordSource = 'pdf-text'): Suggestion[] {
const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    const suggestions: Suggestion[] = [];
    const ctx: LineContext = { refund: false, date: null, merchant: null };
    const seen: Set<string> = new Set();

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // 页标记（OCR 块边界/一图多账单）：重置跨行上下文，避免泄漏到下一条记录
      if (PAGE_MARKER_RE.test(line)) {
        ctx.refund = false;
        ctx.date = null;
        ctx.merchant = null;
        continue;
      }

      // KV 上下文：交易类型:退款 / 日期:xxx / 商户 只更新状态，不成记录
      if (REFUND_KEYWORDS.some(kw => line.includes(kw))) {
        ctx.refund = true;
      }
      const dateMatch = line.match(DATE_RE);
      if (dateMatch && /日期|时间|交易时间/.test(line)) {
        ctx.date = dateMatch[0];
      }
      const merchant = AmountParser.extractMerchant(line);
      if (merchant) {
        ctx.merchant = merchant;
      }

      const entry = AmountParser.parseEntry(line);
      if (!entry.money) {
        continue;
      }

      // 跨行上下文：把最近的退款/日期/商户应用到当前金额
      const effectiveRefund = ctx.refund || entry.type === 'refund';
      const effectiveDate = entry.dateStr !== null ? entry.dateStr : ctx.date;
      const effectiveMerchant = AmountParser.extractMerchant(line) ?? ctx.merchant;

      let amount = entry.money.amount;
      let type: 'expense' | 'income' | 'refund' = entry.type;
      if (effectiveRefund && type !== 'income') {
        type = 'refund';
        amount = -Math.abs(amount);
      }

      let category = entry.category;
      if (effectiveMerchant !== null) {
        const byMerchant = AmountParser.classifyByMerchant(effectiveMerchant);
        if (byMerchant !== null) {
          category = byMerchant;
        }
      }

      const timestamp = effectiveDate !== null ? AmountParser.dateToTimestamp(effectiveDate) : Date.now();

      // 去重：同金额+同分类+同日期 仅保留首条，避免页签/重复行重复落库
      const key = `${amount.toFixed(2)}|${type}|${category}|${effectiveDate ?? ''}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);

      suggestions.push({
        amount: amount,
        type: type,
        category: category,
        confidence: entry.confidence,
        note: line.substring(0, 50),
        merchant: effectiveMerchant !== null ? effectiveMerchant : undefined,
        date: effectiveDate !== null ? effectiveDate : undefined,
        timestamp: timestamp,
        source: source
      });

      // 消费一次上下文，避免污染下一条记录
      ctx.refund = false;
      ctx.date = null;
      ctx.merchant = null;
    }

    // 置信优先排序：带 ¥/标签的信条靠前，OCR 噪声（营养/克数）沉底
    return suggestions.sort((a, b) => b.confidence - a.confidence || Math.abs(b.amount) - Math.abs(a.amount));
  }

  private static parseEntry(line: string): ParsedEntry {
    const trimmed = line.trim();
    const empty: ParsedEntry = {
      raw: trimmed,
      label: null,
      money: null,
      type: 'expense',
      category: '',
      dateStr: null,
      confidence: 0
    };

    if (PAGE_MARKER_RE.test(trimmed) || trimmed.length === 0) {
      return empty;
    }

    const dateStr = AmountParser.extractDate(trimmed);
    const labelMoney = AmountParser.findLabelMoney(trimmed);
    if (labelMoney && AmountParser.isPlausibleAmount(labelMoney.amount)) {
      const type = AmountParser.detectType(trimmed, labelMoney.amount);
      const category = AmountParser.classify(trimmed);
      return {
        raw: trimmed,
        label: labelMoney.label,
        money: labelMoney,
        type: type,
        category: category,
        dateStr: dateStr,
        confidence: AmountParser.calculateConfidence(trimmed, labelMoney.amount, category, true)
      };
    }

    // 兜底：通用数字候选，排除日期/时间/电话/单号/页签
    const money = AmountParser.findFallbackMoney(trimmed);
    if (money) {
      const type = AmountParser.detectType(trimmed, money.amount);
      const category = AmountParser.classify(trimmed);
      return {
        raw: trimmed,
        label: null,
        money: money,
        type: type,
        category: category,
        dateStr: dateStr,
        confidence: AmountParser.calculateConfidence(trimmed, money.amount, category, false)
      };
    }

    return empty;
  }

  private static findLabelMoney(line: string): MoneyCandidate | null {
    const re = buildTotalRe();
    const m = line.match(re);
    if (!m || !m[2]) {
      return null;
    }
    const amount = AmountParser.normalizeAmount(m[2]);
    if (amount === null) {
      return null;
    }
    return {
      amount: amount,
      raw: m[2],
      index: m.index !== undefined ? m.index : 0,
      hasLabel: true,
      label: m[1],
      hasSymbol: /[¥￥]/.test(m[2]),
      hasDecimal: /\.\d{1,2}$/.test(m[2])
    };
  }

  private static findFallbackMoney(line: string): MoneyCandidate | null {
    // 剔除日期/时间/电话/单号/页签后，在剩余片段中取数字
    let candidateText = line;
    candidateText = candidateText.replace(DATE_RE, ' ');
    candidateText = candidateText.replace(TIME_RE, ' ');
    candidateText = candidateText.replace(PHONE_RE, ' ');
    candidateText = candidateText.replace(ORDER_RE, ' ');
    // 退款上下文剔除银行卡尾号，避免「退回支付卡(工商银行6986)」的 6986 误当金额
    if (REFUND_KEYWORDS.some(kw => line.includes(kw))) {
      candidateText = candidateText.replace(/(?:支付卡|银行卡|尾号|卡号)[^\d]{0,12}\d{4}/g, ' ');
    }
    candidateText = candidateText.replace(/，/g, ',')
      .replace(/－/g, '-')
      .replace(/．/g, '.')
      .replace(/[０-９]/g, m => String.fromCharCode(m.charCodeAt(0) - 0xFEE0));

    const matches = candidateText.matchAll(/[\-￥¥]?\s*\d+(?:,\d{3})*(?:\.\d{1,2})?/g);
    const cands: MoneyCandidate[] = [];
    let m = matches.next();
    while (!m.done) {
      const raw = m.value[0].replace(/\s/g, '');
      const amount = AmountParser.normalizeAmount(raw);
      const endIdx = (m.value.index !== undefined ? m.value.index : 0) + m.value[0].length;
      const tail = candidateText.slice(endIdx);
      if (amount !== null && AmountParser.isPlausibleAmount(amount) && !UNIT_TAIL_RE.test(tail)) {
        cands.push({
          amount: amount,
          raw: raw,
          index: m.value.index !== undefined ? m.value.index : 0,
          hasLabel: false,
          label: '',
          hasSymbol: /[¥￥]/.test(raw),
          hasDecimal: /\.\d{1,2}$/.test(raw)
        });
      }
      m = matches.next();
    }
    if (cands.length === 0) {
      return null;
    }
    // 综合评分选最像金额的：带符号 > 带小数 > 位置靠后
    cands.sort((a, b) => AmountParser.scoreCandidate(b) - AmountParser.scoreCandidate(a));
    return cands[0];
  }

  private static scoreCandidate(c: MoneyCandidate): number {
    let score = 0;
    if (c.hasSymbol) {
      score += 100;
    }
    if (c.hasDecimal) {
      score += 10;
    }
    score += c.index;
    return score;
  }

  private static normalizeAmount(raw: string): number | null {
    let s = raw.trim()
      .replace(/，/g, ',')
      .replace(/－/g, '-')
      .replace(/．/g, '.')
      .replace(/[０-９]/g, m => String.fromCharCode(m.charCodeAt(0) - 0xFEE0))
      .replace(/[,]/g, '')
      .replace(/[^\d\.\-]/g, '');

    const n = parseFloat(s);
    if (isNaN(n) || Math.abs(n) > 99999 || Math.abs(n) < 0.01) {
      return null;
    }
    return n;
  }

  private static isPlausibleAmount(n: number): boolean {
    return n > 0 && n < 99999;
  }

  private static detectType(text: string, amount: number): 'expense' | 'income' | 'refund' {
    if (REFUND_KEYWORDS.some(kw => text.includes(kw))) {
      return 'refund';
    }
    if (amount < 0) {
      return 'refund';
    }
    if (INCOME_WORDS.some(kw => text.includes(kw))) {
      return 'income';
    }
    return 'expense';
  }

  private static classify(text: string): string {
    const isIncome = INCOME_WORDS.some(kw => text.includes(kw));
    const cats = isIncome ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
    // 最长命中优先：长词（如「咖啡厅」）优先于子串（「咖啡」），避免首命中误判
    let best: string = '其他';
    let bestLen: number = 0;
    for (const cat of cats) {
      if (cat.keywords.length === 0) {
        continue;
      }
      for (let i = 0; i < cat.keywords.length; i++) {
        const kw = cat.keywords[i];
        if (text.includes(kw) && kw.length > bestLen) {
          best = cat.name;
          bestLen = kw.length;
        }
      }
    }
    return best;
  }

  private static classifyByMerchant(merchant: string): string | null {
    let best: string | null = null;
    let bestLen: number = 0;
    for (const cat of EXPENSE_CATEGORIES) {
      if (cat.keywords.length === 0) {
        continue;
      }
      for (let i = 0; i < cat.keywords.length; i++) {
        const kw = cat.keywords[i];
        if (merchant.includes(kw) && kw.length > bestLen) {
          best = cat.name;
          bestLen = kw.length;
        }
      }
    }
    return best;
  }

  private static calculateConfidence(text: string, amount: number, category: string, hasLabel: boolean): number {
    let score = 0.15;
    if (hasLabel) {
      score += 0.4;
    }
    if (/[¥￥]|元/.test(text)) {
      score += 0.15;
    }
    if (category !== '其他') {
      score += 0.15;
    }
    if (/\.\d{1,2}$/.test(String(amount))) {
      score += 0.05;
    }
    return Math.min(score, 1.0);
  }

  private static extractDate(text: string): string | null {
    const m = text.match(DATE_RE);
    return m ? m[0] : null;
  }

  private static extractMerchant(text: string): string | null {
    // MERCHANT_MAP 最长精确名（防「美团」子串吞「美团打车」）
    let bestName: string | null = null;
    for (let i = 0; i < MERCHANT_MAP.length; i++) {
      const name = MERCHANT_MAP[i].name;
      if (text.includes(name) && (bestName === null || name.length > bestName.length)) {
        bestName = name;
      }
    }
    if (bestName !== null) {
      return bestName;
    }
    // 先剥离支付通道前缀，再判排除词（避免「微信支付 禾牛肉饭 ¥45」整行被误杀）
    const stripped = text.trim().replace(/^(?:微信支付|支付宝|银联|云闪付)\s*/, '');
    if (stripped.length === 0) {
      return null;
    }
    if (MERCHANT_EXCLUDE.some(w => stripped.includes(w))) {
      return null;
    }
    // 元信息/页标记/件数行使行捕获前置排除（先于关键词，防止「咖啡」命中「咖啡因」等子串）
    if (MERCHANT_EXCLUDE_META.some(w => stripped.includes(w)) || MERCHANT_META_RE.test(stripped)) {
      return null;
    }
    // 品名/商户行捕获：命中分类关键词（奶茶/泡芙/炒饭…）或为非金额非元信息长行，均视为商户上下文
    if (AmountParser.hasCategoryKeyword(stripped) || AmountParser.isMerchantBodyRow(stripped)) {
      return stripped.substring(0, 20);
    }
    // 商户行回退捕获：含支付/收款/商户等标志且非纯金额行 → 整行作为商户上下文
    if (/支付|收款|商户|付款给|消费于|购于/.test(stripped) && !/^[\-￥¥]?\d/.test(stripped)) {
      return stripped.substring(0, 20);
    }
    return null;
  }

  private static isMerchantBodyRow(text: string): boolean {
    const t = text.trim();
    if (t.length < 4) {
      return false;
    }
    if (/^[\-￥¥]?\d/.test(t)) {
      return false;
    }
    if (MERCHANT_EXCLUDE_META.some(w => t.includes(w))) {
      return false;
    }
    if (MERCHANT_META_RE.test(t)) {
      return false;
    }
    return true;
  }

  private static hasCategoryKeyword(text: string): boolean {
    for (const cat of EXPENSE_CATEGORIES) {
      if (cat.name === '其他') {
        continue;
      }
      if (cat.keywords.some(kw => text.includes(kw))) {
        return true;
      }
    }
    return false;
  }

  private static dateToTimestamp(dateStr: string): number {
    const normalized = dateStr
      .replace(/年/g, '-').replace(/月/g, '-').replace(/日/g, '')
      .replace(/\//g, '-');

    const parts = normalized.split('-').map(p => parseInt(p));
    if (parts.length >= 3) {
      return new Date(parts[0], parts[1] - 1, parts[2]).getTime();
    }
    return Date.now();
  }

  static parseAmountOnly(text: string): number | null {
    const label = AmountParser.findLabelMoney(text);
    if (label) {
      return label.amount;
    }
    const fallback = AmountParser.findFallbackMoney(text);
    return fallback ? fallback.amount : null;
  }

  static isRefund(text: string): boolean {
    return REFUND_KEYWORDS.some(kw => text.includes(kw));
  }

  static getCategoryFromText(text: string): string {
    return AmountParser.classify(text);
  }
}
