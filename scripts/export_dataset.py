#!/usr/bin/env python3
"""
Export and prepare training dataset from freepdf database.
Generates JSON with train/val splits and labels.json for ALBERT fine-tuning.
"""

import json
import random
from collections import defaultdict
from pathlib import Path
import argparse
import sqlite3

from data_utils import load_records

# Category mappings
EXPENSE_CATEGORIES = [
    '餐饮', '交通', '购物', '医疗', '娱乐', '居住', '通讯', '其他'
]
INCOME_CATEGORIES = [
    '工资', '理财', '其他'
]
ALL_CATEGORIES = EXPENSE_CATEGORIES + INCOME_CATEGORIES
MIN_CATEGORY_COUNT = 20

# Columns in freepdf_accounting.db `records` table (see utils/RecordDatabase.ets)
DB_COLUMNS = [
    'id', 'amount', 'type', 'category', 'note', 'merchant', 'timestamp',
    'dateStr', 'confidence', 'source', 'status', 'createdAt',
]

def load_from_db(db_path: Path) -> list:
    """Load CONFIRMED records straight from the app's SQLite database.

    Mirrors DatasetExportUtil.ets semantics: only status=1 (CONFIRMED),
    empty notes are dropped (no signal for the model), NULLs are coalesced.
    """
    if not Path(db_path).exists():
        raise FileNotFoundError(f'Database not found: {db_path}')

    conn = sqlite3.connect(f'file:{Path(db_path)}?mode=ro', uri=True)
    try:
        sql = (
            f'SELECT {", ".join(DB_COLUMNS)} FROM records '
            "WHERE status = 1 AND length(trim(note)) > 0 ORDER BY timestamp DESC"
        )
        rows = conn.execute(sql).fetchall()
        records = []
        for row in rows:
            row_map = dict(zip(DB_COLUMNS, row))
            source = row_map.get('source')
            if source not in ('pdf-text', 'pdf-ocr', 'img-ocr'):
                source = 'pdf-text'
            records.append({
                'id': row_map.get('id'),
                'text': row_map.get('note') or '',
                'category': row_map.get('category') or '其他',
                'type': row_map.get('type') or 'expense',
                'amount': row_map.get('amount') or 0.0,
                'merchant': row_map.get('merchant') or '',
                'source': source,
                'confidence': row_map.get('confidence') or 0.5,
                'timestamp': row_map.get('timestamp'),
                'dateStr': row_map.get('dateStr'),
            })
        return records
    finally:
        conn.close()


def load_dataset(source, from_db: bool = False) -> list:
    """Load records (JSON/JSONL file via load_records, or straight SQLite)."""
    if from_db:
        return load_from_db(source)
    return load_records(Path(source))

def categorize_record(record: dict) -> str:
    """Categorize a record based on its category field."""
    category = record.get('category', '其他')
    if category in ALL_CATEGORIES:
        return category
    return '其他'

def create_splits(records: list, train_ratio: float = 0.8, seed: int = 42):
    """Stratified train/val split. Categories with <20 records are kept fully in train."""
    random.seed(seed)
    MIN_PER_CATEGORY = 20

    by_category: dict = defaultdict(list)
    for record in records:
        by_category[categorize_record(record)].append(record)

    all_categories = sorted(by_category.keys())
    if all_categories and all_categories[-1] == '其他':
        all_categories.remove('其他')
        all_categories.append('其他')

    train_records = []
    val_records = []
    train_ids = set()
    val_ids = set()

    def rec_id(r):
        rid = r.get('id')
        if rid is None:
            return (r.get('text'), r.get('timestamp'))
        return rid

    for cat in all_categories:
        group = by_category[cat]
        random.shuffle(group)
        if len(group) < MIN_CATEGORY_COUNT:
            # Too few to leave an unseen test set: put all in train
            for r in group:
                train_records.append(r)
                train_ids.add(rec_id(r))
            continue
        split = max(1, int(len(group) * (1 - train_ratio)))
        # Ensure at least MIN_CATEGORY_COUNT in train when possible
        split = min(split, max(1, len(group) - MIN_CATEGORY_COUNT))
        for r in group[split:]:
            train_records.append(r)
            train_ids.add(rec_id(r))
        for r in group[:split]:
            val_records.append(r)
            val_ids.add(rec_id(r))

    # Any records skipped -> append to train
    for r in records:
        rid = rec_id(r)
        if rid not in train_ids and rid not in val_ids:
            train_records.append(r)
            train_ids.add(rid)

    random.shuffle(train_records)
    random.shuffle(val_records)
    return train_records, val_records

def create_label_mapping(records: list) -> dict:
    """Create label mapping for ALBERT tokenizer."""
    categories = set()
    for record in records:
        categories.add(categorize_record(record))

    # Create label mapping
    label_map = {cat: idx for idx, cat in enumerate(sorted(categories))}
    inv_label_map = {idx: cat for cat, idx in label_map.items()}

    return label_map, inv_label_map

