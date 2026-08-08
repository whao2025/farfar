#!/usr/bin/env python3
"""
Fine-tune ALBERT-tiny-Chinese for bookkeeping categorization.
Produces ONNX model for MindSporeLite conversion.

Requirements:
  pip install torch transformers datasets accelerate
Model: voidful/albert_chinese_tiny (~4M params, Apache-2.0)
"""

import json
import argparse
from pathlib import Path

import torch
from torch.utils.data import Dataset
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    TrainingArguments,
    Trainer,
)

# Runtime constants (overridable via CLI)
MAX_LENGTH = 128
BATCH_SIZE = 16
LEARNING_RATE = 2e-5

CATEGORIES = [
    '餐饮', '交通', '购物', '医疗', '娱乐', '居住', '通讯', '其他',
    '工资', '理财', '其他收入',
]


class BookkeepingDataset(Dataset):

    def __init__(self, records: list, label_ids: dict, tokenizer, max_length: int = MAX_LENGTH):
        self.records = records
        self.label_ids = label_ids
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx: int):
        record = self.records[idx]
        text = record['text']
        category = record['category']
        label = self.label_ids.get(category, self.label_ids['其他']) if category in self.label_ids else self.label_ids['其他']
        if category in self.label_ids:
            label = self.label_ids[category]
        else:
            label = self.label_ids['其他']
        encoding = self.tokenizer(
            text,
            max_length=self.max_length,
            padding='max_length',
            truncation=True,
            return_tensors='pt',
        )
        return {
            'input_ids': encoding['input_ids'].squeeze(0),
            'attention_mask': encoding['attention_mask'].squeeze(0),
            'labels': torch.tensor(label, dtype=torch.long),
        }


def load_records(path: Path) -> list:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    # Accept {version, records: [...]} wrapper or bare array
    if isinstance(data, dict):
        return data['records']
    return data


def compute_metrics(eval_pred):
    logits, labels = eval_pred
    predictions = logits.argmax(axis=-1)
    correct = sum(1 for p, l in zip(predictions, labels) if p == l)
    return {'accuracy': correct / max(len(labels), 1)}


def main():
    parser = argparse.ArgumentParser(description='Fine-tune ALBERT for bookkeeping')
    parser.add_argument('--train', type=str, default='data/train.jsonl')
    parser.add_argument('--val', type=str, default='data/val.jsonl')
    parser.add_argument('--labels', type=str, default='data/labels.json')
    parser.add_argument('--model', type=str, default='voidful/albert_chinese_tiny')
    parser.add_argument('--output-dir', type=str, default='models/albert_finetuned')
    parser.add_argument('--onnx-dir', type=str, default='models/onnx')
    parser.add_argument('--epochs', type=int, default=3)
    parser.add_argument('--batch-size', type=int, default=16)
    parser.add_argument('--lr', type=float, default=2e-5)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    onnx_dir = Path(args.onnx_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    onnx_dir.mkdir(parents=True, exist_ok=True)

    # ---- Load labels ----
    with open(args.labels, 'r', encoding='utf-8') as f:
        label_config = json.load(f)
    label_map = label_config['label_map']          # {category: idx}
    inv_label_map = label_config['inv_label_map']  # {idx: category}
    labels_dir = output_dir / 'labels.json'
    with open(labels_dir, 'w', encoding='utf-8') as f:
        json.dump({'label_map': label_map, 'invLabelMap': inv_label_map}, f, ensure_ascii=False, indent=2)

    # ---- Load data ----
    train_records = load_records(args.train)
    val_records = load_records(args.val)
    print(f'Load train={len(train_records)} val={len(val_records)} labels={len(label_map)}')

    # ---- Tokenizer ----
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    tokenizer.save_pretrained(str(output_dir))

    # ---- Dataset ----
    train_ds = BookkeepingDataset(train_records, label_map, tokenizer)
    val_ds = BookkeepingDataset(val_records, label_map, tokenizer)

    # ---- Model ----
    use_cuda = torch.cuda.is_available()
    if not use_cuda:
        num_labels = len(label_map)
    else:
        num_labels = len(label_map)
    model = AutoModelForSequenceClassification.from_pretrained(
        args.model,
        num_labels=num_labels,
    )

    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size,
        warmup_ratio=0.1,
        weight_decay=0.01,
        logging_dir=str(output_dir / 'logs'),
        logging_steps=10,
        save_steps=500,
        eval_strategy='epoch',
        save_strategy='epoch',
        learning_rate=args.lr,
        fp16=use_cuda,
        load_best_model_at_end=True,
        metric_for_best_model='eval_accuracy',
        greater_is_better=True,
        report_to='none',
        save_total_limit=2,
        seed=42,
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_ds,
        eval_dataset=val_ds,
        compute_metrics=compute_metrics,
    )

    trainer.train()
    metrics = trainer.evaluate()
    print(f'\nValidation: {metrics}')

    # Save final model + tokenizer
    trainer.save_model(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))

    # ---- Export to ONNX ----
    onnx_path = onnx_dir / 'albert_finetuned.onnx'
    model.eval()
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model.to(device)
    dummy_input_ids = torch.randint(0, 21128, (1, MAX_LENGTH), dtype=torch.int32).to(device)
    dummy_attention_mask = torch.ones(1, MAX_LENGTH, dtype=torch.int32).to(device)

    with torch.no_grad():
        torch.onnx.export(
            model,
            (dummy_input_ids, dummy_attention_mask),
            str(onnx_path),
            input_names=['input_ids', 'attention_mask'],
            output_names=['logits'],
            dynamic_axes={
                'input_ids': {1: 'sequence_length'},
                'attention_mask': {1: 'sequence_length'},
                'logits': {0: 'batch'},
            },
            opset_version=14,
            do_constant_folding=True,
        )

    print(f'ONNX exported: {onnx_path} ({onnx_path.stat().st_size / 1024 / 1024:.2f} MB)')


if __name__ == '__main__':
    main()