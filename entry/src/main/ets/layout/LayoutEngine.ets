// 排版引擎：OCR 页面 → 结构化版面（段落/表格/图片），纯函数无副作用
import { OCRPage } from '../ocr/OCRTypes';
import { ParagraphReconstructor, Paragraph } from './ParagraphReconstructor';
import { FontMatcher, FontMatchResult } from './FontMatcher';

export interface LayoutImage {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface LayoutTable {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rows: number;
  cols: number;
  cells: string[][];
}

export interface LayoutResult {
  paragraphs: Paragraph[];
  tables: LayoutTable[];
  images: LayoutImage[];
  pageWidth: number;
  pageHeight: number;
}

export interface FontMapEntry {
  blockId: string;
  match: FontMatchResult;
}

export class LayoutEngine {
  static reconstructLayout(page: OCRPage): LayoutResult {
    const paragraphs = ParagraphReconstructor.reconstruct(page.blocks);
    const tables = LayoutEngine.detectTables(page);
    const images = LayoutEngine.detectImages(page);
    return {
      paragraphs: paragraphs,
      tables: tables,
      images: images,
      pageWidth: page.width,
      pageHeight: page.height
    };
  }

  static matchFonts(page: OCRPage): FontMapEntry[] {
    const map: FontMapEntry[] = [];
    for (const b of page.blocks) {
      map.push({ blockId: b.id, match: FontMatcher.matchFont(b.fontName) });
    }
    return map;
  }

  private static detectTables(page: OCRPage): LayoutTable[] {
    const blocks = page.blocks;
    if (blocks.length === 0) {
      return [];
    }
    const rows: TextRow[] = [];
    for (const b of blocks) {
      const row = rows.find((r) => Math.abs(r.y - b.y) < 8);
      if (row) {
        row.blocks.push(b);
      } else {
        rows.push({ y: b.y, blocks: [b] });
      }
    }
    if (rows.length < 3) {
      return [];
    }
    const colCounts = rows.map((r) => r.blocks.length);
    const maxCols = Math.max(...colCounts);
    if (maxCols < 2) {
      return [];
    }
    const minX = Math.min(...blocks.map((b) => b.x));
    const minY = Math.min(...blocks.map((b) => b.y));
    const maxX = Math.max(...blocks.map((b) => b.x + b.width));
    const maxY = Math.max(...blocks.map((b) => b.y + b.height));
    rows.sort((a, b) => a.y - b.y);
    const cells: string[][] = [];
    for (const r of rows) {
      r.blocks.sort((a, b) => a.x - b.x);
      const line: string[] = [];
      for (const b of r.blocks) {
        line.push(b.text);
      }
      cells.push(line);
    }
    return [{
      id: 't0',
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      rows: rows.length,
      cols: maxCols,
      cells: cells
    }];
  }

  private static detectImages(page: OCRPage): LayoutImage[] {
    const images: LayoutImage[] = [];
    const blocks = page.blocks;
    if (blocks.length < 2) {
      return [];
    }
    const total = blocks.reduce((s, b) => s + b.width * b.height, 0);
    const avg = total / blocks.length;
    for (const b of blocks) {
      const area = b.width * b.height;
      if (area > avg * 6 && b.width > 80 && b.height > 80) {
        images.push({
          id: 'img_' + b.id,
          x: b.x,
          y: b.y,
          width: b.width,
          height: b.height
        });
      }
    }
    return images;
  }
}

interface TextRow {
  y: number;
  blocks: Array<{ id: string; text: string; x: number; y: number; width: number; height: number }>;
}
