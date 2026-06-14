#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
import tempfile
from pathlib import Path
from statistics import mean
import sys

WORK_ROOT = Path(r"D:\霍子衿\gpt\实验")
ZIJIN_SCRIPTS = Path(r"D:\zijin\scripts")
sys.path.insert(0, str(WORK_ROOT))
sys.path.insert(0, str(ZIJIN_SCRIPTS))

import fixed_index_rule_compare as base  # type: ignore
from fe_ref import pack_bits  # type: ignore
from fe_codeoffset_ref import fe_gen as b4_fe_gen, fe_rep as b4_fe_rep  # type: ignore
from fe_bch31_ref import fe_gen as bch_fe_gen, fe_rep as bch_fe_rep  # type: ignore
from puf_to_kdf_pipeline import protocol_round  # type: ignore

PROFILE_DIR = Path(r"D:\zijin\results\device_profile\v4_noise_w2_p20")
RAW_CSV = Path(r"D:\zijin\results\apuf64_capture_2026-05-24_v7_noise_w2_p35_seed4_c8_n2048_r16.csv")
ENHANCED_CSV = Path(r"D:\zijin\results\apuf64_enhanced_capture_2026-05-24_v3_enhanced_noise_w2_p35_seed4_c8_n2048_r16.csv")
OUT_ROOT = Path(r"D:\zijin\results\fixed_index_unified_samecaliber_seed4_fast2_2026-06-06")
TOP_K = 256

RULE_ORDER = [
    ("score_only", "稳定性 Top-K"),
    ("balanced_per_device", "稳定性+均衡"),
    ("cross_condition", "跨噪声一致性"),
    ("recovery_oriented", "根密钥恢复导向规则"),
]

MODES = {
    "raw_uniform1": {"display": "raw 单次采样", "budgets": None},
    "enhanced_tier3716": {"display": "enhanced 分层采样", "budgets": {"A": 3, "B": 7, "C": 16}},
    "enhanced_uniform3": {"display": "enhanced 统一3次采样", "budgets": {"A": 3, "B": 3, "C": 3}},
}


def parse_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def normalize_challenge(value: str) -> str:
    text = value.strip().upper()
    if text.startswith("0X"):
        text = text[2:]
    return text.zfill(16)


def load_enhanced_valid(path: Path) -> dict[str, dict[str, tuple[int, ...]]]:
    out: dict[str, dict[str, list[int]]] = {}
    for row in parse_csv(path):
        if int(row["valid"]) != 1:
            continue
        device_id = f"device_{int(row['chip_id']):03d}"
        challenge = normalize_challenge(row["challenge_hex"])
        out.setdefault(device_id, {}).setdefault(challenge, []).append(int(row["response"]))
    return {device: {challenge: tuple(vals) for challenge, vals in challenge_map.items()} for device, challenge_map in out.items()}


def majority(samples: tuple[int, ...], budget: int) -> int:
    used = list(samples[: max(1, min(budget, len(samples)))])
    ones = sum(used)
    zeros = len(used) - ones
    if ones > zeros:
        return 1
    if zeros > ones:
        return 0
    return used[0]


def deterministic_salt(tag: str, device_id: str) -> bytes:
    return hashlib.sha256(f"{tag}:{device_id}".encode("utf-8")).digest()[:16]


def write_bits(bits_path: Path, mask_path: Path, bits: list[int], mask: list[int]) -> None:
    bits_path.parent.mkdir(parents=True, exist_ok=True)
    bits_path.write_bytes(pack_bits(bits))
    mask_path.write_bytes(pack_bits(mask))


def select_cross_condition(rows: list[dict[str, object]], raw_stats_for_device: dict[str, base.RawStats], top_k: int) -> list[dict[str, object]]:
    enriched = []
    for row in rows:
        challenge = str(row["challenge_hex"])
        stats = raw_stats_for_device[challenge]
        enroll_rel = float(row["mean_reliability"])
        validate_rel = stats.reliability
        cross_match = 1 if int(row["reference_response"]) == stats.reference else 0
        min_rel = min(enroll_rel, validate_rel)
        enriched.append(
            {
                **row,
                "validate_reliability": validate_rel,
                "cross_match": cross_match,
                "min_reliability_cross_condition": min_rel,
            }
        )
    enriched.sort(
        key=lambda item: (
            -float(item["min_reliability_cross_condition"]),
            -int(item["cross_match"]),
            -float(item["validate_reliability"]),
            -float(item["mean_reliability"]),
            str(item["challenge_hex"]),
        )
    )
    return enriched[:top_k]


