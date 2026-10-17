import { AmountParser } from './AmountParser';
import {
  Suggestion,
  CategoryInfo,
  RecordSource,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES,
  MERCHANT_MAP
} from '../model/RecordModel';
import { CategorizationResult, CategorySummary } from './AutoCategorizerTypes';
import { getBillClassifier } from './ml/BillClassifier';

/**
 * 记账分类「规则引擎」——纯本地关键词 + 商户映射表。
 * 阶段 C 的 ML 作为 enhance 钩子注入（默认 null，规则兜底）。
 */
export type EnhanceFn = (suggestions: Suggestion[]) => Promise<Suggestion[]>;

const EXPENSE_NAMES: string[] = EXPENSE_CATEGORIES.map((c: CategoryInfo): string => c.name);
const INCOME_NAMES: string[] = INCOME_CATEGORIES.map((c: CategoryInfo): string => c.name);

const ML_FALLBACK_CONF = 0.30;
const ML_FALLBACK_MARGIN = 0.03;

export class RuleCategorizer {
  // 预留 ML 增强钩子，默认关闭（null = 不启用）
  static enhance: EnhanceFn | null = null;

  // ML 增强实现：逐条调用 BillClassifier，置信度过低或失败则保留规则结果
  static mlEnhance: EnhanceFn = async (suggestions: Suggestion[]): Promise<Suggestion[]> => {
    const classifier = getBillClassifier();
    if (!classifier.isLoaded()) {
      return suggestions;
    }
    const enhanced: Suggestion[] = [];
    for (const s of suggestions) {
      const note = (s.note || '').trim();
      const merchant = (s.merchant || '').trim();
      // 消费端守卫：退款、纯金额/时间行、支付动词+金额 形态一律不送 ML，保留规则结果
      if (s.amount < 0 || /退回|退款/.test(note)) {
        enhanced.push(s);
        continue;
      }
      // 仅「无商户上下文 且 纯金额/通道金额」才跳过；有品名上下文（如 note=¥16 + merchant=品名行）须送 ML
      const isBareAmount: boolean = /^[\s¥￥\-]?\d+(?:[,.]\d+)?$/.test(note)
        || /^(?:微信支付|支付宝|银联|云闪付)[\s¥￥]?\d/.test(note);
      if (isBareAmount && merchant.length === 0) {
        enhanced.push(s);
        continue;
      }
      // merchant==note 去重，避免商户名重复膨胀输入
      const actList = merchant.length > 0 && merchant !== note ? merchant + ' ' + note : (merchant.length > 0 ? merchant : note);
      const mlResult = await classifier.classify(actList);
      let result = s;
      if (mlResult && mlResult.category && mlResult.category !== '其他') {
        // 类别守卫：expense 只收支出类、income 只收收入类，防「工资/理财」污染支出记录
        const catOk: boolean = s.type === 'income'
          ? INCOME_NAMES.includes(mlResult.category)
          : EXPENSE_NAMES.includes(mlResult.category);
        const margin: number = mlResult.confidence - (mlResult.secondConfidence ?? 0);
        // 仅「规则=其他」时允许 ML 改判，且须过置信/边际门槛；规则已有分类不覆写
        const useMl: boolean = catOk && s.category === '其他' &&
          mlResult.confidence >= ML_FALLBACK_CONF && margin >= ML_FALLBACK_MARGIN;
        if (useMl) {
          result = {
            amount: s.amount,
            type: s.type,
            category: mlResult.category,
            confidence: Math.max(mlResult.confidence, s.confidence),
            note: s.note,
            merchant: s.merchant,
            date: s.date,
            timestamp: s.timestamp,
            source: s.source
          };
        }
        console.log(
          'ML classify input="' + actList + '" ->',
          mlResult.category, 'conf=' + mlResult.confidence.toFixed(3),
          'sec=' + (mlResult.secondConfidence ?? 0).toFixed(3),
          'margin=' + margin.toFixed(3),
          'catOk=' + catOk, 'useMl=' + useMl, 'rule=' + s.category
        );
      }
      enhanced.push(result);
    }
    return enhanced;
  };

  static getCategories(): CategoryInfo[] {
    return EXPENSE_CATEGORIES.concat(INCOME_CATEGORIES);
  }

  static async categorizeBatch(text: string, source: RecordSource = 'pdf-text'): Promise<CategorizationResult> {
    const suggestions = AmountParser.parse(text, source);
    const summary = RuleCategorizer.buildSummary(suggestions);
    const merchantMap = await RuleCategorizer.loadMerchantMap();

    const enhanced: Suggestion[] = [];
    for (const s of suggestions) {
      if (s.merchant && merchantMap.has(s.merchant)) {
        const mappedCategory: string = merchantMap.get(s.merchant) as string;
        enhanced.push({
          amount: s.amount,
          type: s.type,
          category: mappedCategory,
          confidence: Math.max(s.confidence, 0.8),
          note: s.note,
          merchant: s.merchant,
          date: s.date,
          timestamp: s.timestamp,
          source: s.source
        });
      } else {
        enhanced.push(s);
      }
    }

    let result = enhanced;
    if (RuleCategorizer.enhance) {
      try {
        result = await RuleCategorizer.enhance(enhanced);
      } catch (err) {
        console.error('rule enhance failed, fallback to rule', JSON.stringify(err));
        result = enhanced;
      }
    }

    return {
      suggestions: result,
      summary
    };
  }

  static buildSummary(suggestions: Suggestion[]): CategorySummary {
    const byCategory: Record<string, number> = {};
    let totalAmount = 0;

    for (const s of suggestions) {
      byCategory[s.category] = (byCategory[s.category] || 0) + s.amount;
      totalAmount += s.amount;
    }

    return {
      total: suggestions.length,
      byCategory,
      totalAmount
    };
  }

  static async loadMerchantMap(): Promise<Map<string, string>> {
    const map = new Map<string, string>();
    for (let i = 0; i < MERCHANT_MAP.length; i++) {
      map.set(MERCHANT_MAP[i].name, MERCHANT_MAP[i].category);
    }
    return map;
  }

  static validateSuggestion(s: Suggestion): boolean {
    return (
      typeof s.amount === 'number' &&
      !isNaN(s.amount) &&
      Math.abs(s.amount) > 0 &&
      Math.abs(s.amount) < 100000 &&
      typeof s.category === 'string' &&
      s.category.length > 0 &&
      typeof s.note === 'string' &&
      ['expense', 'income'].includes(s.type) &&
      typeof s.confidence === 'number' &&
      s.confidence >= 0 &&
      s.confidence <= 1.0
    );
  }

  static filterValid(suggestions: Suggestion[]): Suggestion[] {
    return suggestions.filter(RuleCategorizer.validateSuggestion);
  }
}