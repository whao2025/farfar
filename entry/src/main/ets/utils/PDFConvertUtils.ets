import { pdfService } from '@kit.PDFKit';
import { taskpool } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export async function pdfToImagesAsync(srcPath: string, outDir: string, progress: (p: number) => void): Promise<boolean> {
  const task = new taskpool.Task(runPdfToImages, srcPath, outDir);
  try {
    const ok = await taskpool.execute(task) as boolean;
    return ok;
  } catch (err) {
    const e = err as BusinessError;
    console.error('pdfToImages failed', JSON.stringify(e));
    return false;
  }
}

@Concurrent
function runPdfToImages(srcPath: string, outDir: string): boolean {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const result = doc.loadDocument(srcPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      return false;
    }
    return doc.convertToImage(outDir, pdfService.ImageFormat.PNG, (p: number) => {
      return p;
    });
  } catch (err) {
    console.error('runPdfToImages failed', JSON.stringify(err));
    return false;
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export async function imagesToPdfAsync(imagePaths: string[], outPath: string, pageWidth: number, pageHeight: number): Promise<boolean> {
  const task = new taskpool.Task(runImagesToPdf, imagePaths, outPath, pageWidth, pageHeight);
  try {
    const ok = await taskpool.execute(task) as boolean;
    return ok;
  } catch (err) {
    const e = err as BusinessError;
    console.error('imagesToPdf failed', JSON.stringify(e));
    return false;
  }
}

@Concurrent
function runImagesToPdf(imagePaths: string[], outPath: string, pageWidth: number, pageHeight: number): boolean {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const ok = doc.createDocument(pageWidth, pageHeight);
    if (!ok) {
      return false;
    }
    for (let i = 0; i < imagePaths.length; i++) {
      const page = doc.insertBlankPage(doc.getPageCount(), pageWidth, pageHeight);
      page.addImageObject(imagePaths[i], 0, 0, pageWidth, pageHeight);
    }
    return doc.saveDocument(outPath);
  } catch (err) {
    console.error('runImagesToPdf failed', JSON.stringify(err));
    return false;
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export async function listFiles(dir: string): Promise<string[]> {
  try {
    const files = await fileIo.listFile(dir);
    return files;
  } catch (err) {
    console.error('listFiles failed', JSON.stringify(err));
    return [];
  }
}
