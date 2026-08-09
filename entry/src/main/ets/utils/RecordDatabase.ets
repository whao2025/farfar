import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BookkeepingRecord, RecordStatus, RecordType, RecordSource } from '../model/RecordModel';

const DB_NAME = 'freepdf_accounting.db';
const TABLE_NAME = 'records';

export class RecordDatabase {
  private db: relationalStore.RdbStore | null = null;
  private static instance: RecordDatabase | null = null;

  private constructor() {}

  static getInstance(): RecordDatabase {
    if (!RecordDatabase.instance) {
      RecordDatabase.instance = new RecordDatabase();
    }
    return RecordDatabase.instance;
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
      console.error('getRdbStore failed:', JSON.stringify(err));
      this.db = null;
      throw new Error(String(err));
    }

    try {
      await this.createTable();
      await this.createIndexes();
    } catch (err) {
      console.error('RecordDatabase init failed:', JSON.stringify(err));
      this.db = null;
      throw new Error(String(err));
    }
  }

  private async createTable(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `
      CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '其他',
        note TEXT NOT NULL,
        merchant TEXT,
        timestamp INTEGER NOT NULL,
        dateStr TEXT NOT NULL,
        confidence REAL DEFAULT 0.5,
        source TEXT NOT NULL,
        status INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL
      );
`;
    try {
      await this.db.executeSql(sql);
    } catch (err) {
      throw new Error(String(err));
    }
  }

  private async createIndexes(): Promise<void> {
    if (!this.db) return;

    const indexes = [
      `CREATE INDEX IF NOT EXISTS idx_date ON ${TABLE_NAME}(dateStr);`,
      `CREATE INDEX IF NOT EXISTS idx_timestamp ON ${TABLE_NAME}(timestamp);`,
      `CREATE INDEX IF NOT EXISTS idx_source ON ${TABLE_NAME}(source);`,
      `CREATE INDEX IF NOT EXISTS idx_status ON ${TABLE_NAME}(status);`,
      `CREATE INDEX IF NOT EXISTS idx_date_type ON ${TABLE_NAME}(dateStr, type);`
    ];

    for (const sql of indexes) {
      try {
        await this.db.executeSql(sql);
      } catch (err) {
        throw new Error(String(err));
      }
    }
  }

  async insert(record: BookkeepingRecord): Promise<number> {
    if (!this.db) throw new Error('Database not initialized');

    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      amount: record.amount,
      type: record.type,
      category: record.category,
      note: record.note,
      merchant: record.merchant ?? null,
      timestamp: record.timestamp ?? now,
      dateStr: record.dateStr,
      confidence: record.confidence ?? 0.5,
      source: record.source,
      status: record.status ?? RecordStatus.CONFIRMED,
      createdAt: record.createdAt ?? now
    };

    try {
      const id = await this.db.insert(TABLE_NAME, bucket);
      return id;
    } catch (err) {
      console.error('Insert failed:', err);
      throw new Error(String(err));
    }
  }

  async batchInsert(records: BookkeepingRecord[]): Promise<number[]> {
    if (!this.db) throw new Error('Database not initialized');

    let tx: relationalStore.Transaction | null = null;
    const ids: number[] = [];
    try {
      tx = await this.db.createTransaction();
      for (const record of records) {
        const id = await this.insert(record);
        ids.push(id);
      }
      await tx.commit();
    } catch (err) {
      if (tx) {
        try {
          await tx.rollback();
        } catch (rollbackErr) {
          console.error('Rollback failed:', JSON.stringify(rollbackErr));
        }
      }
      throw new Error(String(err));
    }
    return ids;
  }

  async getAll(status?: RecordStatus): Promise<BookkeepingRecord[]> {
    if (!this.db) throw new Error('Database not initialized');

    let sql = `SELECT * FROM ${TABLE_NAME}`;
    const args: Array<relationalStore.ValueType> = [];
    if (typeof status !== 'undefined') {
      sql += ` WHERE status = ?`;
      args.push(status as number);
    }
    sql += ' ORDER BY timestamp DESC';

    return this.queryRecords(sql, args);
  }

  async getByDateRange(startDate: string, endDate: string): Promise<BookkeepingRecord[]> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `SELECT * FROM ${TABLE_NAME} WHERE dateStr >= ? AND dateStr <= ? AND status != ? ORDER BY timestamp DESC`;
    const args: Array<relationalStore.ValueType> = [startDate, endDate, RecordStatus.DELETED as number];
    return this.queryRecords(sql, args);
  }

  async getByCategory(category: string, startDate?: string, endDate?: string): Promise<BookkeepingRecord[]> {
    if (!this.db) throw new Error('Database not initialized');

    let sql = `SELECT * FROM ${TABLE_NAME} WHERE category = ? AND status != ?`;
    const args: Array<relationalStore.ValueType> = [category, RecordStatus.DELETED as number];

    if (startDate && endDate) {
      sql += ' AND dateStr >= ? AND dateStr <= ?';
      args.push(startDate);
      args.push(endDate);
    }

    sql += ' ORDER BY timestamp DESC';
    return this.queryRecords(sql, args);
  }

  async getWeeklyStats(startDate: string, endDate: string): Promise<DailyStat[]> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `
      SELECT dateStr, SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as totalExpense,
             SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as totalIncome
      FROM ${TABLE_NAME}
      WHERE dateStr >= ? AND dateStr <= ? AND status != ?
      GROUP BY dateStr
      ORDER BY dateStr ASC
    `;
    const args: Array<relationalStore.ValueType> = [startDate, endDate, RecordStatus.DELETED as number];
    const stats: DailyStat[] = [];
    try {
      const resultSet = await this.db.querySql(sql, args);
      try {
        while (resultSet.goToNextRow()) {
          const dateStrIdx = resultSet.getColumnIndex('dateStr');
          const expIdx = resultSet.getColumnIndex('totalExpense');
          const incIdx = resultSet.getColumnIndex('totalIncome');
          stats.push({
            dateStr: resultSet.getString(dateStrIdx),
            expense: resultSet.getDouble(expIdx),
            income: resultSet.getDouble(incIdx)
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
      console.error('getWeeklyStats failed:', JSON.stringify(err));
    }
    return stats;
  }

  async getMonthlyTotals(month: string): Promise<MonthTotal> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `
      SELECT SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as totalExpense,
             SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as totalIncome
      FROM ${TABLE_NAME}
      WHERE dateStr LIKE ? AND status != ?
    `;
    const prefix = month.substring(0, 7) + '%';
    const args: Array<relationalStore.ValueType> = [prefix, RecordStatus.DELETED as number];

    const result: MonthTotal = { expense: 0, income: 0 };
    try {
      const resultSet = await this.db.querySql(sql, args);
      try {
        if (resultSet.goToNextRow()) {
          const expIdx = resultSet.getColumnIndex('totalExpense');
          const incIdx = resultSet.getColumnIndex('totalIncome');
          result.expense = resultSet.getDouble(expIdx);
          result.income = resultSet.getDouble(incIdx);
        }
      } finally {
        try {
          resultSet.close();
        } catch (closeErr) {
          console.error('resultSet close failed:', JSON.stringify(closeErr));
        }
      }
    } catch (err) {
      console.error('getMonthlyTotals failed:', JSON.stringify(err));
    }
    return result;
  }

  async update(record: BookkeepingRecord): Promise<number> {
    if (!this.db) throw new Error('Database not initialized');
    if (record.id === null) throw new Error('Cannot update record without id');

    const bucket: relationalStore.ValuesBucket = {
      amount: record.amount,
      type: record.type,
      category: record.category,
      note: record.note,
      merchant: record.merchant ?? null,
      timestamp: record.timestamp,
      dateStr: record.dateStr,
      confidence: record.confidence,
      status: record.status
    };

    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', record.id);
      const rows = await this.db.update(bucket, predicates);
      return rows;
    } catch (err) {
      console.error('Update failed:', err);
      throw new Error(String(err));
    }
  }

  async updateStatus(id: number, status: RecordStatus): Promise<number> {
    if (!this.db) throw new Error('Database not initialized');

    const bucket: relationalStore.ValuesBucket = { status: status as number };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    try {
      return await this.db.update(bucket, predicates);
    } catch (err) {
      console.error('UpdateStatus failed:', JSON.stringify(err));
      throw new Error(String(err));
    }
  }

  async delete(id: number, hardDelete: boolean = false): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    if (hardDelete) {
      const sql = `DELETE FROM ${TABLE_NAME} WHERE id = ?`;
      try {
        await this.db.executeSql(sql, [id]);
      } catch (err) {
        console.error('Delete failed:', JSON.stringify(err));
        throw new Error(String(err));
      }
    } else {
      await this.updateStatus(id, RecordStatus.DELETED);
    }
  }

  async clearAll(): Promise<void> {
    if (!this.db) throw new Error('Database not initialized');

    const sql = `DELETE FROM ${TABLE_NAME}`;
    try {
      await this.db.executeSql(sql);
    } catch (err) {
      console.error('ClearAll failed:', JSON.stringify(err));
      throw new Error(String(err));
    }
  }

  async close(): Promise<void> {
    if (this.db) {
      try {
        await this.db.close();
      } catch (err) {
        console.error('RecordDatabase close failed:', JSON.stringify(err));
      }
      this.db = null;
    }
  }

  private async queryRecords(sql: string, args: Array<relationalStore.ValueType>): Promise<BookkeepingRecord[]> {
    if (!this.db) throw new Error('Database not initialized');

    const records: BookkeepingRecord[] = [];
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
          const statusIdx = resultSet.getColumnIndex('status');
          const createdAtIdx = resultSet.getColumnIndex('createdAt');

          const merchantValue = resultSet.getString(merchantIdx);
          records.push({
            id: resultSet.getLong(idIdx),
            amount: resultSet.getDouble(amountIdx),
            type: resultSet.getString(typeIdx) as RecordType,
            category: resultSet.getString(categoryIdx),
            note: resultSet.getString(noteIdx),
            merchant: merchantValue.trim().length > 0 ? merchantValue : null,
            timestamp: resultSet.getLong(timestampIdx),
            dateStr: resultSet.getString(dateStrIdx),
            confidence: resultSet.getDouble(confidenceIdx),
            source: resultSet.getString(sourceIdx) as RecordSource,
            status: resultSet.getLong(statusIdx) as RecordStatus,
            createdAt: resultSet.getLong(createdAtIdx)
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
      console.error('queryRecords failed:', JSON.stringify(err));
    }
    return records;
  }
}

export interface DailyStat {
  dateStr: string;
  expense: number;
  income: number;
}

export interface MonthTotal {
  expense: number;
  income: number;
}

export const recordDb = RecordDatabase.getInstance();