def save_label_mapping(label_map: dict, output_path: Path):
    """Save label mapping (with invLabelMap for the on-device labels.json)."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    inv = {str(idx): cat for cat, idx in label_map.items()}
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump({
            'label_map': label_map,
            'inv_label_map': inv
        }, f, ensure_ascii=False, indent=2)

def save_dataset(records: list, output_path: Path, format: str = 'jsonl'):
    """Save dataset to file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if format == 'jsonl':
        with open(output_path, 'w', encoding='utf-8') as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
    elif format == 'json':
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(records, f, ensure_ascii=False, indent=2)

    print(f"Saved {len(records)} records to {output_path}")

def main():
    parser = argparse.ArgumentParser(description='Export and prepare training dataset')
    src = parser.add_mutually_exclusive_group()
    src.add_argument('--input', type=str, default=None,
                     help='Input JSON/JSONL file path')
    src.add_argument('--from-db', type=str, default=None, metavar='DB',
                     help='Read CONFIRMED records directly from the app SQLite database')
    parser.add_argument('--train', type=str, default='data/train.jsonl',
                       help='Output train split path')
    parser.add_argument('--val', type=str, default='data/val.jsonl',
                        help='Output val split path')
    parser.add_argument('--labels', type=str, default='data/labels.json',
                        help='Output label mapping path')
    parser.add_argument('--train-ratio', type=float, default=0.8,
                        help='Train split ratio (default: 0.8)')
    parser.add_argument('--seed', type=int, default=42,
                        help='Random seed for reproducibility')
    args = parser.parse_args()

    if args.from_db:
        input_path = Path(args.from_db)
        print(f"Loading records from database {input_path}...")
        try:
            records = load_dataset(input_path, from_db=True)
        except FileNotFoundError as e:
            print(f"Error: {e}")
            return
    else:
        if args.input is None:
            candidate = Path('freepdf_accounting.db')
            if candidate.exists():
                print(f'No --input/--from-db given; found {candidate}, reading database...')
                try:
                    records = load_dataset(candidate, from_db=True)
                except FileNotFoundError as e:
                    print(f"Error: {e}")
                    return
            else:
                print('Error: no --input/--from-db provided and no freepdf_accounting.db in cwd')
                return
        else:
            input_path = Path(args.input)
            if not input_path.exists():
                print(f'Error: Input file not found: {input_path}')
                return
            print(f"Loading records from {input_path}...")
            records = load_dataset(input_path)
    print(f"Loaded {len(records)} records")

    # Print category distribution
    by_category = defaultdict(int)
    for record in records:
        category = categorize_record(record)
        by_category[category] += 1

    print("\nCategory distribution:")
    for cat in sorted(by_category.keys()):
        print(f"  {cat}: {by_category[cat]}")

    # type × category cross distribution (note: '其他' is shared across expense/income)
    cross = defaultdict(int)
    for record in records:
        cross[(record.get('type', 'expense'), categorize_record(record))] += 1
    print("\nType × category cross distribution:")
    for type_name in ('expense', 'income'):
        for cat in sorted(by_category.keys()):
            count = cross[(type_name, cat)]
            if count:
                print(f"  {type_name:8s} {cat}: {count}")
    print("  Note: '其他' labels collapse across expense/income in model training.")

    # Create splits
    print(f"\nCreating train/val splits (train_ratio={args.train_ratio})...")
    train_records, val_records = create_splits(
        records,
        train_ratio=args.train_ratio,
        seed=args.seed
    )

    # Print split distribution
    print("\nTrain split distribution:")
    by_category = defaultdict(int)
    for record in train_records:
        category = categorize_record(record)
        by_category[category] += 1
    for cat in sorted(by_category.keys()):
        print(f"  {cat}: {by_category[cat]}")

    print("\nVal split distribution:")
    by_category = defaultdict(int)
    for record in val_records:
        category = categorize_record(record)
        by_category[category] += 1
    for cat in sorted(by_category.keys()):
        print(f"  {cat}: {by_category[cat]}")

    # Save splits
    print(f"\nSaving datasets...")
    save_dataset(train_records, Path(args.train), format='jsonl')
    save_dataset(val_records, Path(args.val), format='jsonl')

    # Create and save label mapping
    all_records = train_records + val_records
    label_map, _ = create_label_mapping(all_records)
    save_label_mapping(label_map, Path(args.labels))

    print(f"\n✓ Dataset preparation complete!")
    print(f"  - Train: {len(train_records)} records")
    print(f"  - Val: {len(val_records)} records")
    print(f"  - Labels: {len(label_map)} categories")

if __name__ == '__main__':
    main()
