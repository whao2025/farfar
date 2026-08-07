import { GlassTokens } from '../theme/GlassTokens';
import { Suggestion, BookkeepingRecord, RecordStatus } from '../model/RecordModel';
import { AmountParser } from '../utils/AmountParser';

@Component
export struct AutoRecordConfirm {
  @StorageProp('darkMode') darkMode: boolean = false;
  @Prop suggestions: Suggestion[];
  @State current: number = 0;
  @State editedRecords: Map<number, Partial<Suggestion>> = new Map();
  @State currentItem: Suggestion = {
    amount: 0,
    type: 'expense',
    category: '其他',
    confidence: 0,
    note: '',
    source: 'pdf-text'
  };
  @Event closeDialog: () => void;
  @Event saveRecords: (records: BookkeepingRecord[]) => void;

  aboutToAppear() {
    this.refreshCurrentItem();
  }

  private refreshCurrentItem(): void {
    this.currentItem = this.getCurrentSuggestion();
  }

  private getCategories(): string[] {
    return ['餐饮', '交通', '购物', '医疗', '娱乐', '居居', '通讯', '理财', '工资', '其他'];
  }

  private getCurrentSuggestion(): Suggestion {
    const item = this.suggestions[this.current] || {
      amount: 0,
      type: 'expense',
      category: '其他',
      confidence: 0,
      note: '',
      source: 'pdf-text'
    };
    const edited = this.editedRecords.get(this.current) || {};
    return Object.assign({}, item, edited);
  }

  private updateField(key: string, value: any): void {
    const current = this.editedRecords.get(this.current) || {};
    current[key] = value;
    this.editedRecords.set(this.current, current);
  }

  private handleSave(): void {
    const records: BookkeepingRecord[] = [];
    const now = Date.now();

    for (let i = 0; i < this.suggestions.length; i++) {
      const original = this.suggestions[i];
      const edited = this.editedRecords.get(i) || {};
      const merged = Object.assign({}, original, edited);

      records.push({
        id: null,
        amount: merged.type === 'income' ? Math.abs(merged.amount) : -Math.abs(merged.amount),
        type: merged.type,
        category: merged.category,
        note: merged.note,
        merchant: merged.merchant || null,
        timestamp: merged.timestamp || now,
        dateStr: this.formatTimestampToDate(merged.timestamp || now),
        confidence: merged.confidence,
        source: merged.source,
        status: RecordStatus.CONFIRMED,
        createdAt: now
      });
    }

    this.saveRecords(records);
  }

