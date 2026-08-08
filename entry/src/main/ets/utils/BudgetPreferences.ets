import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BudgetConfig } from '../model/RecordModel';

const PREFS_NAME = 'freepdf_budget_prefs';

export class BudgetPreferences {
  private prefs: preferences.Preferences | null = null;
  private static instance: BudgetPreferences | null = null;

  private constructor() {}

  static getInstance(): BudgetPreferences {
    if (!BudgetPreferences.instance) {
      BudgetPreferences.instance = new BudgetPreferences();
    }
    return BudgetPreferences.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.prefs) return;
    this.prefs = await preferences.getPreferences(context, PREFS_NAME);
  }

  async getMonthlyBudget(): Promise<number> {
    if (!this.prefs) return 0;
    try {
      const value = await this.prefs.get('monthly_budget', 0);
      return typeof value === 'number' ? value : 0;
    } catch {
      return 0;
    }
  }

  async setMonthlyBudget(budget: number): Promise<void> {
    if (!this.prefs) throw new Error('Preferences not initialized');
    await this.prefs.put('monthly_budget', budget);
    await this.prefs.flush();
  }

  async getBudgetConfig(): Promise<BudgetConfig> {
    const monthly = await this.getMonthlyBudget();
    return {
      daily: Math.round(monthly / 30),
      weekly: Math.round(monthly / (30 / 7)),
      monthly: monthly
    };
  }

  async getDailyBudget(): Promise<number> {
    const monthly = await this.getMonthlyBudget();
    return Math.round(monthly / 30);
  }

  async getWeeklyBudget(): Promise<number> {
    const monthly = await this.getMonthlyBudget();
    return Math.round(monthly / (30 / 7));
  }

  async isFirstLaunch(): Promise<boolean> {
    if (!this.prefs) return true;
    try {
      const launched = await this.prefs.get('launched_before', false);
      return launched !== true;
    } catch {
      return true;
    }
  }

  async setLaunched(): Promise<void> {
    if (!this.prefs) return;
    await this.prefs.put('launched_before', true);
    await this.prefs.flush();
  }
}

export const budgetPrefs = BudgetPreferences.getInstance();