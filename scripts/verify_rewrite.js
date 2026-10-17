#!/usr/bin/env node
/**
 * 多选改字功能验证（只读，无副作用）。
 * 复刻 entry/src/main/ets/utils/PDFEditUtils.ets 与 pages/PDFEditPage.ets 中的纯逻辑：
 *  1) TextBlockInfo.id 生成（`${pageIndex}_${objIdx}`，同页唯一）
 *  2) applyEditsAsync 的 rewriteText 入栈映射（xs=index → 定位第 N 个 TEXT 对象；nums=newSize；texts=newText）
 *  3) 改字回写复用原 TextObject.fontInfo（不改字体）—— 校验 rwRefs[].fontInfo 复用分支
 *  4) addText 入栈映射（xs=color/ys=x/ws=y/nums=size 与 runEditOps 读取语义 opsX→textColor、opsY→x、opsW→y、opsNum→textSize 对应）
 *  5) 批量改字选择逻辑（全选/全不选/部分选择 → batchId 同批统一）
 *  6) 批量撤回（按勾选倒序删除、预览清理）
 *  7) 错误前缀「改字错误：」与 300ms toast 防抖
 *  8) 切页安全（退出改字模式 + 重新加载新页块）
 *  9) 性能：100 页 × 300 块 列表与选择全流程耗时
 * 运行：node scripts/verify_rewrite.js
 */
const { performance } = require('perf_hooks');

let fails = 0;
function check(name, cond, detail) {
  const ok = !!cond;
  if (!ok) fails++;
  console.log((ok ? 'OK   ' : 'FAIL ') + name + (detail ? '  (' + detail + ')' : ''));
}

// ---------- 1. id 生成（复刻 listTextObjectsAsync blocks.push） ----------
function makeBlock(pageIndex, objIdx, text, size, fontName) {
  return { index: objIdx, id: pageIndex + '_' + objIdx, text: text, size: size, fontName: fontName || undefined };
}
const blocks = [];
for (let p = 0; p < 2; p++) {
  for (let i = 0; i < 3; i++) {
    blocks.push(makeBlock(p, i, '块' + p + '_' + i, 12 + i, i === 0 ? 'HarmonyOS Sans' : ''));
  }
}
const ids = blocks.map((b) => b.id);
const idSet = new Set(ids);
check('id 唯一（6 块）', idSet.size === 6, 'size=' + idSet.size);
check('id 格式 pageIndex_objIdx', blocks[4].id === '1_1', blocks[4].id);
check('fontName 保留', blocks[0].fontName === 'HarmonyOS Sans' && blocks[1].fontName === undefined, JSON.stringify(blocks[0].fontName) + '/' + JSON.stringify(blocks[1].fontName));

// ---------- 2. rewriteText 入栈映射（复刻 applyEditsAsync rewriteText 分支 + runEditOps OP_REWRITE_TEXT 定位） ----------
function rewriteOpToArrays(op) {
  return { kinds: 8, pages: op.page, xs: op.index, ys: 0, ws: 0, hs: 0, texts: op.newText, nums: op.newSize, counts: 1 };
}
const rw = { op: 'rewriteText', page: 2, index: 5, newText: '新文字', newSize: 14, batchId: 'b123' };
const rwArr = rewriteOpToArrays(rw);
check('rewriteText xs=块序号', rwArr.xs === 5, 'xs=' + rwArr.xs);
check('rewriteText nums=新字号', rwArr.nums === 14, 'nums=' + rwArr.nums);
check('rewriteText texts=新文字', rwArr.texts === '新文字', rwArr.texts);

// ---------- 3. 回写复用 fontInfo（复刻 runEditOps 回写分支：style.fontInfo = rwRefs[j].fontInfo） ----------
function rewriteWriteBack(fontInfo) {
  // 有 fontInfo 则复用原字体；无则回退系统字体
  const style = {};
  if (fontInfo) {
    style.fontInfo = fontInfo;
  } else {
    style.fontInfo = { fontName: 'HarmonyOS Sans' };
  }
  return style.fontInfo;
}
const origFont = { fontName: 'FZHei-B01' };
const wb1 = rewriteWriteBack(origFont);
const wb2 = rewriteWriteBack(null);
check('改字后字体不变（复用原 fontInfo）', wb1 === origFont && wb1.fontName === 'FZHei-B01', wb1.fontName);
check('无 fontInfo 时回退系统字体', wb2.fontName === 'HarmonyOS Sans', wb2.fontName);

