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
    this.db = await relationalStore.getRdbStore(context, config);
  }

  async getAllRecords(): Promise<TrainingRecord[]> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `SELECT * FROM ${TABLE_NAME} WHERE status = ? ORDER BY timestamp DESC`;
    const args: Array<relationalStore.ValueType> = [RecordStatus.CONFIRMED];
    const resultSet = await this.db.querySql(sql, args);

    const records: TrainingRecord[] = [];
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
          merchant: merchantValue.trim().length > 0 ? merchantValue : undefined,
          source: resultSet.getString(sourceIdx) as RecordSource,
          timestamp: resultSet.getLong(timestampIdx),
          dateStr: resultSet.getString(dateStrIdx),
          confidence: resultSet.getDouble(confidenceIdx)
        });
      }
    } finally {
      resultSet.close();
    }
    return records;
  }

  async exportToJSON(filePath: string, records: TrainingRecord[]): Promise<void> {
    const data = {
      version: '1.0',
      exportDate: new Date().toISOString(),
      recordCount: records.length,
      records: records.map(r => ({
        text: r.text,
        category: r.category,
        type: r.type,
        amount: r.amount,
        merchant: r.merchant || '',
        source: r.source,
        confidence: r.confidence
      }))
    };

    const content = JSON.stringify(data, null, 2);
    await this.writeFile(filePath, content);
  }

  private async writeFile(filePath: string, content: string): Promise<void> {
    const fd = await fileIo.open(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(fd.fd, content);
    } finally {
      await fileIo.close(fd.fd);
    }
  }
}

export const datasetExportUtil = DatasetExportUtil.getInstance();