def build_rule_maps(profiles, raw_stats):
    return {
        "score_only": {device_id: base.select_score_only(rows, TOP_K) for device_id, rows in profiles.items()},
        "balanced_per_device": {device_id: base.select_balanced(rows, TOP_K) for device_id, rows in profiles.items()},
        "cross_condition": {device_id: select_cross_condition(rows, raw_stats[device_id], TOP_K) for device_id, rows in profiles.items()},
        "recovery_oriented": {device_id: base.select_recovery_oriented(rows, raw_stats[device_id], TOP_K) for device_id, rows in profiles.items()},
    }


def summarize_material(rule_name: str, selected_map, raw_stats):
    per_device = []
    for device_id, rows in selected_map.items():
        refs = [int(row["reference_response"]) for row in rows]
        enroll_rels = [float(row["mean_reliability"]) for row in rows]
        validate_rels = [raw_stats[device_id][str(row["challenge_hex"])].reliability for row in rows]
        min_cross_rels = [min(a, b) for a, b in zip(enroll_rels, validate_rels)]
        per_device.append(
            {
                "device_id": device_id,
                "uniformity": sum(refs) / len(refs),
                "enroll_reliability_mean": mean(enroll_rels),
                "validate_reliability_mean": mean(validate_rels),
                "cross_condition_min_reliability_mean": mean(min_cross_rels),
            }
        )
    return {
        "rule_name": rule_name,
        "uniformity_mean": mean(item["uniformity"] for item in per_device),
        "enroll_reliability_mean": mean(item["enroll_reliability_mean"] for item in per_device),
        "validate_reliability_mean": mean(item["validate_reliability_mean"] for item in per_device),
        "cross_condition_min_reliability_mean": mean(item["cross_condition_min_reliability_mean"] for item in per_device),
        "per_device": per_device,
    }


def precompute_helpers(tmp_root: Path, rule_maps):
    helper_cache = {}
    for rule_key, _ in RULE_ORDER:
        helper_cache[rule_key] = {}
        for device_id, rows in rule_maps[rule_key].items():
            enroll_bits = [int(row["reference_response"]) for row in rows]
            enroll_mask = [1] * len(enroll_bits)
            dev_dir = tmp_root / "enroll" / rule_key / device_id
            enroll_bits_path = dev_dir / f"{device_id}_enroll_bits.bin"
            enroll_mask_path = dev_dir / f"{device_id}_enroll_mask.bin"
            write_bits(enroll_bits_path, enroll_mask_path, enroll_bits, enroll_mask)
            b4_key_bytes = 16
            b4_gen = b4_fe_gen(
                device_id=device_id,
                stable_bits_path=enroll_bits_path,
                mask_path=enroll_mask_path,
                block_size=4,
                key_bytes=b4_key_bytes,
                salt=deterministic_salt(f"{rule_key}:b4", device_id),
                bit_length=len(enroll_bits),
            )
            bch_gen = bch_fe_gen(
                device_id=device_id,
                stable_bits_path=enroll_bits_path,
                mask_path=enroll_mask_path,
                key_bytes=16,
                salt=deterministic_salt(f"{rule_key}:bch31", device_id),
                bit_length=len(enroll_bits),
            )
            helper_cache[rule_key][device_id] = {
                "rows": rows,
                "enroll_bits": enroll_bits,
                "b4_helper": b4_gen.helper,
                "b4_key": b4_gen.key,
                "bch_helper": bch_gen.helper,
                "bch_key": bch_gen.key,
            }
    return helper_cache


def verify_protocol_equivalence(helper_cache):
    checked = []
    for rule_key, _ in RULE_ORDER:
        device_id = sorted(helper_cache[rule_key].keys())[0]
        item = helper_cache[rule_key][device_id]
        proto_b4 = protocol_round(device_id, item["b4_key"], item["b4_key"], round_index=0, out_bytes=16)
        proto_bch = protocol_round(device_id, item["bch_key"], item["bch_key"], round_index=0, out_bytes=16)
        if not (proto_b4["K_match"] and proto_b4["R_virtual_match"] and proto_b4["SK_match"] and proto_b4["device_auth_ok"] and proto_b4["server_auth_ok"]):
            raise RuntimeError(f"B4 protocol equivalence failed for {rule_key}/{device_id}")
        if not (proto_bch["K_match"] and proto_bch["R_virtual_match"] and proto_bch["SK_match"] and proto_bch["device_auth_ok"] and proto_bch["server_auth_ok"]):
            raise RuntimeError(f"BCH protocol equivalence failed for {rule_key}/{device_id}")
        checked.append({"rule_key": rule_key, "device_id": device_id})
    return checked


