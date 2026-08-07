// PDF 文本回写抽象层（与具体实现解耦，接口隔离）
export interface TextEdit {
  pageIndex: number;
  blockIndex: number;
  newText: string;
  newSize: number;
}

export interface RewriteResult {
  ok: boolean;
  error?: string;
  pageCount?: number;
}

export interface PDFRewriter {
  rewrite(srcPath: string, outPath: string, edits: TextEdit[]): Promise<RewriteResult>;
}
