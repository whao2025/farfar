// OCR 领域类型（与 UI/PDF 层解耦，纯数据，无 @kit 依赖）
export interface TextLine {
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface TextBlock {
  id: string;
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
  fontSize: number;
  fontName?: string;
  confidence: number;
  lines: TextLine[];
}

export interface OCRPage {
  index: number;
  width: number;
  height: number;
  blocks: TextBlock[];
}

export interface OCRResult {
  pages: OCRPage[];
}

export interface OCRProgress {
  pageIndex: number;
  total: number;
  percent: number;
}

export interface OCROptions {
  startPage?: number;
  endPage?: number;
}