def evaluate_mode(rule_key: str, helper_cache, raw_stats, enhanced_valid, mode_name: str, mode_cfg: dict[str, object], tmp_root: Path):
    bit_errors = 0
    total_bits = 0
    total_budget = 0
    zero_error_devices = 0
    b4_ok = 0
    bch_ok = 0
    per_device = []
    budgets = mode_cfg["budgets"]

    for device_id, item in helper_cache[rule_key].items():
        rows = item["rows"]
        enroll_bits = item["enroll_bits"]
        online_bits = []
        online_mask = [1] * len(enroll_bits)
        device_budget = 0
        for row in rows:
            challenge = str(row["challenge_hex"])
            if mode_name == "raw_uniform1":
                bit = raw_stats[device_id][challenge].samples[0]
                device_budget += 1
            else:
                tier = base.confidence_tier(raw_stats[device_id][challenge].reliability)
                budget = budgets[tier]
                bit = majority(enhanced_valid[device_id][challenge], budget)
                device_budget += min(budget, len(enhanced_valid[device_id][challenge]))
            online_bits.append(bit)

        device_bit_errors = sum(1 for a, b in zip(enroll_bits, online_bits) if a != b)
        if device_bit_errors == 0:
            zero_error_devices += 1
        bit_errors += device_bit_errors
        total_bits += len(enroll_bits)
        total_budget += device_budget

        dev_dir = tmp_root / mode_name / rule_key / device_id
        online_bits_path = dev_dir / f"{device_id}_online_bits.bin"
        online_mask_path = dev_dir / f"{device_id}_online_mask.bin"
        write_bits(online_bits_path, online_mask_path, online_bits, online_mask)

        b4_rep = b4_fe_rep(item["b4_helper"], online_bits_path, online_mask_path)
        if b4_rep.success and b4_rep.key == item["b4_key"]:
            b4_ok += 1
        bch_rep = bch_fe_rep(item["bch_helper"], online_bits_path, online_mask_path)
        if bch_rep.success and bch_rep.key == item["bch_key"]:
            bch_ok += 1

        per_device.append({
            "device_id": device_id,
            "bit_errors": device_bit_errors,
            "avg_budget_per_bit": device_budget / len(enroll_bits),
            "b4_ok": b4_rep.success and b4_rep.key == item["b4_key"],
            "bch31_ok": bch_rep.success and bch_rep.key == item["bch_key"],
        })

    return {
        "rule_name": rule_key,
        "mode_name": mode_name,
        "mode_display": str(mode_cfg["display"]),
        "bit_errors": bit_errors,
        "bit_error_rate": bit_errors / total_bits,
        "zero_error_devices": zero_error_devices,
        "avg_budget_per_bit": total_budget / total_bits,
        "b4_recovery_ok": b4_ok,
        "bch31_recovery_ok": bch_ok,
        "b4_protocol_ok": b4_ok,
        "bch31_protocol_ok": bch_ok,
        "per_device": per_device,
    }


def build_summary_csv(material_summary, mode_results):
    rows = []
    for rule_key, rule_display in RULE_ORDER:
        base_row = {
            "rule_key": rule_key,
            "rule_display": rule_display,
            "uniformity_mean": material_summary[rule_key]["uniformity_mean"],
            "enroll_reliability_mean": material_summary[rule_key]["enroll_reliability_mean"],
            "validate_reliability_mean": material_summary[rule_key]["validate_reliability_mean"],
            "cross_condition_min_reliability_mean": material_summary[rule_key]["cross_condition_min_reliability_mean"],
        }
        for mode_name in MODES:
            item = mode_results[mode_name][rule_key]
            row = dict(base_row)
            row.update(
                {
                    "mode_name": mode_name,
                    "mode_display": item["mode_display"],
                    "bit_errors": item["bit_errors"],
                    "bit_error_rate": item["bit_error_rate"],
                    "zero_error_devices": item["zero_error_devices"],
                    "avg_budget_per_bit": item["avg_budget_per_bit"],
                    "b4_recovery_ok": item["b4_recovery_ok"],
                    "bch31_recovery_ok": item["bch31_recovery_ok"],
                    "b4_protocol_ok": item["b4_protocol_ok"],
                    "bch31_protocol_ok": item["bch31_protocol_ok"],
                }
            )
            rows.append(row)
    return rows