  private formatTimestampToDate(ts: number): string {
    const d = new Date(ts);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  private formatAmount(amount: number, type: string): string {
    if (type === 'income') return '+¥' + Math.abs(amount).toFixed(2);
    return '-¥' + Math.abs(amount).toFixed(2);
  }

  private getTextClass(): string {
    return this.darkMode ? 'text-dark' : 'text-light';
  }

  build() {
    Column() {
      // Header
      Column() {
        Text(`记录 ${this.current + 1}/${this.suggestions.length}`)
          .fontSize(14)
          .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          .fontWeight(FontWeight.Normal)

        Text('确认记账')
          .fontSize(18)
          .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          .fontWeight(FontWeight.Bold)
      }
      .alignItems(FlexAlign.Center)
      .width('100%')
      .margin({ bottom: 20 })

      // Suggestion info
      Column({ space: 16 }) {
        // 金额
        Column() {
          Text('金额')
            .fontSize(12)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
          Text(this.formatAmount(this.currentItem.amount, this.currentItem.type))
            .fontSize(28)
            .fontColor(this.currentItem.type === 'income' ? '#10B981' : '#EF4444')
            .fontWeight(FontWeight.Bold)
        }

        // 分类选择
        Column() {
          Text('分类')
            .fontSize(12)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
          Select({
            value: this.currentItem.category,
            options: this.getCategories()
          })
            .selectedColor(this.darkMode ? '#3B82F6' : '#60A5FA')
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            .showDefaultIcon(true)
            .backgroundColor('transparent')
            .onSelect((idx: number, value: string) => {
              this.updateField('category', value);
            })
        }

        // 类型切换
        Column() {
          Text('类型')
            .fontSize(12)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
          Row({ space: 12 }) {
            Button({ type: ButtonType.Normal }) {
              Text('收入')
                .fontColor(this.currentItem.type === 'income'
                  ? '#FFFFFF'
                  : (this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT))
                .fontSize(14)
            }
            .onClick(() => this.updateField('type', 'income'))
            .backgroundColor(this.currentItem.type === 'income'
              ? '#10B981'
              : (this.darkMode ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.05)'))
            .borderRadius(8)
            .width(80)
            .height(36);

            Button({ type: ButtonType.Normal }) {
              Text('支出')
                .fontColor(this.currentItem.type === 'expense'
                  ? '#FFFFFF'
                  : (this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT))
                .fontSize(14)
            }
            .onClick(() => this.updateField('type', 'expense'))
            .backgroundColor(this.currentItem.type === 'expense'
              ? '#EF4444'
              : (this.darkMode ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.05)'))
            .borderRadius(8)
            .width(80)
            .height(36);
          }
        }

        // 备注
        Column() {
          Text('备注')
            .fontSize(12)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
          TextInput({
            text: this.currentItem.note,
            placeholder: '输入备注...'
          })
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            .placeholderColor(this.darkMode ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
            .backgroundColor(this.darkMode ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.2)')
            .borderColor(this.darkMode ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
            .borderWidth(1)
            .borderRadius(8)
            .height(36)
            .onChange((value: string) => {
              this.updateField('note', value);
            })
        }

        // 商户
        Column() {
          Text('商户')
            .fontSize(12)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
          TextInput({
            text: this.currentItem.merchant || '',
            placeholder: '商户名称...'
          })
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            .placeholderColor(this.darkMode ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
            .backgroundColor(this.darkMode ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.2)')
            .borderColor(this.darkMode ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
            .borderWidth(1)
            .borderRadius(8)
            .height(36)
            .onChange((value: string) => {
              this.updateField('merchant', value || undefined);
            })
        }

        // 置信度显示
        Column() {
          Text(`置信度: ${(this.currentItem.confidence * 100).toFixed(0)}%`)
            .fontSize(12)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
        }
      }
      .width('100%')
      .padding(16)
      .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
      .borderColor(this.darkMode ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
      .borderWidth(1)
      .borderRadius(16)

      // 导航按钮
      Row({ space: 20 }) {
        Button({ type: ButtonType.Normal }) {
          Text('上一条')
            .fontSize(14)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT);
        }
        .onClick(() => {
          if (this.current > 0) {
            this.current = this.current - 1;
          } else {
            this.closeDialog();
          }
        })
        .backgroundColor(this.darkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.03)')
        .borderColor(this.darkMode ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
        .borderRadius(10)
        .width(100)
        .height(40);

        Button({ type: ButtonType.Normal }) {
          Text('下一条')
            .fontSize(14)
            .fontColor(this.darkMode ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT);
        }
        .onClick(() => {
          if (this.current < this.suggestions.length - 1) {
            this.current = this.current + 1;
          }
        })
        .backgroundColor(this.darkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.03)')
        .borderColor(this.darkMode ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
        .borderRadius(10)
        .width(100)
        .height(40);
      }
      .margin({ top: 20 })
    }
    .padding(24)
    .backgroundBlurStyle(GlassTokens.BLUR_MODAL)
    .borderColor(this.darkMode ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
    .borderWidth(1)
    .borderRadius(24)
    .boxShadow(GlassTokens.SHADOW)
    .onTouch(
      (event: TouchEvent) => {
        event.stopPropagation();
      }
    )
  }
}