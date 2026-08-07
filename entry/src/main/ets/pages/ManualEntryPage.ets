import { common } from '@kit.AbilityKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';
import { CategoryPicker } from '../components/CategoryPicker';
import { BookkeepingRecord, RecordStatus, RecordSource, EXPENSE_CATEGORIES, INCOME_CATEGORIES } from '../model/RecordModel';
import { recordDb } from '../utils/RecordDatabase';

@Entry
@Component
struct ManualEntryPage {
  @StorageProp('darkMode') dark: boolean = false;
  @State amountText: string = '';
  @State type: 'expense' | 'income' = 'expense';
  @State category: string = '餐饮';
  @State note: string = '';
  @State merchant: string = '';
  @State dateText: string = '';
  @State busy: boolean = false;
  @State statusMsg: string = '';

  private getExpenseCategories(): string[] {
    return EXPENSE_CATEGORIES.map((c): string => c.name);
  }

  private getIncomeCategories(): string[] {
    return INCOME_CATEGORIES.map((c): string => c.name);
  }

  private getCategories(): string[] {
    return this.type === 'income' ? this.getIncomeCategories() : this.getExpenseCategories();
  }

  private switchType(next: 'expense' | 'income'): void {
    if (this.type === next) {
      return;
    }
    const cats = this.getCategories();
    const first = cats.length > 0 ? cats[0] : this.category;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.type = next;
      this.category = first;
    });
  }

  private pickCategory(name: string): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.category = name;
    });
  }

  private parseAmount(): number | null {
    const s = this.amountText.trim()
      .replace(/，/g, ',')
      .replace(/－/g, '-')
      .replace(/．/g, '.')
      .replace(/[０-９]/g, m => String.fromCharCode(m.charCodeAt(0) - 0xFEE0));
    const n = parseFloat(s.replace(/[^0-9.\-]/g, ''));
    if (isNaN(n) || n <= 0 || n > 99999) {
      return null;
    }
    return n;
  }

  private parseDate(): number {
    const s = this.dateText.trim().replace(/年/g, '-').replace(/月/g, '-').replace(/日/g, '').replace(/\//g, '-');
    if (!s) {
      return Date.now();
    }
    const parts = s.split('-');
    if (parts.length >= 3) {
      const y = parseInt(parts[0]);
      const m = parseInt(parts[1]);
      const d = parseInt(parts[2]);
      if (!isNaN(y) && !isNaN(m) && !isNaN(d)) {
        const t = new Date(y, m - 1, d).getTime();
        if (!isNaN(t)) {
          return t;
        }
      }
    }
    return Date.now();
  }

  private formatDate(ts: number): string {
    const d = new Date(ts);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  aboutToAppear(): void {
    this.dateText = this.formatDate(Date.now());
  }

  private async onSave(): Promise<void> {
    const amount = this.parseAmount();
    if (amount === null) {
      this.statusMsg = '请输入有效金额（0-99999）';
      return;
    }
    this.busy = true;
    this.statusMsg = '保存中…';
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx) {
        await recordDb.init(ctx as common.Context);
      }
      const ts = this.parseDate();
      const record: BookkeepingRecord = {
        id: null,
        amount: this.type === 'income' ? amount : -amount,
        type: this.type,
        category: this.category,
        note: this.note.trim(),
        merchant: this.merchant.trim() || null,
        timestamp: ts,
        dateStr: this.formatDate(ts),
        confidence: 1.0,
        source: 'pdf-text' as RecordSource,
        status: RecordStatus.CONFIRMED,
        createdAt: Date.now()
      };
      await recordDb.insert(record);
      const tick = AppStorage.get<number>('recordRefreshTick') ?? 0;
      AppStorage.setOrCreate('recordRefreshTick', tick + 1);
      this.statusMsg = '✓ 已保存';
      setTimeout(() => {
        this.getUIContext().getRouter().back();
      }, 900);
    } catch (err) {
      console.error('manual save failed', JSON.stringify(err));
      this.statusMsg = '保存失败';
    } finally {
      this.busy = false;
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [this.dark ? '#1b1b22' : '#dfe7ff', 0],
            [this.dark ? '#2a2440' : '#f6e9ff', 1]
          ]
        })

      Column() {
        GlassToolbar({ dark: this.dark }) {
          Row() {
            Blank()
            Text('手动记账')
              .fontSize(16)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            Blank()
          }
          .width('100%')
        }

        Column({ space: 16 }) {
          // 类型切换（玻璃胶囊分段）
          Row() {
            Row() {
              Text('支出')
                .fontColor(this.type === 'expense' ? '#FFFFFF' : (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT))
                .fontSize(15)
                .fontWeight(this.type === 'expense' ? FontWeight.Medium : FontWeight.Normal)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.type === 'expense' ? '#EF4444' : Color.Transparent)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
            .onClick(() => this.switchType('expense'))

            Row() {
              Text('收入')
                .fontColor(this.type === 'income' ? '#FFFFFF' : (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT))
                .fontSize(15)
                .fontWeight(this.type === 'income' ? FontWeight.Medium : FontWeight.Normal)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.type === 'income' ? '#10B981' : Color.Transparent)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
            .onClick(() => this.switchType('income'))
          }
          .width('100%')
          .height(48)
          .padding(2)
          .borderRadius(24)
          .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
          .backgroundColor(this.dark ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.35)')
          .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
          .shadow(GlassTokens.SHADOW)

          // 金额（玻璃卡）
          Column({ space: 6 }) {
            Text('金额')
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
            TextInput({ text: this.amountText, placeholder: '如 1280.00' })
              .type(InputType.NUMBER_DECIMAL)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .placeholderColor(this.dark ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
              .backgroundColor(this.dark ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.5)')
              .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
              .borderWidth(1)
              .borderRadius(12)
              .height(44)
              .onChange((v: string) => {
                this.amountText = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .borderRadius(16)
          .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
          .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
          .shadow(GlassTokens.SHADOW)

          // 分类（玻璃卡 + 预选胶囊）
          Column({ space: 10 }) {
            Text('分类')
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
            CategoryPicker({
              categories: this.getCategories(),
              selected: this.category,
              dark: this.dark,
              onPick: (n: string): void => {
                this.pickCategory(n);
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .borderRadius(20)
          .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
          .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
          .shadow(GlassTokens.SHADOW)

          // 备注
          Column({ space: 6 }) {
            Text('备注')
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
            TextInput({ text: this.note, placeholder: '消费说明（选填）' })
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .placeholderColor(this.dark ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
              .backgroundColor(this.dark ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.5)')
              .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
              .borderWidth(1)
              .borderRadius(12)
              .height(44)
              .onChange((v: string) => {
                this.note = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .borderRadius(16)
          .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
          .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
          .shadow(GlassTokens.SHADOW)

          // 商户
          Column({ space: 6 }) {
            Text('商户')
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
            TextInput({ text: this.merchant, placeholder: '商户名称（选填）' })
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .placeholderColor(this.dark ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
              .backgroundColor(this.dark ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.5)')
              .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
              .borderWidth(1)
              .borderRadius(12)
              .height(44)
              .onChange((v: string) => {
                this.merchant = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .borderRadius(16)
          .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
          .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
          .shadow(GlassTokens.SHADOW)

          // 日期
          Column({ space: 6 }) {
            Text('日期（默认今天）')
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
            TextInput({ text: this.dateText, placeholder: '2026-08-07' })
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .placeholderColor(this.dark ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
              .backgroundColor(this.dark ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.5)')
              .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
              .borderWidth(1)
              .borderRadius(12)
              .height(44)
              .onChange((v: string) => {
                this.dateText = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .borderRadius(16)
          .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
          .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
          .shadow(GlassTokens.SHADOW)

          if (this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(13)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .textAlign(TextAlign.Center)
              .width('100%')
          }

          GlassButton({
            label: this.busy ? '保存中…' : '保存',
            dark: this.dark,
            heightVp: 48,
            fontSize: 16,
            onClickHandler: () => this.onSave()
          })
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
    .backgroundColor(Color.Transparent)
  }
}
