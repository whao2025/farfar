export class Breakpoint {
  static readonly SM: number = 600;
  static readonly MD: number = 840;

  static calc(width: number): string {
    if (width >= Breakpoint.MD) {
      return 'lg';
    }
    if (width >= Breakpoint.SM) {
      return 'md';
    }
    return 'sm';
  }

  static calcFromPx(widthPx: number, density: number): string {
    const widthVp = widthPx / density;
    return Breakpoint.calc(widthVp);
  }
}
