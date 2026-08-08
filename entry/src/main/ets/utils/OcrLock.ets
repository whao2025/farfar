/**
 * OCR 全局互斥锁。
 * textRecognition 为全局单例，若多路并发 init/recognize/release 会 double-init/double-release 崩溃。
 * 所有 OCR 调用（图片/PDF/编辑页 OCR）必须包进 runOcrSession，Promise 链保证严格串行。
 */
let _ocrChain: Promise<boolean> = Promise.resolve(true);

export function runOcrSession<T>(fn: () => Promise<T>): Promise<T> {
  const run: Promise<T> = _ocrChain.then(() => fn());
  // 掐住失败，避免断链使后续调用方一直 pending
  _ocrChain = run.then(
    () => true,
    () => true
  );
  return run;
}