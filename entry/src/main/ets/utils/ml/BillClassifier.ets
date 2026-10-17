import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const MODEL_FILE_NAME = 'ml/albert_finetuned.ms';
const VOCAB_FILE_NAME = 'ml/vocab.txt';
const LABELS_FILE_NAME = 'ml/labels.json';
const MAX_INPUT_LENGTH = 128;
const DEFAULT_PAD_ID = 0;
const DEFAULT_UNK_ID = 100;

interface LabelsConfig {
  labelMap?: Record<string, string>;
  invLabelMap?: Record<string, string>;
  inv_label_map?: Record<string, string>;
}

export interface ClassificationResult {
  category: string;
  confidence: number;
  secondConfidence?: number;
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
      if (!canIUse('SystemCapability.AI.MindSporeLite')) {
        console.error('MindSporeLite syscap unsupported, BillClassifier disabled');
        return;
      }
      const modelBytes = await context.resourceManager.getRawFileContent(MODEL_FILE_NAME);
      const modelBuffer = new ArrayBuffer(modelBytes.byteLength);
      new Uint8Array(modelBuffer).set(new Uint8Array(modelBytes.buffer));

      if (canIUse('SystemCapability.AI.MindSporeLite')) {
        this.model = await mindSporeLite.loadModelFromBuffer(modelBuffer, {
          target: ['cpu'],
          cpu: {
            threadNum: 1
          }
        });
      }
      if (!this.model) {
        this.model = null;
        return;
      }

      await this.loadVocab(context);
      await this.loadLabels(context);

      this.loaded = true;
      console.log('BillClassifier initialized successfully');
      this.warmup();
    } catch (err) {
      console.error('BillClassifier init failed:', JSON.stringify(err));
      this.model = null;
      this.loaded = false;
    }
  }

  private async warmup(): Promise<void> {
    try {
      const res = await this.classify('美团外卖 消费');
      if (res) {
        console.log('BillClassifier warmup ok, category=' + res.category + ', conf=' + res.confidence.toFixed(3)
          + ', sec=' + (res.secondConfidence ?? 0).toFixed(3)
          + ', margin=' + (res.confidence - (res.secondConfidence ?? 0)).toFixed(3));
      } else {
        console.error('BillClassifier warmup returned null');
      }
    } catch (err) {
      console.error('BillClassifier warmup failed:', JSON.stringify(err));
    }
  }

  private async loadVocab(context: common.Context): Promise<void> {
    try {
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
    } catch (err) {
      console.error('loadVocab failed:', JSON.stringify(err));
    }
  }

  private async loadLabels(context: common.Context): Promise<void> {
    try {
      const bytes = await context.resourceManager.getRawFileContent(LABELS_FILE_NAME);
      const decoder = new util.TextDecoder();
      const content = decoder.decodeToString(new Uint8Array(bytes.buffer));
      const labelsConfig = JSON.parse(content) as LabelsConfig;
      const inv: Record<string, string> = labelsConfig.invLabelMap ? labelsConfig.invLabelMap :
        (labelsConfig.inv_label_map ? labelsConfig.inv_label_map : {});
      const names: string[] = [];
      const keys = Object.keys(inv);
      keys.sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
      for (let i = 0; i < keys.length; i++) {
        names.push(inv[keys[i]]);
      }
      this.categoryNames = names;
    } catch (err) {
      console.error('loadLabels failed:', JSON.stringify(err));
    }
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
    if (canIUse('SystemCapability.AI.MindSporeLite')) {
      return await this.classifyWithModel(text);
    }
    console.error('MindSporeLite syscap unsupported');
    return null;
  }

  private async classifyWithModel(text: string): Promise<ClassificationResult | null> {
    if (!this.model) {
      return null;
    }
    if (canIUse('SystemCapability.AI.MindSporeLite')) {
      try {
        const inputIds = this.tokenizeToIds(text);
        const attentionMask = new Uint8Array(MAX_INPUT_LENGTH);
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
        new Uint8Array(maskBytes).set(attentionMask);
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
        let secondIdx = -1;
        for (let i = 1; i < logits.length; i++) {
          if (logits[i] > logits[maxIdx]) {
            secondIdx = maxIdx;
            maxIdx = i;
          } else if (secondIdx < 0 || logits[i] > logits[secondIdx]) {
            secondIdx = i;
          }
        }

        const expValues = new Float32Array(logits.length);
        let sumExp = 0;
        for (let i = 0; i < logits.length; i++) {
          expValues[i] = Math.exp(logits[i]);
          sumExp += expValues[i];
        }
        const confidence = sumExp > 0 ? expValues[maxIdx] / sumExp : 0;
        const secondConfidence = sumExp > 0 && secondIdx >= 0 ? expValues[secondIdx] / sumExp : 0;

        const category = maxIdx < this.categoryNames.length ? this.categoryNames[maxIdx] : '其他';
        return {
          category: category,
          confidence: confidence,
          secondConfidence: secondConfidence
        };
      } catch (err) {
        console.error('BillClassifier classify failed:', JSON.stringify(err));
        return null;
      }
    }
    console.error('MindSporeLite syscap unsupported');
    return null;
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