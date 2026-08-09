import { Suggestion, CategoryInfo, RecordSource } from '../model/RecordModel';
import { CategorizationResult } from './AutoCategorizerTypes';
import { RuleCategorizer, EnhanceFn } from './RuleCategorizer';

/**
 * 记账分类门面——内部委托 RuleCategorizer（规则引擎）。
 * 调用点零改动（保持旧静态签名）；为阶段 C 预留 setEnhance 钩子（默认关闭）。
 */
export class AutoCategorizer {
  static setEnhance(fn: EnhanceFn | null): void {
    RuleCategorizer.enhance = fn;
  }

  static getCategories(): CategoryInfo[] {
    return RuleCategorizer.getCategories();
  }

  static async categorizeBatch(
    text: string,
    source: RecordSource = 'pdf-text'
  ): Promise<CategorizationResult> {
    return RuleCategorizer.categorizeBatch(text, source);
  }

  static validateSuggestion(s: Suggestion): boolean {
    return RuleCategorizer.validateSuggestion(s);
  }

  static filterValid(suggestions: Suggestion[]): Suggestion[] {
    return RuleCategorizer.filterValid(suggestions);
  }

  static async getSuggestionsForEdit(text: string): Promise<Suggestion[]> {
    const result = await RuleCategorizer.categorizeBatch(text);
    return RuleCategorizer.filterValid(result.suggestions);
  }
}