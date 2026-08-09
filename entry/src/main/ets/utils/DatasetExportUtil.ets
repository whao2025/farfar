import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BookkeepingRecord, RecordSource, RecordStatus } from '../model/RecordModel';

const DB_NAME = 'freepdf_accounting.db';
const TABLE_NAME = 'records';

export interface TrainingRecord {
  id: number;
  text: string;
  category: string;
  type: 'expense' | 'income';
  amount: number;
  merchant?: string;
  source: RecordSource;
  timestamp: number;
  dateStr: string;
  confidence: number;
}

interface ExportRecord {
  id: number;
  text: string;
  category: string;
  type: 'expense' | 'income';
  amount: number;
  merchant: string;
  source: RecordSource;
  confidence: number;
}

interface ExportPayload {
  version: string;
  exportDate: string;
  recordCount: number;
  records: ExportRecord[];
}

export class DatasetExportUtil {
  private db: relationalStore.RdbStore | null = null;
  private static instance: DatasetExportUtil | null = null;

  private constructor() {}

  static getInstance(): DatasetExportUtil {
    if (!DatasetExportUtil.instance) {
      DatasetExportUtil.instance = new DatasetExportUtil();
    }
    return DatasetExportUtil.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.db) return;

    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S2
    };
    try {
      this.db = await relationalStore.getRdbStore(context, config);
    } catch (err) {
      console.error('DatasetExport getRdbStore failed:', JSON.stringify(err));
      this.db = null;
      throw new Error(String(err));
    }
  }

  async getAllRecords(): Promise<TrainingRecord[]> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `SELECT * FROM ${TABLE_NAME} WHERE status = ? ORDER BY timestamp DESC`;
    const args: Array<relationalStore.ValueType> = [RecordStatus.CONFIRMED];

    const records: TrainingRecord[] = [];
    try {
      const resultSet = await this.db.querySql(sql, args);
      try {
        while (resultSet.goToNextRow()) {
          const idIdx = resultSet.getColumnIndex('id');
          const amountIdx = resultSet.getColumnIndex('amount');
          const typeIdx = resultSet.getColumnIndex('type');
          const categoryIdx = resultSet.getColumnIndex('category');
          const noteIdx = resultSet.getColumnIndex('note');
          const merchantIdx = resultSet.getColumnIndex('merchant');
          const timestampIdx = resultSet.getColumnIndex('timestamp');
          const dateStrIdx = resultSet.getColumnIndex('dateStr');
          const confidenceIdx = resultSet.getColumnIndex('confidence');
          const sourceIdx = resultSet.getColumnIndex('source');

          const merchantValue = resultSet.getString(merchantIdx);

          records.push({
            id: resultSet.getLong(idIdx),
            text: resultSet.getString(noteIdx) || '',
            category: resultSet.getString(categoryIdx),
            type: resultSet.getString(typeIdx) as 'expense' | 'income',
            amount: resultSet.getDouble(amountIdx),
            merchant: merchantValue && merchantValue.trim().length > 0 ? merchantValue : undefined,
            source: resultSet.getString(sourceIdx) as RecordSource,
            timestamp: resultSet.getLong(timestampIdx),
            dateStr: resultSet.getString(dateStrIdx),
            confidence: resultSet.getDouble(confidenceIdx)
          });
        }
      } finally {
        try {
          resultSet.close();
        } catch (closeErr) {
          console.error('resultSet close failed:', JSON.stringify(closeErr));
        }
      }
    } catch (err) {
      console.error('getAllRecords failed:', JSON.stringify(err));
    }
    return records;
  }

  async exportToJSON(filePath: string, records: TrainingRecord[]): Promise<void> {
    const data: ExportPayload = {
      version: '1.0',
      exportDate: new Date().toISOString(),
      recordCount: records.length,
      records: records.map(r => ({
        id: r.id,
        text: r.text,
        category: r.category,
        type: r.type,
        amount: r.amount,
        merchant: r.merchant || '',
        source: r.source,
        confidence: r.confidence
      }) as ExportRecord)
    };

    const content = JSON.stringify(data, null, 2);
    await this.writeFile(filePath, content);
  }

  private async writeFile(filePath: string, content: string): Promise<void> {
    try {
      const fd = await fileIo.open(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(fd.fd, content);
      } catch (err) {
        console.error('writeFile failed:', JSON.stringify(err));
        throw new Error(String(err));
      } finally {
        try {
          await fileIo.close(fd.fd);
        } catch (closeErr) {
          console.error('writeFile close failed:', JSON.stringify(closeErr));
        }
      }
    } catch (err) {
      console.error('writeFile open failed:', JSON.stringify(err));
      throw new Error(String(err));
    }
  }
}

export const datasetExportUtil = DatasetExportUtil.getInstance();
