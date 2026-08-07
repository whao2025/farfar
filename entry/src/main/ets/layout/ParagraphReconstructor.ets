// 段落重构：OCR 文本块 → 结构化段落（同行/跨行合并、边界检测、阅读序）
import { TextBlock } from '../ocr/OCRTypes';

export interface Paragraph {
  id: string;
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
  fontSize: number;
  fontName?: string;
  confidence: number;
  blockIds: string[];
}

const MIN_OVERLAP_RATIO = 0.3;

export class ParagraphReconstructor {
  static reconstruct(blocks: TextBlock[]): Paragraph[] {
    if (blocks.length === 0) {
      return [];
    }
    const sorted = blocks.slice();
    sorted.sort((a, b) => {
      const ay = Math.round(a.y);
      const by = Math.round(b.y);
      if (ay !== by) {
        return ay - by;
      }
      return a.x - b.x;
    });
    const rows: TextBlock[][] = [];
    let cur: TextBlock[] = [];
    let curBottom = -1;
    for (const b of sorted) {
      if (cur.length === 0) {
        cur.push(b);
        curBottom = b.y + b.height;
        continue;
      }
      const head = cur[0];
      const lineH = head.height > 0 ? head.height : 12;
      const overlap = this.xOverlap(b, head);
      if (b.y <= curBottom + lineH * 0.5 && overlap >= MIN_OVERLAP_RATIO) {
        cur.push(b);
        curBottom = Math.max(curBottom, b.y + b.height);
      } else {
        rows.push(cur);
        cur = [b];
        curBottom = b.y + b.height;
      }
    }
    if (cur.length > 0) {
      rows.push(cur);
    }
    const paragraphs: Paragraph[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      row.sort((a, b) => a.x - b.x);
      let text = '';
      let lastRight = -1;
      let lastSize = 0;
      for (let j = 0; j < row.length; j++) {
        const b = row[j];
        const size = b.fontSize > 0 ? b.fontSize : 12;
        if (lastRight >= 0) {
          const gap = b.x - lastRight;
          const spaceW = Math.max(size, lastSize) * 0.35;
          if (gap > 1 && gap > spaceW * 0.5) {
            text += ' ';
          }
        }
        text += b.text;
        lastRight = b.x + b.width;
        lastSize = size;
      }
      const first = row[0];
      const minX = Math.min(...row.map((b) => b.x));
      const minY = Math.min(...row.map((b) => b.y));
      const maxX = Math.max(...row.map((b) => b.x + b.width));
      const maxY = Math.max(...row.map((b) => b.y + b.height));
      const confSum = row.reduce((s, b) => s + b.confidence, 0);
      paragraphs.push({
        id: 'p' + i,
        text: text.trim(),
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY,
        fontSize: first.fontSize,
        fontName: first.fontName,
        confidence: row.length > 0 ? confSum / row.length : 0,
        blockIds: row.map((b) => b.id)
      });
    }
    return paragraphs;
  }

  static xOverlap(a: TextBlock, b: TextBlock): number {
    const left = Math.max(a.x, b.x);
    const right = Math.min(a.x + a.width, b.x + b.width);
    const overlap = right - left;
    if (overlap <= 0) {
      return 0;
    }
    const minW = Math.min(a.width, b.width);
    return minW > 0 ? overlap / minW : 0;
  }
}
