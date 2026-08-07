import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { importPDFToLibrary } from './ImportLibrary';

async function pickAndCopyPDF(context: common.Context): Promise<string> {
  const documentPicker = new picker.DocumentViewPicker(context);
  const uris: Array<string> = await documentPicker.select({
    maxSelectNumber: 1,
    fileSuffixFilters: ['.pdf']
  });
  if (!uris || uris.length === 0) {
    return '';
  }
  return importPDFToLibrary(context, uris[0]);
}

export { pickAndCopyPDF };
