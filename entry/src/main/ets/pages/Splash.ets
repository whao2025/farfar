import { router, AnimatorOptions, AnimatorResult } from '@kit.ArkUI';

const BG: string = '#0a1429';
const DURATION: number = 1800;
const FADE: number = 300;
const STAY: number = 450;
const MAX_FRACTION: number = 0.7;
const SEG: number = 0.13;
const OVERLAP: number = 0.05;
const LETTERS: string[] = ['f', 'r', 'e', 'e', 'p', 'd', 'f'];
const GRAD_COLORS: string[] = ['#5B8CFF', '#7A74FF', '#9B5BFF'];

@Entry
@Component
struct Splash {
  @State private splashOpacity: number = 1;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private animator: AnimatorResult | undefined = undefined;
  private animDone: boolean = false;
  private stayTimer: number = -1;
  private canvasW: number = 0;
  private canvasH: number = 0;
  private totalW: number = 0;
  private wordLeft: number = 0;
  private baseY: number = 0;
  private letterLeft: number[] = [];
  private letterW: number[] = [];
  private grad: CanvasGradient | undefined = undefined;
  private renderFailed: boolean = false;

  aboutToDisappear(): void {
    this.renderFailed = true;
    if (this.animator !== undefined) {
      this.animator.cancel();
      this.animator = undefined;
    }
    if (this.stayTimer >= 0) {
      clearTimeout(this.stayTimer);
      this.stayTimer = -1;
    }
  }

  build() {
    Column() {
      Canvas(this.ctx)
        .width('90%')
        .height('25%')
        .onReady(() => {
          this.init();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(BG)
    .opacity(this.splashOpacity)
  }

  private init(): void {
    try {
      this.canvasW = this.ctx.width > 0 ? this.ctx.width : 340;
      this.canvasH = this.ctx.height > 0 ? this.ctx.height : 120;
      if (!this.isFiniteNum(this.canvasW) || !this.isFiniteNum(this.canvasH) || this.canvasW <= 0 || this.canvasH <= 0) {
        this.fallbackToTextSplash();
        return;
      }
      this.ctx.font = 'bold 88vp sans-serif';
      this.ctx.textBaseline = 'middle';
      this.ctx.textAlign = 'left';
      let totalW = this.ctx.measureText('freepdf').width;
      const maxW = this.canvasW * MAX_FRACTION;
      const maxH = this.canvasH * 0.9;
      if (totalW > maxW || 88 * 1.2 > maxH) {
        const scale = Math.min(maxW / totalW, maxH / (88 * 1.2));
        const fontSize = Math.max(30, Math.floor(88 * scale));
        this.ctx.font = 'bold ' + fontSize.toString() + 'vp sans-serif';
        totalW = this.ctx.measureText('freepdf').width;
      }
      this.totalW = totalW;
      this.wordLeft = (this.canvasW - totalW) / 2;
      this.baseY = this.canvasH / 2;
      this.letterLeft = [];
      this.letterW = [];
      const count = LETTERS.length;
      for (let i = 0; i < count; i++) {
        this.letterLeft.push(this.wordLeft + this.ctx.measureText(LETTERS.slice(0, i).join('')).width);
        this.letterW.push(this.ctx.measureText(LETTERS[i]).width);
      }
      this.grad = this.ctx.createLinearGradient(this.wordLeft, 0, this.wordLeft + totalW, 0);
      const stopCount = GRAD_COLORS.length;
      for (let i = 0; i < stopCount; i++) {
        this.grad.addColorStop(i / (stopCount - 1), GRAD_COLORS[i]);
      }
      this.drawFrame(0);
      this.animDone = false;
      this.setupAnimator();
    } catch (e) {
      this.fallbackToTextSplash();
    }
  }

  private setupAnimator(): void {
    try {
      const opts: AnimatorOptions = {
        duration: DURATION,
        easing: 'linear',
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: 1,
        begin: 0,
        end: 1
      };
      this.animator = this.getUIContext().createAnimator(opts);
      this.animator.onFrame = (progress: number): void => {
        if (this.renderFailed || this.animDone) {
          return;
        }
        try {
          this.drawFrame(progress);
        } catch (e) {
          this.fallbackToTextSplash();
        }
      };
      this.animator.onFinish = (): void => {
        if (this.animDone || this.renderFailed) {
          return;
        }
        this.animDone = true;
        this.drawFrame(1);
        this.startExit();
      };
      this.animator.play();
    } catch (e) {
      this.renderFailed = true;
      this.drawFrame(1);
      this.startExit();
    }
  }

  private startExit(): void {
    if (this.stayTimer >= 0) {
      return;
    }
    this.stayTimer = setTimeout(() => {
      this.stayTimer = -1;
      animateTo({ duration: FADE, curve: Curve.EaseInOut }, () => {
        this.splashOpacity = 0;
      });
      setTimeout(() => {
        router.replaceUrl({ url: 'pages/Home' });
      }, FADE);
    }, STAY);
  }

  private drawFrame(p: number): void {
    this.ctx.clearRect(0, 0, this.canvasW, this.canvasH);
    const grad = this.grad;
    if (grad === undefined) {
      return;
    }
    const pp = Math.max(0, Math.min(1, p));
    const count = LETTERS.length;
    this.ctx.save();
    for (let i = 0; i < count; i++) {
      const start = i * (SEG - OVERLAP);
      if (pp < start) {
        break;
      }
      const local = Math.min(1, (pp - start) / SEG);
      const e = 1 - Math.pow(1 - local, 3);
      const w = this.letterW[i] * e;
      if (w <= 0.5) {
        continue;
      }
      this.ctx.save();
      this.ctx.beginPath();
      this.ctx.rect(this.letterLeft[i], 0, w, this.canvasH);
      this.ctx.clip();
      this.ctx.fillStyle = grad;
      this.ctx.fillText('freepdf', this.wordLeft, this.baseY);
      this.ctx.restore();
    }
    this.ctx.restore();
  }

  private isFiniteNum(v: number): boolean {
    return Number.isFinite(v);
  }

  private fallbackToTextSplash(): void {
    if (this.renderFailed) {
      return;
    }
    this.renderFailed = true;
    if (this.animator !== undefined) {
      this.animator.cancel();
      this.animator = undefined;
    }
    if (this.stayTimer >= 0) {
      clearTimeout(this.stayTimer);
      this.stayTimer = -1;
    }
    this.animDone = true;
    setTimeout(() => {
      router.replaceUrl({ url: 'pages/Home' });
    }, 1200);
  }
}
