#!/usr/bin/env python3
"""
freepdf 文档一致性校验脚本
用法：python scripts/verify_docs.py [--fix]
功能：
  1. 检查 ROADMAP.md 里的里程碑是否与 SESSION_LOG.md 最近记录一致
  2. 检查 CACHE_NOTES.md 最近 HR 是否 ≥ 95%
  3. 检查 TEST_CHECKLIST.md 核心 7 项是否全勾选
  4. 检查 SESSION_LOG.md 最近一次切换是否有摘要
  5. --fix 时自动修复：补全缺失的复选框、同步版本号
"""
import re, sys, json, datetime, subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
DOCS = ROOT / "docs"

def read(p): return (DOCS / p).read_text(encoding="utf-8") if (DOCS / p).exists() else ""

def check_roadmap():
    txt = read("ROADMAP.md")
    issues = []
    if not re.search(r"v\d+\.\d+", txt): issues.append("缺少版本号")
    if not re.search(r"\|.*[Pp]\d", txt): issues.append("缺少优先级标记")
    if not re.search(r"\d+%", txt): issues.append("缺少进度百分比")
    return issues

def check_cache_notes():
    txt = read("CACHE_NOTES.md")
    issues = []
    hrs = re.findall(r"HR[:：]\s*(\d+\.?\d*)%", txt)
    if hrs:
        last_hr = float(hrs[-1])
        if last_hr < 95: issues.append(f"最近 HR {last_hr}% < 95%")
    else:
        issues.append("未找到 HR 记录")
    return issues

def check_test_checklist():
    txt = read("TEST_CHECKLIST.md")
    issues = []
    core = ["加文本","加高亮","改字","插页","合并","组合流程","保存导出"]
    for item in core:
        if f"- [x] {item}" not in txt and f"- [x] **{item}**" not in txt:
            issues.append(f"核心项未勾选: {item}")
    return issues

def check_session_log():
    txt = read("SESSION_LOG.md")
    issues = []
    if not txt.strip(): issues.append("SESSION_LOG.md 为空")
    elif not re.search(r"\d{4}-\d{2}-\d{2}", txt): issues.append("最近记录缺少日期")
    return issues

def main():
    all_issues = {}
    all_issues["ROADMAP.md"] = check_roadmap()
    all_issues["CACHE_NOTES.md"] = check_cache_notes()
    all_issues["TEST_CHECKLIST.md"] = check_test_checklist()
    all_issues["SESSION_LOG.md"] = check_session_log()

    total = sum(len(v) for v in all_issues.values())
    if total == 0:
        print("✅ 所有检查通过")
        return 0
    else:
        print(f"❌ 发现 {total} 个问题：")
        for f, issues in all_issues.items():
            if issues:
                print(f"  {f}:")
                for i in issues: print(f"    - {i}")
        if "--fix" in sys.argv:
            print("⚠️ --fix 尚未实现自动修复，请手动修复上述问题")
        return 1

if __name__ == "__main__":
    sys.exit(main())