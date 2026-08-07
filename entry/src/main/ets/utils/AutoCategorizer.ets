import { AmountParser } from './AmountParser';
import { budgetPrefs } from './BudgetPreferences';
import {
  BookkeepingRecord,
  Suggestion,
  CategoryInfo,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES
} from '../model/RecordModel';

export interface CategorySummary {
  total: number;
  byCategory: Record<string, number>;
  totalAmount: number;
}

export interface CategorizationResult {
  suggestions: Suggestion[];
  summary: CategorySummary;
}

export class AutoCategorizer {
  static getCategories(): CategoryInfo[] {
    return EXPENSE_CATEGORIES.concat(INCOME_CATEGORIES);
  }

  static async categorizeBatch(
    text: string,
    source: 'pdf-text' | 'pdf-ocr' = 'pdf-text'
  ): Promise<CategorizationResult> {
    const suggestions = AmountParser.parse(text, source);
    const summary = AutoCategorizer.buildSummary(suggestions);
    const merchantMap = await AutoCategorizer.loadMerchantMap();

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

    return {
      suggestions: enhanced,
      summary
    };
  }

  private static buildSummary(suggestions: Suggestion[]): CategorySummary {
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

  private static async loadMerchantMap(): Promise<Map<string, string>> {
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
    return suggestions.filter(AutoCategorizer.validateSuggestion);
  }

  static async getSuggestionsForEdit(text: string): Promise<Suggestion[]> {
    const result = await AutoCategorizer.categorizeBatch(text);
    return AutoCategorizer.filterValid(result.suggestions);
  }
}

export const autoCategorizer = AutoCategorizer;