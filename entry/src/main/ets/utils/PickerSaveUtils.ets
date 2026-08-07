import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export async function saveSandboxFile(context: common.Context, srcSandboxPath: string, suggestedName: string, suffix: string): Promise<boolean> {
  try {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [suggestedName];
    options.fileSuffixChoices = [suffix];
    const pickerInst = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await pickerInst.save(options);
    if (!uris || uris.length === 0) {
      return false;
    }
    const dstUri = uris[0];
    let srcFd: number = 0;
    let dstFd: number = 0;
    try {
      const stat = await fileIo.stat(srcSandboxPath);
      const buf = new ArrayBuffer(stat.size);
      const src = await fileIo.open(srcSandboxPath, fileIo.OpenMode.READ_ONLY);
      srcFd = src.fd;
      await fileIo.read(srcFd, buf);
      const dst = await fileIo.open(dstUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      dstFd = dst.fd;
      await fileIo.write(dstFd, buf);
      return true;
    } finally {
      if (srcFd !== 0) {
        await fileIo.close(srcFd);
      }
      if (dstFd !== 0) {
        await fileIo.close(dstFd);
      }
    }
  } catch (err) {
    const e = err as BusinessError;
    console.error('saveSandboxFile failed', JSON.stringify(e));
    return false;
  }
}
