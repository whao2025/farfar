import { OCRResult, OCROptions, OCRProgress } from './OCRTypes';
import { CoreVisionOCR } from './CoreVisionOCR';

export interface OCRService {
  recognize(pdfPath: string, options?: OCROptions, onProgress?: (p: OCRProgress) => void): Promise<OCRResult>;
}

export function createOCRService(): OCRService {
  return new CoreVisionOCR();
}