def write_outputs(material_summary, mode_results, protocol_equiv_checked):
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    summary = {
        "profile_dir": str(PROFILE_DIR),
        "raw_csv": str(RAW_CSV),
        "enhanced_csv": str(ENHANCED_CSV),
        "top_k": TOP_K,
        "rules": {key: display for key, display in RULE_ORDER},
        "protocol_equivalence_checked": protocol_equiv_checked,
        "material_summary": material_summary,
        "mode_results": mode_results,
    }
    (OUT_ROOT / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    csv_rows = build_summary_csv(material_summary, mode_results)
    with (OUT_ROOT / "summary.csv").open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=list(csv_rows[0].keys()))
        writer.writeheader()
        writer.writerows(csv_rows)
    md_lines = [
        "# 固定索引统一脚本重跑结果（seed4, fast2, 2026-06-06）",
        "",
        "- 说明：这是一轮统一脚本重跑版，用同一 profile、同一 raw 验证数据、同一 enhanced 验证数据，对四类规则一次性并排比较。",
        "- 优化点：协议成功列采用 `FE恢复成功 => 协议成功` 的等价判定，并对每类规则做了 spot-check 验证。",
        "- 边界：这仍然是离线数据重跑，不是真实 PUF 多板多温最终实测。",
        "",
        "## 材料层指标",
        "",
        "| 规则 | 均衡性均值 | 注册稳定性均值 | 验证稳定性均值 | 跨条件最小稳定性均值 |",
        "|---|---:|---:|---:|---:|",
    ]
    for rule_key, rule_display in RULE_ORDER:
        item = material_summary[rule_key]
        md_lines.append(f"| {rule_display} | {item['uniformity_mean']:.12f} | {item['enroll_reliability_mean']:.12f} | {item['validate_reliability_mean']:.12f} | {item['cross_condition_min_reliability_mean']:.12f} |")
    md_lines.extend(["", "## 模式结果", ""])
    for mode_name, mode_cfg in MODES.items():
        md_lines.extend([
            f"### {mode_cfg['display']}",
            "",
            "| 规则 | bit errors | BER | 零错误设备数 | 平均采样预算/bit | B4恢复 | BCH31恢复 | 协议成功(B4/BCH31) |",
            "|---|---:|---:|---:|---:|---:|---:|---|",
        ])
        for rule_key, rule_display in RULE_ORDER:
            item = mode_results[mode_name][rule_key]
            md_lines.append(f"| {rule_display} | {item['bit_errors']} | {item['bit_error_rate']:.12f} | {item['zero_error_devices']} | {item['avg_budget_per_bit']:.6f} | {item['b4_recovery_ok']}/8 | {item['bch31_recovery_ok']}/8 | {item['b4_protocol_ok']}/8, {item['bch31_protocol_ok']}/8 |")
        md_lines.append("")
    (OUT_ROOT / "summary.md").write_text("\n".join(md_lines).rstrip() + "\n", encoding="utf-8")


def main() -> None:
    profiles = base.load_profiles(PROFILE_DIR)
    raw_stats = base.load_raw_stats(RAW_CSV)
    enhanced_valid = load_enhanced_valid(ENHANCED_CSV)
    rule_maps = build_rule_maps(profiles, raw_stats)
    material_summary = {rule_key: summarize_material(rule_key, rule_maps[rule_key], raw_stats) for rule_key, _ in RULE_ORDER}
    with tempfile.TemporaryDirectory(prefix="fixed_index_unified_fast2_") as tmp:
        tmp_root = Path(tmp)
        helper_cache = precompute_helpers(tmp_root, rule_maps)
        protocol_equiv_checked = verify_protocol_equivalence(helper_cache)
        mode_results = {
            mode_name: {
                rule_key: evaluate_mode(rule_key, helper_cache, raw_stats, enhanced_valid, mode_name, mode_cfg, tmp_root)
                for rule_key, _ in RULE_ORDER
            }
            for mode_name, mode_cfg in MODES.items()
        }
    write_outputs(material_summary, mode_results, protocol_equiv_checked)
    print((OUT_ROOT / "summary.md").as_posix())


if __name__ == "__main__":
    main()