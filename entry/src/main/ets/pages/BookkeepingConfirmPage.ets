import { common } from '@kit.AbilityKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';
import { Suggestion, BookkeepingRecord, RecordStatus } from '../model/RecordModel';
import { AutoCategorizer } from '../utils/AutoCategorizer';
import { recordDb } from '../utils/RecordDatabase';

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
  @State savedCount: number = 0;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as ConfirmPageParams;
    this.mode = params?.mode ?? 'pdfToCredit';
    this.pdfText = params?.text ?? '';
    this.source = params?.source ?? 'pdf-text';
    if (this.pdfText) {
      this.parseText();
    }
  }

  private async parseText(): Promise<void> {
    this.busy = true;
    this.statusMsg = '分析中…';
    try {
      const result = await AutoCategorizer.categorizeBatch(this.pdfText, this.source === 'pdf-ocr' ? 'pdf-ocr' : 'pdf-text');
      this.suggestions = result.suggestions;
      this.statusMsg = `识别到 ${result.summary.total} 条记录`;
    } catch (err) {
      console.error('parse failed', JSON.stringify(err));
      this.statusMsg = '分析失败';
    } finally {
      this.busy = false;
    }
  }

  private async onSaveAll(): Promise<void> {
    if (this.suggestions.length === 0) {
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
      const records: BookkeepingRecord[] = this.suggestions.map((s: Suggestion): BookkeepingRecord => ({
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

  private getTotalAmount(): number {
    return this.suggestions.reduce((sum, s) => sum + s.amount, 0);
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

        Column({ space: 20 }) {
          if (this.busy || this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(14)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .textAlign(TextAlign.Center)
              .margin({ left: 24, right: 24 })
          }

          if (this.suggestions.length > 0 && !this.busy) {
            Text(`识别到 ${this.suggestions.length} 条记录 | 合计: ¥${Math.abs(this.getTotalAmount()).toFixed(2)}`)
              .fontSize(13)
              .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
              .textAlign(TextAlign.Center)

            // 显示前 3 条建议预览
            Column({ space: 10 }) {
              ForEach(this.suggestions.slice(0, Math.min(3, this.suggestions.length)),
                (item: Suggestion, idx: number) => {
                  Column() {
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
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                  .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
                  .borderWidth(0)
                  .borderRadius(8)
                },
                (item: Suggestion, idx: number) => idx.toString()
              )
            }
            .padding({ left: 16, right: 16 })
          } else if (!this.busy && this.pdfText) {
            Text('未识别到有效账单记录')
              .fontSize(14)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .textAlign(TextAlign.Center)
              .margin({ left: 24, right: 24 })
          }

          if (!this.busy && this.suggestions.length > 0) {
            GlassButton({
              label: '全部保存到记账',
              dark: this.dark,
              heightVp: 48,
              fontSize: 15,
              onClickHandler: () => this.onSaveAll()
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding(20)
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