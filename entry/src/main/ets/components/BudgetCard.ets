import { GlassTokens } from '../theme/GlassTokens';
import { budgetPrefs } from '../utils/BudgetPreferences';
import { common } from '@kit.AbilityKit';
import curves from '@ohos.curves';

@Component
export struct BudgetCard {
  @Prop monthlyBudget: number = 0;
  @Prop dailyBudget: number = 0;
  @Prop weeklyBudget: number = 0;
  @Prop actualDaily: number = 0;
  @Prop actualWeekly: number = 0;
  @Prop actualMonthly: number = 0;
  @Prop dark: boolean = false;
  onBudgetSaved: () => void = () => {};
  @State editingBudget: boolean = false;
  @State budgetInput: string = '';

  private startEditBudget(): void {
    this.budgetInput = this.monthlyBudget > 0 ? String(this.monthlyBudget) : '';
    this.editingBudget = true;
  }

  private async ensurePrefs(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx) {
        await budgetPrefs.init(ctx as common.Context);
      }
    } catch (err) {
      console.error('prefs init in budget card failed:', err);
    }
  }

  private async saveBudget(): Promise<void> {
    const s = this.budgetInput.trim();
    const n = parseFloat(s.replace(/[^0-9.]/g, ''));
    this.editingBudget = false;
    this.budgetInput = '';
    if (isNaN(n) || n <= 0) {
      return;
    }
    try {
      await this.ensurePrefs();
      await budgetPrefs.setMonthlyBudget(Math.round(n));
      this.onBudgetSaved();
    } catch (err) {
      console.error('save budget failed:', err);
    }
  }

  private getMonthlyPct(): number {
    if (this.monthlyBudget <= 0) return 0;
    const spent = Math.abs(this.actualMonthly);
    return Math.min((spent / this.monthlyBudget) * 100, 100);
  }

  private getDailyPct(): number {
    if (this.dailyBudget <= 0) return 0;
    const spent = Math.abs(this.actualDaily);
    return Math.min((spent / this.dailyBudget) * 100, 100);
  }

  private getWeeklyPct(): number {
    if (this.weeklyBudget <= 0) return 0;
    const spent = Math.abs(this.actualWeekly);
    return Math.min((spent / this.weeklyBudget) * 100, 100);
  }

  private paceTone(): string {
    const b = this.monthlyBudget;
    const spent = Math.abs(this.actualMonthly);
    if (b <= 0) return 'neutral';
    if (spent / b >= 1) return 'danger';
    const d = new Date();
    const day = d.getDate();
    const totalDays = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    const pace = (spent / b) * 100 - (day / totalDays) * 100;
    if (pace > 10) return 'warn';
    if (pace < -10) return 'ok';
    return 'neutral';
  }

  private paceColor(tone: string): string {
    if (tone === 'danger') return GlassTokens.DANGER;
    if (tone === 'warn') return GlassTokens.WARN;
    if (tone === 'ok') return GlassTokens.SUCCESS;
    return this.dark ? GlassTokens.ACCENT_SKY : GlassTokens.ACCENT;
  }

  private daysLeft(): number {
    const d = new Date();
    const totalDays = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    return Math.max(1, totalDays - d.getDate() + 1);
  }

  private dailyAllowance(): number {
    const b = this.monthlyBudget;
    if (b <= 0) return 0;
    const rest = b - Math.abs(this.actualMonthly);
    return Math.max(0, rest / this.daysLeft());
  }

  private formatMoney(n: number): string {
    if (n >= 10000) return (n / 10000).toFixed(1) + 'w';
    return Math.round(n).toString();
  }

  @Builder
  mainBar(tone: string) {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(14)
        .borderRadius(7)
        .backgroundColor(this.dark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')

      Row()
        .width(this.getMonthlyPct() + '%')
        .height(14)
        .borderRadius(7)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [[this.paceColor(tone), 0], [GlassTokens.ACCENT, 1]]
        })
        .animation({ duration: 600, curve: curves.springMotion(0.6, 0.9, 0) })
    }
    .width('100%')
  }

  @Builder
  miniBar(label: string, pct: number, color: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(11)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        .width(22)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.dark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')

        Row()
          .width(pct + '%')
          .height(8)
          .borderRadius(4)
          .backgroundColor(color)
          .animation({ duration: 600, curve: curves.springMotion(0.6, 0.9, 0) })
      }
      .layoutWeight(1)

      Text(pct >= 100 ? '超支' : Math.round(pct) + '%')
        .fontSize(11)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
    }
    .width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('本月预算')
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
        Blank()
      }
      .width('100%')

      if (this.monthlyBudget <= 0) {
        Row({ space: 8 }) {
          Text('未设置预算')
            .fontSize(13)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Text('点击设置月预算')
            .fontSize(12)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK + '60' : GlassTokens.TEXT_LIGHT + '60')
          Blank()
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
        .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
        .onClick(() => this.startEditBudget())
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      } else {
        Column({ space: 8 }) {
          this.mainBar(this.paceTone())

          Row() {
            Text('已用 ¥' + this.formatMoney(Math.abs(this.actualMonthly)))
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.paceColor(this.paceTone()))
            Blank()
            Text('剩余 ¥' + this.formatMoney(Math.max(0, this.monthlyBudget - Math.abs(this.actualMonthly))))
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          }
          .width('100%')
        }
        .width('100%')
        .onClick(() => this.startEditBudget())
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })

        Row({ space: 12 }) {
          Text('剩余 ' + this.daysLeft() + ' 天')
            .fontSize(11)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
          Text('今日可用 ¥' + this.formatMoney(this.dailyAllowance()))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.paceColor(this.paceTone()))
        }
        .width('100%')

        Column({ space: 8 }) {
          this.miniBar('日', this.getDailyPct(), this.dark ? GlassTokens.ACCENT_BLUE : GlassTokens.ACCENT_SKY)
          this.miniBar('周', this.getWeeklyPct(), GlassTokens.PURPLE)
        }
        .width('100%')
      }

      if (this.editingBudget) {
        Row({ space: 8 }) {
          TextInput({ text: this.budgetInput, placeholder: '月预算(元)' })
            .type(InputType.NUMBER_DECIMAL)
            .fontSize(13)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            .placeholderColor(this.dark ? GlassTokens.TEXT_DARK + '40' : GlassTokens.TEXT_LIGHT + '40')
            .backgroundColor(this.dark ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.5)')
            .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
            .borderWidth(1)
            .borderRadius(10)
            .height(36)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.budgetInput = v;
            })
          Button({ type: ButtonType.Normal }) {
            Text('保存')
              .fontSize(13)
              .fontColor('#FFFFFF')
          }
          .onClick(() => this.saveBudget())
          .backgroundColor(GlassTokens.ACCENT)
          .borderRadius(10)
          .height(36)
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(18)
    .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
    .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
    .borderWidth(1)
    .borderRadius(20)
    .shadow(GlassTokens.SHADOW)
  }
}