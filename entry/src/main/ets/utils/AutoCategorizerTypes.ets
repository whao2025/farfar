import { Suggestion } from '../model/RecordModel';

export interface CategorySummary {
  total: number;
  byCategory: Record<string, number>;
  totalAmount: number;
}

export interface CategorizationResult {
  suggestions: Suggestion[];
  summary: CategorySummary;
}