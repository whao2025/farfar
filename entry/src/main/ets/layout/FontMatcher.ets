// 字体匹配引擎：OCR 字体信息 → 系统字体（精确/模糊/视觉/回退）
export interface FontMatchResult {
  fontName: string;
  fontPath?: string;
  similarity: number;
  fallback: boolean;
}

export interface FontCandidate {
  name: string;
  serif: boolean;
  bold: boolean;
  mono: boolean;
  cjk: boolean;
}

const SYSTEM_FONTS: FontCandidate[] = [
  { name: 'HarmonyOS Sans', serif: false, bold: false, mono: false, cjk: true },
  { name: 'HarmonyOS Sans SC', serif: false, bold: false, mono: false, cjk: true },
  { name: 'HarmonyOS Sans Medium', serif: false, bold: true, mono: false, cjk: true },
  { name: 'HarmonyOS Sans Bold', serif: false, bold: true, mono: false, cjk: true },
  { name: 'Times New Roman', serif: true, bold: false, mono: false, cjk: false },
  { name: 'Courier New', serif: false, bold: false, mono: true, cjk: false },
  { name: 'Arial', serif: false, bold: false, mono: false, cjk: false }
];

const FALLBACK_NAME = 'HarmonyOS Sans';
const CACHE_KEY_MAX = 64;

class FontCache {
  private map: Map<string, FontMatchResult> = new Map();

  get(key: string): FontMatchResult | undefined {
    return this.map.get(key);
  }

  put(key: string, value: FontMatchResult): void {
    if (this.map.size >= CACHE_KEY_MAX) {
      this.map.clear();
    }
    this.map.set(key, value);
  }
}

const cache = new FontCache();

export class FontMatcher {
  static matchFont(ocrFontName?: string): FontMatchResult {
    const key = ocrFontName ?? FALLBACK_NAME;
    const hit = cache.get(key);
    if (hit) {
      return hit;
    }
    const result = FontMatcher.matchInternal(ocrFontName);
    cache.put(key, result);
    return result;
  }

  private static matchInternal(ocrFontName?: string): FontMatchResult {
    if (!ocrFontName || ocrFontName.trim().length === 0) {
      return FontMatcher.fallback();
    }
    const name = ocrFontName.trim();
    const exact = SYSTEM_FONTS.find((f) => f.name === name);
    if (exact) {
      return { fontName: exact.name, similarity: 1, fallback: false };
    }
    const fuzzy = FontMatcher.matchFuzzy(name);
    if (fuzzy) {
      return fuzzy;
    }
    const visual = FontMatcher.matchVisual(name);
    if (visual) {
      return visual;
    }
    return FontMatcher.fallback();
  }

  private static matchFuzzy(ocrName: string): FontMatchResult | undefined {
    let best: FontCandidate | undefined;
    let bestSim = 0;
    const lower = ocrName.toLowerCase();
    for (const f of SYSTEM_FONTS) {
      const sim = FontMatcher.levenshteinRatio(lower, f.name.toLowerCase());
      if (sim > bestSim) {
        bestSim = sim;
        best = f;
      }
    }
    if (best && bestSim >= 0.6) {
      return { fontName: best.name, similarity: bestSim, fallback: false };
    }
    return undefined;
  }

  private static matchVisual(ocrName: string): FontMatchResult | undefined {
    const lower = ocrName.toLowerCase();
    const wantSerif = lower.includes('times') || lower.includes('serif') || lower.includes('song');
    const wantMono = lower.includes('courier') || lower.includes('mono') || lower.includes('consolas');
    const wantBold = lower.includes('bold') || lower.includes('medium') || lower.includes('heavy');
    for (const f of SYSTEM_FONTS) {
      if (wantMono && f.mono) {
        return { fontName: f.name, similarity: 0.8, fallback: false };
      }
      if (wantSerif && f.serif) {
        return { fontName: f.name, similarity: 0.8, fallback: false };
      }
      if (wantBold && f.bold) {
        return { fontName: f.name, similarity: 0.8, fallback: false };
      }
    }
    return undefined;
  }

  static levenshteinRatio(a: string, b: string): number {
    if (a === b) {
      return 1;
    }
    if (a.length === 0 || b.length === 0) {
      return 0;
    }
    const m = a.length;
    const n = b.length;
    const dp: number[][] = new Array(m + 1);
    for (let i = 0; i <= m; i++) {
      dp[i] = new Array(n + 1);
      dp[i][0] = i;
    }
    for (let j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
        const del = dp[i - 1][j] + 1;
        const ins = dp[i][j - 1] + 1;
        const sub = dp[i - 1][j - 1] + cost;
        dp[i][j] = Math.min(del, ins, sub);
      }
    }
    const dist = dp[m][n];
    return 1 - dist / Math.max(m, n);
  }

  private static fallback(): FontMatchResult {
    return { fontName: FALLBACK_NAME, similarity: 0, fallback: true };
  }
}
