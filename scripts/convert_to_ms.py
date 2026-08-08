#!/usr/bin/env python3
"""
Wrapper for MindSpore Lite converter (ONNX -> .ms).

Usage:
  python convert_to_ms.py --converter <path/to/converter_lite.exe> \
      --onnx models/onnx/albert_finetuned.onnx \
      --output models/albert_finetuned.ms [--quant INT8|WEIGHT|NONE]
"""
import argparse
import subprocess
import sys
from pathlib import Path


def convert(converter: Path, onnx: Path, output: Path, quant: str) -> int:
    cmd = [
        str(converter),
        '--fmk=ONNX',
        f'--modelFile={onnx}',
        f'--outputFile={output}',
    ]
    if quant.upper() == 'INT8':
        cmd.append('--quantType=INT8')
    elif quant.upper() == 'WEIGHT':
        cmd.append('--quantType=WEIGHT_QUANT')
    cmd.append('--optimizeModel=1')

    print('Running:', ' '.join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    if result.returncode != 0:
        print(f'Conversion failed (rc={result.returncode})')
        return result.returncode

    size_mb = output.stat().st_size / 1024 / 1024 if output.exists() else 0
    print(f'OK: {output} ({size_mb:.2f} MB)')
    if size_mb > 8:
        print('WARN: model exceeds 8 MB target')
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--converter', required=True,
                        help='Path to converter_lite.exe (e.g. mindspore-lite-*/tools/converter/converter/converter_lite.exe)')
    parser.add_argument('--onnx', default='models/onnx/albert_finetuned.onnx')
    parser.add_argument('--output', default='models/albert_finetuned.ms')
    parser.add_argument('--quant', default='INT8', choices=['INT8', 'WEIGHT', 'NONE'])
    args = parser.parse_args()

    converter = Path(args.converter)
    onnx = Path(args.onnx)
    output = Path(args.output)

    if not converter.exists():
        print(f'Error: converter not found: {converter}')
        sys.exit(1)
    if not onnx.exists():
        print(f'Error: ONNX not found: {onnx}')
        sys.exit(1)
    output.parent.mkdir(parents=True, exist_ok=True)
    sys.exit(convert(converter, onnx, output, args.quant))


if __name__ == '__main__':
    main()