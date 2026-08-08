import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const MODEL_FILE_NAME = 'albert_finetuned.ms';
const VOCAB_FILE_NAME = 'vocab.txt';
const LABELS_FILE_NAME = 'labels.json';
const MAX_INPUT_LENGTH = 128;
const DEFAULT_PAD_ID = 0;
const DEFAULT_UNK_ID = 1;

export interface ClassificationResult {
  category: string;
  confidence: number;
}

interface LabelsConfig {
  labelMap?: Record<string, string>;
  invLabelMap?: Record<string, string>;
}

export class BillClassifier {
  private model: mindSporeLite.Model | null = null;
  private tokenToId: Map<string, number> = new Map();
  private categoryNames: string[] = [];
  private padId: number = DEFAULT_PAD_ID;
  private unkId: number = DEFAULT_UNK_ID;
  private loaded: boolean = false;

  async init(context: common.Context): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      const modelBytes = await context.resourceManager.getRawFileContent(MODEL_FILE_NAME);
      const modelBuffer = new ArrayBuffer(modelBytes.byteLength);
      new Uint8Array(modelBuffer).set(new Uint8Array(modelBytes.buffer));

      this.model = await mindSporeLite.loadModelFromBuffer(modelBuffer, {
        target: ['cpu'],
        cpu: {
          threadNum: 1
        }
      });
      if (!this.model) {
        this.model = null;
        return;
      }

      await this.loadVocab(context);
      await this.loadLabels(context);

      this.loaded = true;
      console.log('BillClassifier initialized successfully');
    } catch (err) {
      console.error('BillClassifier init failed:', JSON.stringify(err));
      this.model = null;
      this.loaded = false;
    }
  }

  private async loadVocab(context: common.Context): Promise<void> {
    const vocabBytes = await context.resourceManager.getRawFileContent(VOCAB_FILE_NAME);
    const decoder = new util.TextDecoder();
    const content = decoder.decodeToString(new Uint8Array(vocabBytes.buffer));
    const lines = content.split('\n');
    this.tokenToId = new Map<string, number>();
    for (let i = 0; i < lines.length; i++) {
      const token = lines[i].trim();
      if (token) {
        if (this.tokenToId.has(token)) {
          continue;
        }
        this.tokenToId.set(token, i);
        if (token === '[PAD]') {
          this.padId = i;
        } else if (token === '[UNK]') {
          this.unkId = i;
        }
      }
    }
  }

  private async loadLabels(context: common.Context): Promise<void> {
    const bytes = await context.resourceManager.getRawFileContent(LABELS_FILE_NAME);
    const decoder = new util.TextDecoder();
    const content = decoder.decodeToString(new Uint8Array(bytes.buffer));
    const labelsConfig = JSON.parse(content) as LabelsConfig;
    const inv: Record<string, string> = labelsConfig.invLabelMap ? labelsConfig.invLabelMap : {};
    const names: string[] = [];
    const keys = Object.keys(inv);
    keys.sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    for (let i = 0; i < keys.length; i++) {
      names.push(inv[keys[i]]);
    }
    this.categoryNames = names;
  }

  private tokenizeToIds(text: string): Int32Array {
    const result = new Int32Array(MAX_INPUT_LENGTH);
    let pos = 0;
    result[pos] = this.clsId();
    pos++;
    for (let i = 0; i < text.length && pos < MAX_INPUT_LENGTH - 1; i++) {
      const ch = text[i];
      let id: number = this.unkId;
      if (this.tokenToId.has(ch)) {
        const foundId = this.tokenToId.get(ch);
        if (foundId !== undefined) {
          id = foundId;
        }
      }
      result[pos] = id;
      pos++;
    }
    if (pos < MAX_INPUT_LENGTH) {
      result[pos] = this.sepId();
      pos++;
    }
    while (pos < MAX_INPUT_LENGTH) {
      result[pos] = this.padId;
      pos++;
    }
    return result;
  }

  private clsId(): number {
    const id = this.tokenToId.get('[CLS]');
    return id !== undefined ? id : 101;
  }

  private sepId(): number {
    const id = this.tokenToId.get('[SEP]');
    return id !== undefined ? id : 102;
  }

  async classify(text: string): Promise<ClassificationResult | null> {
    if (!this.loaded || !this.model) {
      console.error('BillClassifier not loaded');
      return null;
    }
    try {
      const inputIds = this.tokenizeToIds(text);
      const attentionMask = new Int32Array(MAX_INPUT_LENGTH);
      for (let i = 0; i < MAX_INPUT_LENGTH; i++) {
        attentionMask[i] = inputIds[i] !== this.padId ? 1 : 0;
      }

      const inputs: mindSporeLite.MSTensor[] = this.model.getInputs();
      if (!inputs || inputs.length < 2) {
        console.error('model inputs invalid');
        return null;
      }

      const idBytes = new ArrayBuffer(inputIds.byteLength);
      new Int32Array(idBytes).set(inputIds);
      inputs[0].setData(idBytes);

      const maskBytes = new ArrayBuffer(attentionMask.byteLength);
      new Int32Array(maskBytes).set(attentionMask);
      inputs[1].setData(maskBytes);

      const outputs: mindSporeLite.MSTensor[] = await this.model.predict(inputs);
      if (!outputs || outputs.length === 0) {
        console.error('predict returned empty outputs');
        return null;
      }

      const logitsBuf: ArrayBuffer = outputs[0].getData();
      const logits = new Float32Array(logitsBuf);
      if (logits.length === 0) {
        return null;
      }

      let maxIdx = 0;
      for (let i = 1; i < logits.length; i++) {
        if (logits[i] > logits[maxIdx]) {
          maxIdx = i;
        }
      }

      const expValues = new Float32Array(logits.length);
      let sumExp = 0;
      for (let i = 0; i < logits.length; i++) {
        expValues[i] = Math.exp(logits[i]);
        sumExp += expValues[i];
      }
      const confidence = sumExp > 0 ? expValues[maxIdx] / sumExp : 0;

      const category = maxIdx < this.categoryNames.length ? this.categoryNames[maxIdx] : '其他';
      return {
        category: category,
        confidence: confidence
      };
    } catch (err) {
      console.error('BillClassifier classify failed:', JSON.stringify(err));
      return null;
    }
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  release(): void {
    this.model = null;
    this.tokenToId.clear();
    this.categoryNames = [];
    this.loaded = false;
  }
}

let classifierInstance: BillClassifier | null = null;

export function getBillClassifier(): BillClassifier {
  if (!classifierInstance) {
    classifierInstance = new BillClassifier();
  }
  return classifierInstance;
}

export const billClassifier = getBillClassifier();