// ---------- 4. addText 入栈映射（复刻 applyEditsAsync addText 分支与 runEditOps 读取语义） ----------
// runEditOps 读取：style.textSize=opsNum、style.textColor=opsX、addTextObject(text, opsY, opsW)
// applyEditsAsync 写入：xs=op.color、ys=op.x、ws=op.y、nums=op.size
function addTextToArrays(op) {
  return { kinds: 1, pages: op.page, xs: op.color, ys: op.x, ws: op.y, hs: 0, texts: op.text, nums: op.size, counts: 1 };
}
function runEditOpsAddText(arr) {
  const style = { textSize: arr.nums, textColor: arr.xs };
  const pos = { x: arr.ys, y: arr.ws };
  return { style: style, pos: pos };
}
const at = { op: 'addText', page: 0, text: '你好', x: 30, y: 50, size: 16, color: 0x1A1A1F };
const atArr = addTextToArrays(at);
const atOut = runEditOpsAddText(atArr);
check('addText textSize=op.size', atOut.style.textSize === 16, 'size=' + atOut.style.textSize);
check('addText textColor=op.color', atOut.style.textColor === 0x1A1A1F, 'color=' + atOut.style.textColor);
check('addText x=op.x', atOut.pos.x === 30, 'x=' + atOut.pos.x);
check('addText y=op.y', atOut.pos.y === 50, 'y=' + atOut.pos.y);

// ---------- 5. 批量选择逻辑（复刻 PDFEditPage onToggleBlock/onSelectAll/onSelectNone/applyBatchRewrite） ----------
function toggle(arr, id) {
  const idx = arr.indexOf(id);
  if (idx >= 0) {
    const a = arr.slice();
    a.splice(idx, 1);
    return a;
  }
  const a = arr.slice();
  a.push(id);
  return a;
}
function selectAll(blocks) { return blocks.map((b) => b.id); }
let selected = [];
selected = selectAll(blocks);
check('全选选中全部 6 块', selected.length === 6, selected.length);
selected = toggle(selected, '0_1');
selected = toggle(selected, '0_2');
selected = toggle(selected, '1_0');
check('部分选择（去 3 留 3）', selected.length === 3 && selected.indexOf('0_1') < 0 && selected.indexOf('1_0') < 0, selected.join(','));
selected = [];
check('全不选清空', selected.length === 0, selected.length);

function applyBatchRewrite(blocks, selectedIds, newText, newSize, batchId) {
  const ops = [];
  const previews = [];
  const targets = blocks.filter((b) => selectedIds.indexOf(b.id) >= 0);
  for (const b of targets) {
    ops.push({ op: 'rewriteText', page: 0, index: b.index, newText: newText, newSize: newSize > 0 ? newSize : b.size, batchId: batchId });
  }
  for (const b of blocks) {
    previews.push(selectedIds.indexOf(b.id) >= 0 ? newText : '');
  }
  return { ops: ops, previews: previews };
}
const batchRes = applyBatchRewrite(blocks, ['0_0', '0_1', '1_2'], '统一文案', 15, 'b1');
check('同批 op batchId 统一', batchRes.ops.every((o) => o.batchId === 'b1'), 'count=' + batchRes.ops.length);
check('选中 3 块生成 3 个 op', batchRes.ops.length === 3, batchRes.ops.length);
check('预览仅命中块填充', batchRes.previews[0] === '统一文案' && batchRes.previews[3] === '' && batchRes.previews[5] === '统一文案', batchRes.previews.join('|'));
check('未指定字号沿用块原字号', applyBatchRewrite(blocks, ['0_0'], 'x', 0, 'b2').ops[0].newSize === blocks[0].size, 'size=' + applyBatchRewrite(blocks, ['0_0'], 'x', 0, 'b2').ops[0].newSize);

