import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

export interface ImportFileItem {
  name: string;
  path: string;
  star: boolean;
  time: number;
  starPinTime?: number;
}

interface RecentStore {
  files: Array<ImportFileItem>;
}

const IMPORTS_DIR = 'imports';
const RECENT_FILE = 'recent.json';

function importsDir(context: common.Context): string {
  return context.filesDir + '/' + IMPORTS_DIR;
}

function recentFilePath(context: common.Context): string {
  return importsDir(context) + '/' + RECENT_FILE;
}

function sanitizeName(name: string): string {
  const cleaned = name.replace(/[\\/:*?"<>|]/g, '_');
  return cleaned.length > 0 ? cleaned : 'document.pdf';
}

async function extractDisplayName(srcUri: string): Promise<string> {
  const tail = srcUri.split('/').pop() ?? 'document.pdf';
  const cleanTail = tail.split('?')[0];
  try {
    const decoded = decodeURIComponent(cleanTail);
    if (decoded && decoded !== cleanTail) {
      return decoded;
    }
  } catch (e) {
    // 非法编码时忽略，走兜底
  }
  return tail;
}

async function ensureDir(context: common.Context): Promise<void> {
  try {
    await fileIo.mkdir(importsDir(context));
  } catch (e) {
    // 目录已存在时忽略
  }
}

async function pathExists(path: string): Promise<boolean> {
  try {
    return await fileIo.access(path);
  } catch (e) {
    return false;
  }
}

async function uniquePath(dir: string, name: string): Promise<string> {
  let candidate = dir + '/' + name;
  let i = 1;
  while (await pathExists(candidate)) {
    const dot = name.lastIndexOf('.');
    const stem = dot > 0 ? name.slice(0, dot) : name;
    const ext = dot > 0 ? name.slice(dot) : '';
    candidate = dir + '/' + stem + '(' + i + ')' + ext;
    i++;
  }
  return candidate;
}

async function copyFileTo(srcUri: string, destPath: string): Promise<void> {
  try {
    const src = await fileIo.open(srcUri, fileIo.OpenMode.READ_ONLY);
    try {
      const st = await fileIo.stat(srcUri);
      const buf = new ArrayBuffer(st.size);
      await fileIo.read(src.fd, buf);
      const dst = await fileIo.open(destPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(dst.fd, buf);
      } finally {
        try {
          await fileIo.close(dst.fd);
        } catch (closeErr) {
          console.error('copyFileTo close dst failed:', JSON.stringify(closeErr));
        }
      }
    } finally {
      try {
        await fileIo.close(src.fd);
      } catch (closeErr) {
        console.error('copyFileTo close src failed:', JSON.stringify(closeErr));
      }
    }
  } catch (err) {
    console.error('copyFileTo failed:', JSON.stringify(err));
    throw new Error(String(err));
  }
}

export async function importPDFToLibrary(context: common.Context, srcUri: string): Promise<string> {
  await ensureDir(context);
  const rawName = await extractDisplayName(srcUri);
  const baseName = sanitizeName(rawName.split('?')[0]);
  const destPath = await uniquePath(importsDir(context), baseName);
  await copyFileTo(srcUri, destPath);
  const destBaseName = destPath.split('/').pop() ?? baseName;
  const files = await loadRecentFiles(context);
  const idx = files.findIndex((f) => f.name === destBaseName);
  if (idx >= 0) {
    files.splice(idx, 1);
  }
  files.unshift({ name: destBaseName, path: destPath, star: false, time: Date.now() });
  await saveRecentFiles(context, files);
  return destPath;
}

export async function loadRecentFiles(context: common.Context): Promise<Array<ImportFileItem>> {
  try {
    const text = await fileIo.readText(recentFilePath(context));
    if (!text) {
      return [];
    }
    const store = JSON.parse(text) as RecentStore;
    return store.files ?? [];
  } catch (e) {
    return [];
  }
}

export async function saveRecentFiles(context: common.Context, files: Array<ImportFileItem>): Promise<void> {
  await ensureDir(context);
  const store: RecentStore = { files: files };
  const text = JSON.stringify(store);
  try {
    const file = await fileIo.open(recentFilePath(context), fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const encoder = new util.TextEncoder();
      const buf = encoder.encodeInto(text).buffer;
      await fileIo.write(file.fd, buf);
    } finally {
      try {
        await fileIo.close(file.fd);
      } catch (closeErr) {
        console.error('saveRecentFiles close failed:', JSON.stringify(closeErr));
      }
    }
  } catch (err) {
    console.error('saveRecentFiles failed:', JSON.stringify(err));
  }
}

export async function toggleStar(context: common.Context, name: string): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  const idx = files.findIndex((f) => f.name === name);
  if (idx >= 0) {
    files[idx].star = !files[idx].star;
    await saveRecentFiles(context, files);
  }
  return files;
}

export async function toggleStarPin(context: common.Context, name: string): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  const idx = files.findIndex((f) => f.name === name);
  if (idx >= 0) {
    const pinned = files[idx].starPinTime !== undefined;
    if (pinned) {
      files[idx].starPinTime = undefined;
    } else {
      files[idx].starPinTime = Date.now();
    }
    await saveRecentFiles(context, files);
  }
  return files;
}

