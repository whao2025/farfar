import { AmountParser } from './AmountParser';
import {
  Suggestion,
  CategoryInfo,
  RecordSource,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES
} from '../model/RecordModel';
import { CategorizationResult, CategorySummary } from './AutoCategorizerTypes';
import { getBillClassifier } from './ml/BillClassifier';

/**
 * 记账分类「规则引擎」——纯本地关键词 + 商户映射表。
 * 阶段 C 的 ML 作为 enhance 钩子注入（默认 null，规则兜底）。
 */
export type EnhanceFn = (suggestions: Suggestion[]) => Promise<Suggestion[]>;

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
      const note = s.note || '';
      const mlResult = await classifier.classify(note);
      if (mlResult && mlResult.confidence >= 0.6) {
        enhanced.push({
          amount: s.amount,
          type: s.type,
          category: mlResult.category,
          confidence: mlResult.confidence,
          note: s.note,
          merchant: s.merchant,
          timestamp: s.timestamp,
          source: s.source
        });
      } else {
        enhanced.push(s);
      }
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
    map.set('沃尔玛', '购物');
    map.set('山姆', '购物');
    map.set('永辉', '购物');
    map.set('华联', '购物');
    map.set('肯德基', '餐饮');
    map.set('麦当劳', '餐饮');
    map.set('星巴克', '餐饮');
    map.set('瑞幸', '餐饮');
    map.set('汉堡王', '餐饮');
    map.set('美团', '购物');
    map.set('饿了么', '餐饮');
    map.set('淘宝', '购物');
    map.set('京东', '购物');
    map.set('天猫', '购物');
    map.set('拼多多', '购物');
    map.set('滴滴', '交通');
    map.set('中石油', '交通');
    map.set('中石化', '交通');
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