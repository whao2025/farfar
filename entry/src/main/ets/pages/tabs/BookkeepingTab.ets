import { GlassTokens } from '../../theme/GlassTokens';
import { common } from '@kit.AbilityKit';
import { BudgetCard } from '../../components/BudgetCard';
import { TrendCard } from '../../components/TrendCard';
import { recordDb } from '../../utils/RecordDatabase';
import { budgetPrefs } from '../../utils/BudgetPreferences';
import { BookkeepingRecord, WeekDaySpending, CategoryStat, RecordStatus } from '../../model/RecordModel';
import { GlassButton } from '../../components/GlassButton';
import { exportRecordsToXlsx, pickAndReadXlsxRows, xlsxRowsToBookkeepingText } from '../../utils/ExcelUtils';
import { saveSandboxFile } from '../../utils/PickerSaveUtils';
import { activateMLIfEnabled } from '../../utils/MlActivation';

@Component
export struct BookkeepingTab {
  @StorageProp('darkMode') dark: boolean = false;
  @StorageProp('recordRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0;
  @State monthlyBudget: number = 0;
  @State monthlyExpense: number = 0;
  @State weeklyExpense: number = 0;
  @State dailyExpense: number = 0;
  @State lastMonthExpense: number = 0;
  @State weekData: WeekDaySpending[] = [];
  @State categoryStats: CategoryStat[] = [];
  @State excelBusy: boolean = false;

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      recordDb.init(ctx as common.Context).then(() => {
        budgetPrefs.init(ctx as common.Context).then(() => {
          this.loadBudget();
          this.loadStats();
        }).catch((err: Error) => console.error('prefs init failed:', err));
      }).catch((err: Error) => console.error('db init failed:', err));
      activateMLIfEnabled(ctx as common.Context);
    }
  }

  private onRefreshTick(): void {
    this.loadStats();
  }

  private async onImportExcel(): Promise<void> {
    if (this.excelBusy) {
      return;
    }
    const host = this.getUIContext().getHostContext();
    if (!host) {
      return;
    }
    this.excelBusy = true;
    try {
      const rows = await pickAndReadXlsxRows(host as common.Context);
      if (rows.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '未读取到表格内容' });
        return;
      }
      const text = xlsxRowsToBookkeepingText(rows);
      if (text.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '未识别到金额行，请检查表格' });
        return;
      }
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/BookkeepingConfirmPage',
        params: { source: 'excel', text: text, mode: 'full' }
      });
    } catch (err) {
      console.error('import excel failed', JSON.stringify(err));
      this.getUIContext().getPromptAction().showToast({ message: 'Excel 导入失败' });
    } finally {
      this.excelBusy = false;
    }
  }

  private async onExportExcel(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) {
      return;
    }
    const ctx = host as common.Context;
    try {
      await recordDb.init(ctx);
      const records = await recordDb.getAll(RecordStatus.CONFIRMED);
      if (records.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '暂无已确认记录' });
        return;
      }
      const path = await exportRecordsToXlsx(ctx, records);
      if (!path) {
        this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
        return;
      }
      const saved = await saveSandboxFile(ctx, path, 'freepdf记账.xlsx', '.xlsx');
      this.getUIContext().getPromptAction().showToast({ message: saved ? '已导出 Excel' : '已生成，未选择导出位置' });
    } catch (err) {
      console.error('export excel failed', JSON.stringify(err));
      this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
    }
  }

  private async loadBudget(): Promise<void> {
    try {
      this.monthlyBudget = await budgetPrefs.getMonthlyBudget();
    } catch (err) {
      console.error('loadBudget failed:', err);
    }
  }

  private async onBudgetSaved(): Promise<void> {
    await this.loadBudget();
    await this.loadStats();
    this.bumpTick();
  }

  private bumpTick(): void {
    const tick = AppStorage.get<number>('recordRefreshTick') ?? 0;
    AppStorage.setOrCreate('recordRefreshTick', tick + 1);
  }

  private async loadStats(): Promise<void> {
    try {
      const today = new Date();
      const dateStr = this.formatDate(today);
      const monthPrefix = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;

      const weekStart = this.getWeekStartDate(today);
      const weekEnd = this.getWeekEndDate(today);

      const dailyRecords = recordDb.getByDateRange(dateStr, dateStr);
      const monthRecords = recordDb.getByDateRange(
        monthPrefix + '-01',
        monthPrefix + '-31'
      );
      const weekRecords = recordDb.getByDateRange(
        this.formatDate(weekStart),
        this.formatDate(weekEnd)
      );
      const lastMonthPrefix = this.lastMonthPrefix(today);
      const lastMonthTotal = recordDb.getMonthlyTotals(lastMonthPrefix);

      const daily = await dailyRecords;
      const month = await monthRecords;
      const week = await weekRecords;
      const last = await lastMonthTotal;

      this.dailyExpense = this.sumExpense(daily);
      this.monthlyExpense = this.sumExpense(month);
      this.weeklyExpense = this.sumExpense(week);
      this.lastMonthExpense = Math.abs(last.expense);
      this.weekData = this.buildWeek(weekStart, week);
      this.categoryStats = this.aggregateByCategory(month);
    } catch (err) {
      console.error('loadStats failed:', err);
    }
  }

  private sumExpense(records: BookkeepingRecord[]): number {
    return Math.abs(records.reduce((sum, r) =>
      sum + (r.type === 'expense' ? r.amount : 0), 0));
  }

  private buildWeek(weekStart: Date, weekRecords: BookkeepingRecord[]): WeekDaySpending[] {
    const today = new Date();
    const todayStr = this.formatDate(today);
    const dayNames = ['日', '一', '二', '三', '四', '五', '六'];
    const map = new Map<string, number>();
    for (const r of weekRecords) {
      const key = r.dateStr;
      const amt = Math.abs((r.type === 'expense' ? r.amount : 0));
      map.set(key, (map.get(key) ?? 0) + amt);
    }
    const data: WeekDaySpending[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i);
      const ds = this.formatDate(d);
      data.push({
        day: dayNames[d.getDay()],
        dateStr: ds,
        amount: map.get(ds) ?? 0,
        isToday: ds === todayStr
      });
    }
    return data;
  }

  private aggregateByCategory(records: BookkeepingRecord[]): CategoryStat[] {
    const map = new Map<string, number>();
    for (const r of records) {
      if (r.type !== 'expense') continue;
      const key = r.category || '其他';
      const add = Math.abs(r.amount);
      map.set(key, (map.get(key) ?? 0) + add);
    }
    const list: CategoryStat[] = [];
    map.forEach((value, key) => {
      list.push({ name: key, amount: value });
    });
    list.sort((a: CategoryStat, b: CategoryStat) => b.amount - a.amount);
    const top: CategoryStat[] = [];
    let rest = 0;
    for (let i = 0; i < list.length; i++) {
      if (i < 4) {
        top.push(list[i]);
      } else {
        rest += list[i].amount;
      }
    }
    if (rest > 0) {
      const existing = top.find((s) => s.name === '其他');
      if (existing) {
        existing.amount += rest;
      } else {
        top.push({ name: '其他', amount: rest });
      }
    }
    return top;
  }

  private lastMonthPrefix(d: Date): string {
    const y = d.getFullYear();
    const m = d.getMonth();
    if (m === 0) {
      return `${y - 1}-12`;
    }
    return `${y}-${String(m).padStart(2, '0')}`;
  }

  private formatDate(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  private getWeekStartDate(d: Date): Date {
    const start = new Date(d);
    const day = start.getDay();
    const diff = start.getDate() - day + (day === 0 ? -6 : 1);
    start.setDate(diff);
    return start;
  }

  private getWeekEndDate(d: Date): Date {
    const end = new Date(d);
    const start = this.getWeekStartDate(d);
    end.setDate(start.getDate() + 6);
    return end;
  }

  build() {
    Column({ space: 16 }) {
      Scroll() {
        Column({ space: 16 }) {
          Row({ space: 10 }) {
            GlassButton({
              label: this.excelBusy ? '处理中…' : '导入 Excel',
              dark: this.dark,
              heightVp: 40,
              fontSize: 14,
              onClickHandler: () => this.onImportExcel()
            })
              .layoutWeight(1)
            GlassButton({
              label: '导出 Excel',
              dark: this.dark,
              heightVp: 40,
              fontSize: 14,
              onClickHandler: () => this.onExportExcel()
            })
              .layoutWeight(1)
          }
          .width('100%')

          BudgetCard({
            monthlyBudget: this.monthlyBudget,
            dailyBudget: Math.round(this.monthlyBudget / 30),
            weeklyBudget: Math.round(this.monthlyBudget / (30 / 7)),
            actualDaily: this.dailyExpense,
            actualWeekly: this.weeklyExpense,
            actualMonthly: this.monthlyExpense,
            dark: this.dark,
            onBudgetSaved: () => this.onBudgetSaved()
          })
          .width('100%')

          TrendCard({
            weekData: this.weekData,
            categoryStats: this.categoryStats,
            dailyBudget: Math.round(this.monthlyBudget / 30),
            monthlyExpense: this.monthlyExpense,
            lastMonthExpense: this.lastMonthExpense,
            weekTotal: this.weeklyExpense,
            dark: this.dark
          })
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }
}