export async function pinStarBatch(context: common.Context, names: Array<string>): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  const now = Date.now();
  for (const n of names) {
    const idx = files.findIndex((f) => f.name === n);
    if (idx >= 0) {
      files[idx].starPinTime = now;
    }
  }
  await saveRecentFiles(context, files);
  return files;
}

export async function moveToTop(context: common.Context, name: string): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  const idx = files.findIndex((f) => f.name === name);
  if (idx >= 0) {
    const target = files[idx];
    target.time = Date.now();
    files.splice(idx, 1);
    files.unshift(target);
    await saveRecentFiles(context, files);
  }
  return files;
}

export async function deleteImports(context: common.Context, names: Array<string>): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  const targets = files.filter((f) => names.includes(f.name));
  for (const t of targets) {
    try {
      await fileIo.unlink(t.path);
    } catch (e) {
      // 文件删除失败不阻塞清单更新
    }
  }
  const kept = files.filter((f) => !names.includes(f.name));
  await saveRecentFiles(context, kept);
  return kept;
}

export async function moveToTopBatch(context: common.Context, names: Array<string>): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  for (let i = names.length - 1; i >= 0; i--) {
    const idx = files.findIndex((f) => f.name === names[i]);
    if (idx >= 0) {
      const target = files[idx];
      target.time = Date.now();
      files.splice(idx, 1);
      files.unshift(target);
    }
  }
  await saveRecentFiles(context, files);
  return files;
}

export function deleteImport(context: common.Context, name: string): Promise<Array<ImportFileItem>> {
  return deleteFromLibrary(context, name);
}

async function deleteFromLibrary(context: common.Context, name: string): Promise<Array<ImportFileItem>> {
  const files = await loadRecentFiles(context);
  const idx = files.findIndex((f) => f.name === name);
  if (idx >= 0) {
    const target = files[idx];
    files.splice(idx, 1);
    try {
      await fileIo.unlink(target.path);
    } catch (e) {
      // 文件删除失败不阻塞清单更新
    }
    await saveRecentFiles(context, files);
  }
  return files;
}

export async function addEditedFile(context: common.Context, editedPath: string, baseName: string): Promise<string> {
  await ensureDir(context);
  const destPath = await uniquePath(importsDir(context), sanitizeName(baseName));
  await copyFileTo(editedPath, destPath);
  const destBaseName = destPath.split('/').pop() ?? baseName;
  const files = await loadRecentFiles(context);
  const idx = files.findIndex((f) => f.name === destBaseName);
  if (idx >= 0) {
    files.splice(idx, 1);
  }
  files.unshift({ name: destBaseName, path: destPath, star: false, time: Date.now() });
  await saveRecentFiles(context, files);
  return destPath;
}

export function formatRelativeTime(time: number): string {
  const diff = Date.now() - time;
  const minute = 60 * 1000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (diff < minute) {
    return '刚刚';
  }
  if (diff < hour) {
    return Math.floor(diff / minute) + ' 分钟前';
  }
  if (diff < day) {
    return Math.floor(diff / hour) + ' 小时前';
  }
  if (diff < 7 * day) {
    return Math.floor(diff / day) + ' 天前';
  }
  const d = new Date(time);
  return d.getFullYear() + '/' + (d.getMonth() + 1) + '/' + d.getDate();
}
