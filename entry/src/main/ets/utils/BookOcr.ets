import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { runOcrSession } from './OcrLock';

const MAX_SELECT = 9;
const UPSCALE = 2;

/**
 * 图库选图记账的 OCR 工具。
 * 统一走 runOcrSession 串行互斥，避免 textRecognition 全局单例 double-init/release 崩溃。
 */
export async function pickImagesToSandbox(context: common.Context, max: number = MAX_SELECT): Promise<string[]> {
  const picker = new photoAccessHelper.PhotoViewPicker();
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = max;
  options.isPhotoTakingSupported = true;
  let result: photoAccessHelper.PhotoSelectResult;
  try {
    result = await picker.select(options);
  } catch (err) {
    console.warn('pick images canceled or failed', JSON.stringify(err));
    return [];
  }
  if (!result.photoUris || result.photoUris.length === 0) {
    return [];
  }
  const paths: string[] = [];
  for (let i = 0; i < result.photoUris.length; i++) {
    const uri = result.photoUris[i];
    const sandboxPath = context.filesDir + '/book_img_' + Date.now() + '_' + i + '.jpg';
    let srcFd: number = 0;
    let dstFd: number = 0;
    try {
      const stat = await fileIo.stat(uri);
      const buf = new ArrayBuffer(stat.size);
      const src = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      srcFd = src.fd;
      await fileIo.read(srcFd, buf);
      const dst = await fileIo.open(sandboxPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      dstFd = dst.fd;
      await fileIo.write(dstFd, buf);
      paths.push(sandboxPath);
    } catch (err) {
      console.error('copy img failed', JSON.stringify(err));
    } finally {
      if (srcFd !== 0) {
        try {
          await fileIo.close(srcFd);
        } catch (err) {
          console.warn('close src fd failed', JSON.stringify(err));
        }
      }
      if (dstFd !== 0) {
        try {
          await fileIo.close(dstFd);
        } catch (err) {
          console.warn('close dst fd failed', JSON.stringify(err));
        }
      }
    }
  }
  return paths;
}

/**
 * 对一组图片做 OCR，返回合并文本。
 * 预处理：放大 2 倍后识别；否则回退原图识别；两次结果取并集（行去重）。
 */
export async function ocrImagesToText(paths: string[]): Promise<string> {
  if (paths.length === 0) {
    return '';
  }
  return runOcrSession(async () => {
    let all: string = '';
    for (let i = 0; i < paths.length; i++) {
      try {
        const text = await recognizeImageWithPreprocess(paths[i], i + 1);
        if (text.trim().length > 0) {
          if (all.length > 0) {
            all += '\n--- 第 ' + (i + 1) + ' 页 ---\n';
          }
          all += text;
        }
      } catch (err) {
        console.error('ocr image failed idx=' + i, JSON.stringify(err));
      }
    }
    console.log('BookOcr recognized text:', all.trim());
    return all.trim();
  });
}

async function recognizeImageWithPreprocess(filePath: string, pageNo: number): Promise<string> {
  const source = await image.createImageSource(filePath);
  try {
    const pm = await source.createPixelMap();
    try {
      const up = await upscalePixelMap(pm);
      let text = '';
      if (up) {
        text = await recognizeOnce(up, pageNo);
        up.release();
      }
      const text2 = await recognizeOnce(pm, pageNo);
      if (text.length === 0) {
        return text2;
      }
      if (text2.length === 0) {
        return text;
      }
      return mergeUniqueLines(text, text2);
    } finally {
      pm.release();
    }
  } finally {
    await source.release();
  }
}

async function upscalePixelMap(pm: image.PixelMap): Promise<image.PixelMap | null> {
  try {
    const info = await pm.getImageInfo();
    const dim = Math.max(info.size.width, info.size.height);
    if (dim * UPSCALE > 4096) {
      return null;
    }
    return await pm.createScaledPixelMap(UPSCALE, UPSCALE);
  } catch (err) {
    console.error('upscale failed', JSON.stringify(err));
    return null;
  }
}

async function recognizeOnce(pm: image.PixelMap, pageNo: number): Promise<string> {
  const config: textRecognition.TextRecognitionConfiguration = {
    isDirectionDetectionSupported: true
  };
  try {
    const res = await textRecognition.recognizeText({ pixelMap: pm }, config);
    if (res.blocks && res.blocks.length > 0) {
      // 逐行抽取（blocks → lines → value），保行保序，供 AmountParser 按行解析
      const parts: string[] = [];
      for (let i = 0; i < res.blocks.length; i++) {
        const blk = res.blocks[i];
        if (!blk.lines) {
          continue;
        }
        const blkLines: string[] = [];
        for (let j = 0; j < blk.lines.length; j++) {
          const v = blk.lines[j].value;
          if (v.trim().length > 0) {
            blkLines.push(v);
          }
        }
        if (blkLines.length > 0) {
          // 块边界插页标记：一图多账单/多图隔离，AmountParser 遇到即重置跨行上下文
          parts.push('--- 第 ' + pageNo + ' 页 ---');
          parts.push(blkLines.join('\n'));
        }
      }
      return parts.length > 0 ? parts.join('\n') : (res.value ?? '');
    }
    return res.value ?? '';
  } catch (err) {
    console.error('recognizeText failed', JSON.stringify(err));
    return '';
  }
}

export function mergeUniqueLines(a: string, b: string): string {
  const seen = new Set<string>();
  const out: string[] = [];
  const lines = (a + '\n' + b).split('\n');
  for (const line of lines) {
    const t = line.trim();
    if (t.length === 0) {
      continue;
    }
    if (!seen.has(t)) {
      seen.add(t);
      out.push(t);
    }
  }
  return out.join('\n');
}