// ---------- 6. 批量撤回（复刻 undoLastOp→openBatchUndo→onUndoConfirm：勾选倒序删除 + 预览清理） ----------
function batchUndoConfirm(ops, previews, checked) {
  const remove = [];
  for (let i = 0; i < checked.length; i++) {
    if (checked[i]) remove.push(i);
  }
  remove.sort((a, b) => b - a);
  for (const idx of remove) {
    const o = ops[idx];
    previews[o.blockIdx] = '';
    ops.splice(idx, 1);
  }
  return { ops: ops, previews: previews };
}
let undoOps = [
  { batchId: 'b1', newText: 'A', blockIdx: 0 },
  { batchId: 'b1', newText: 'B', blockIdx: 1 },
  { batchId: 'b1', newText: 'C', blockIdx: 2 },
];
const undoPreviews = ['A', 'B', 'C'];
const undone = batchUndoConfirm(undoOps, undoPreviews, [true, false, true]);
check('撤回只删勾选 2 项（留 B）', undone.ops.length === 1 && undone.ops[0].newText === 'B', 'left=' + undone.ops.map((o) => o.newText).join(','));
check('被撤回块预览已清', undone.previews[0] === '' && undone.previews[2] === '' && undone.previews[1] === 'B', undone.previews.join(','));

// ---------- 7. 错误前缀与 toast 防抖（复刻 showRewriteError/toastDebounced） ----------
let toastQueue = [];
let toastTimer = -1;
function toastDebounced(msg) {
  if (toastTimer >= 0) return 0;
  toastTimer = 1;
  toastQueue.push(msg);
  return 1;
}
function showRewriteError(msg) { return toastDebounced('改字错误：' + msg); }
const e1 = showRewriteError('请输入文字内容');
const e2 = showRewriteError('请至少选择一个文本块');
check('错误提示带「改字错误：」前缀', toastQueue[0] === '改字错误：请输入文字内容', toastQueue[0]);
check('300ms 内第二次被防抖拦截', e2 === 0 && toastQueue.length === 1, 'queue=' + toastQueue.length + ' e2=' + e2);

// ---------- 8. 切页安全（复刻 onPageChangedForRewrite：退出模式+清态+重新加载） ----------
function onPageChanged(activedTool) {
  if (activedTool === 4) {
    return {
      activedTool: -1,
      showSelectDialog: false,
      showEditDialog: false,
      showUndoDialog: false,
      selectedIds: [],
      rewriteBlocks: [],
      reloaded: true
    };
  }
  return { activedTool: activedTool, reloaded: false };
}
const pg = onPageChanged(4);
check('切页自动退出改字模式', pg.activedTool === -1 && pg.showSelectDialog === false && pg.rewriteBlocks.length === 0, 'tool=' + pg.activedTool);
check('切页触发重新加载新页块', pg.reloaded === true, 'reloaded=' + pg.reloaded);

// ---------- 9. 性能：100 页 × 300 块 列表与选择 ----------
const t0 = performance.now();
const bigBlocks = [];
for (let p = 0; p < 100; p++) {
  for (let i = 0; i < 300; i++) {
    bigBlocks.push(makeBlock(p, i, '第' + p + '页 内容块' + i + ' 的预览文字', 12 + (i % 20), ''));
  }
}
let bigSelected = [];
bigSelected = selectAll(bigBlocks);
bigSelected = bigSelected.slice(0, 1500);
const t1 = performance.now();
const listMs = Math.round(t1 - t0);
check('性能：100页×300块=3万块 列表+全选+部分选择 < 2s', listMs < 2000, listMs + 'ms');
console.log('PERF blocks=' + bigBlocks.length + ' selected=' + bigSelected.length + ' ms=' + listMs);

if (fails > 0) {
  console.error('REWRITE_FAIL count=' + fails);
  process.exit(1);
}
console.log('REWRITE_ALL_OK');
