import { common } from '@kit.AbilityKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';
import { CategoryPicker } from '../components/CategoryPicker';
import {
  Suggestion,
  BookkeepingRecord,
  RecordStatus,
  RecordSource,
  RecordType,
  CategoryInfo,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES
} from '../model/RecordModel';
import { AutoCategorizer } from '../utils/AutoCategorizer';
import { ensureMlForImg } from '../utils/MlActivation';
import { recordDb } from '../utils/RecordDatabase';

const MIN_AUTO_CONFIDENCE = 0.4;

interface ConfirmPageParams {
  source?: string;
  text?: string;
  mode?: 'full' | 'compact';
}

@Entry
@Component
struct BookkeepingConfirmPage {
  @StorageProp('darkMode') dark: boolean = false;
  @State mode: string = 'pdfToCredit';
  @State source: string = 'pdf-text';
  @State busy: boolean = false;
  @State statusMsg: string = '';
  @State pdfText: string = '';
  @State suggestions: Suggestion[] = [];
  @State selected: boolean[] = [];
  @State savedCount: number = 0;
  @State activeCatIdx: number = -1;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as ConfirmPageParams;
    this.mode = params?.mode ?? 'pdfToCredit';
    this.pdfText = params?.text ?? '';
    this.source = params?.source ?? 'pdf-text';
    if (this.pdfText) {
      if (this.source === 'img-ocr') {
        // 图片记账强制 ML：先等模型就绪再解析，否则首批分类会因 isLoaded=false 空转
        this.prepareAndParse();
      } else {
        this.parseText();
      }
    }
  }

  private async prepareAndParse(): Promise<void> {
    this.busy = true;
    this.statusMsg = '加载智能分类…';
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      await ensureMlForImg(ctx as common.Context);
    }
    await this.parseText();
  }

  private async parseText(): Promise<void> {
    this.busy = true;
    this.statusMsg = '分析中…';
    try {
      const result = await AutoCategorizer.categorizeBatch(this.pdfText, this.source as RecordSource);
      this.suggestions = result.suggestions;
      this.selected = this.suggestions.map((s: Suggestion): boolean => s.confidence >= MIN_AUTO_CONFIDENCE);
      this.statusMsg = `识别到 ${result.summary.total} 条记录`;
    } catch (err) {
      console.error('parse failed', JSON.stringify(err));
      this.statusMsg = '分析失败';
    } finally {
      this.busy = false;
    }
  }

  private toggleIndex(idx: number): void {
    this.selected = this.selected.map((v: boolean, i: number): boolean => i === idx ? !v : v);
  }

  private toggleCat(idx: number): void {
    this.activeCatIdx = this.activeCatIdx === idx ? -1 : idx;
  }

  private getCatsFor(item: Suggestion): string[] {
    if (item.type === 'income') {
      return INCOME_CATEGORIES.map((c: CategoryInfo): string => c.name);
    }
    return EXPENSE_CATEGORIES.map((c: CategoryInfo): string => c.name);
  }

  private rebuildAt(idx: number, updated: Suggestion): void {
    this.suggestions = this.suggestions.map((x: Suggestion, i: number): Suggestion => i === idx ? updated : x);
  }

  private setCategory(idx: number, name: string): void {
    const s = this.suggestions[idx];
    const updated: Suggestion = {
      amount: s.amount,
      type: s.type,
      category: name,
      confidence: s.confidence,
      note: s.note,
      merchant: s.merchant,
      date: s.date,
      timestamp: s.timestamp,
      source: s.source
    };
    this.rebuildAt(idx, updated);
  }

  private setType(idx: number, type: RecordType): void {
    const s = this.suggestions[idx];
    if (s.amount < 0 && type === 'income') {
      this.statusMsg = '退款记录不建议转为收入';
    }
    const isIncome = type === 'income';
    const catOk: boolean = isIncome
      ? INCOME_CATEGORIES.some((c: CategoryInfo): boolean => c.name === s.category)
      : EXPENSE_CATEGORIES.some((c: CategoryInfo): boolean => c.name === s.category);
    const updated: Suggestion = {
      amount: Math.abs(s.amount),
      type: type,
      category: catOk ? s.category : '其他',
      confidence: s.confidence,
      note: s.note,
      merchant: s.merchant,
      date: s.date,
      timestamp: s.timestamp,
      source: s.source
    };
    this.rebuildAt(idx, updated);
  }

  private setFromCheckbox(idx: number, val: boolean): void {
    this.selected = this.selected.map((v: boolean, i: number): boolean => i === idx ? val : v);
  }

  private getSelectedCount(): number {
    return this.suggestions.filter((s: Suggestion, i: number): boolean => this.selected[i]).length;
  }

  private isAllSelected(): boolean {
    return this.suggestions.length > 0 && this.getSelectedCount() === this.suggestions.length;
  }

  private toggleSelectAll(): void {
    const target = this.isAllSelected() ? false : true;
    this.selected = this.suggestions.map((s: Suggestion): boolean => target);
  }

  private getSelectedTotalAmount(): number {
    return this.suggestions.reduce((sum: number, s: Suggestion, i: number): number => this.selected[i] ? sum + s.amount : sum, 0);
  }

  private async onSaveSelected(): Promise<void> {
    const chosen = this.suggestions.filter((s: Suggestion, i: number): boolean => this.selected[i]);
    if (chosen.length === 0) {
      this.statusMsg = '请至少勾选一条记录';
      return;
    }
    this.busy = true;
    this.statusMsg = '保存中…';
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx) {
        await recordDb.init(ctx as common.Context);
        const prefs = await import('../utils/BudgetPreferences');
        await prefs.budgetPrefs.init(ctx as common.Context);
      }
      const now = Date.now();
      const records: BookkeepingRecord[] = chosen.map((s: Suggestion): BookkeepingRecord => ({
        id: null,
        amount: s.type === 'income' ? Math.abs(s.amount) : -Math.abs(s.amount),
        type: s.type === 'income' ? 'income' : 'expense',
        category: s.category,
        note: s.note,
        merchant: s.merchant || null,
        timestamp: s.timestamp || now,
        dateStr: this.formatTimestampToDate(s.timestamp || now),
        confidence: s.confidence,
        source: s.source,
        status: RecordStatus.CONFIRMED,
        createdAt: now
      }));

      await recordDb.batchInsert(records);
      const tick = AppStorage.get<number>('recordRefreshTick') ?? 0;
      AppStorage.setOrCreate('recordRefreshTick', tick + 1);
      this.savedCount = records.length;
      this.statusMsg = `✓ 已保存 ${this.savedCount} 条记录`;
      setTimeout(() => {
        this.getUIContext().getRouter().back();
      }, 1500);
    } catch (err) {
      console.error('save failed', JSON.stringify(err));
      this.statusMsg = '保存失败';
    } finally {
      this.busy = false;
    }
  }

  private formatTimestampToDate(ts: number): string {
    const d = new Date(ts);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  build() {
    Stack() {
      Column() {
        GlassToolbar({ dark: this.dark }) {
          Row() {
            Blank()
            Text('记账确认')
              .fontSize(16)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            Blank()
          }
          .width('100%')
        }

        Column({ space: 12 }) {
          if (this.busy || this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(14)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .textAlign(TextAlign.Center)
              .margin({ left: 24, right: 24 })
          }

          if (this.suggestions.length > 0 && !this.busy) {
            Text(`识别到 ${this.suggestions.length} 条记录 | 已选 ${this.getSelectedCount()} | 合计: ¥${Math.abs(this.getSelectedTotalAmount()).toFixed(2)}`)
              .fontSize(13)
              .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
              .textAlign(TextAlign.Center)

            GlassButton({
              label: this.isAllSelected() ? '取消全选' : '全选',
              dark: this.dark,
              heightVp: 36,
              fontSize: 14,
              onClickHandler: () => this.toggleSelectAll()
            })
              .width(120)

            // 全量可滚动勾选列表
            Scroll() {
              Column({ space: 10 }) {
                ForEach(this.suggestions,
                  (item: Suggestion, idx: number) => {
                    Row({ space: 8 }) {
                      Checkbox()
                        .select(this.selected[idx])
                        .onChange((v: boolean) => this.setFromCheckbox(idx, v))
                        .hitTestBehavior(HitTestMode.Block)
Column({ space: 4 }) {
        Row() {
                          Text(item.type === 'income' ? '+¥' : '-¥')
                            .fontSize(16)
                            .fontColor(item.type === 'income' ? '#10B981' : '#EF4444')
                            .fontWeight(FontWeight.Bold)
                          Text(Math.abs(item.amount).toFixed(2))
                            .fontSize(16)
                            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
                            .fontWeight(FontWeight.Bold)
Blank()
          Text(this.activeCatIdx === idx ? '收起' : '调整')
            .fontSize(11)
            .fontColor(this.dark ? '#10B981' : '#059669')
            .onClick(() => this.toggleCat(idx))
            .hitTestBehavior(HitTestMode.Block)
          Text(`[${item.category}]`)
            .fontSize(12)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

                        Text(item.note)
                          .fontSize(11)
                          .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
                          .textAlign(TextAlign.Start)
                          .maxLines(2)

Text(`置信度 ${(item.confidence * 100).toFixed(0)}%`)
          .fontSize(10)
          .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')

        if (this.activeCatIdx === idx) {
          Row({ space: 8 }) {
            Text('支出')
              .fontSize(12)
              .fontWeight(item.type === 'expense' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(item.type === 'expense'
                ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
                : (this.dark ? '#A9A9B5' : '#6B6B76'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(12)
              .border({ width: 1, color: item.type === 'expense'
                ? (this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
                : Color.Transparent })
              .onClick(() => this.setType(idx, 'expense'))
              .hitTestBehavior(HitTestMode.Block)
            Text('收入')
              .fontSize(12)
              .fontWeight(item.type === 'income' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(item.type === 'income'
                ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
                : (this.dark ? '#A9A9B5' : '#6B6B76'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(12)
              .border({ width: 1, color: item.type === 'income'
                ? (this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
                : Color.Transparent })
              .onClick(() => this.setType(idx, 'income'))
              .hitTestBehavior(HitTestMode.Block)
          }
          CategoryPicker({
            categories: this.getCatsFor(item),
            selected: item.category,
            dark: this.dark,
            onPick: (name: string) => this.setCategory(idx, name)
          })
        }
      }
      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 8 })
                    .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
                    .borderWidth(0)
                    .borderRadius(8)
                    .onClick(() => {
                      if (this.activeCatIdx !== idx) {
                        this.toggleIndex(idx);
                      }
                    })
                  },
                  (item: Suggestion, idx: number) => idx.toString() + '_' + (this.selected[idx] ? 1 : 0) + '_' + item.type + '_' + item.category
                )
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          } else if (!this.busy && this.pdfText) {
            Text('未识别到有效账单记录')
              .fontSize(14)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .textAlign(TextAlign.Center)
              .margin({ left: 24, right: 24 })
          }

          if (!this.busy && this.suggestions.length > 0) {
            GlassButton({
              label: `保存选中 (${this.getSelectedCount()})`,
              dark: this.dark,
              heightVp: 48,
              fontSize: 15,
              onClickHandler: () => this.onSaveSelected()
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, top: 8, bottom: 16 })
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundBlurStyle(GlassTokens.BLUR)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
  }
}
