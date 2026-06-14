#!/usr/bin/env python3
"""Analyze real PUF sampling CSV files.

This script is intended for post-sampling offline statistics. It keeps three
metric layers separate:
1. raw PUF metrics (uniformity, reliability, raw BER)
2. selected response material metrics (common-set uniqueness / selected response diversity, bit-aliasing)
3. post-processing / authentication metrics (aggregate BER, FE recovery success rate, auth success rate)

It does not prove security, does not replace NIST, and does not turn 3–5 board
results into large-scale chip statistics.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path
from statistics import mean
from typing import Iterable


VALID_SELECTION_MODES = {
    "global_shared",
    "common_challenge",
    "per_device_bestidx",
    "per_device_rom",
    "unknown",
}


@dataclass(frozen=True)
class RawRow:
    board_id: str
    session_id: str
    temperature_label: str
    supply_label: str
    selection_mode: str
    challenge_key: str
    challenge_hex: str
    repeat_index: int
    raw_resp_bit: int
    raw_resp_valid: int
    reference_resp_bit: int | None


@dataclass(frozen=True)
class AggregateBit:
    board_id: str
    challenge_key: str
    challenge_hex: str
    selection_mode: str
    aggregate_bit: int
    reference_bit: int | None
    reliability: float
    raw_ber_for_challenge: float | None
    valid_repeats: int
    unreliable_bit: int


@dataclass(frozen=True)
class PairwiseMetric:
    board_a: str
    board_b: str
    compared_bits: int
    hamming_distance: float



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze real PUF sampling data.")
    parser.add_argument("--raw-csv", required=True, help="Raw sampling CSV path.")
    parser.add_argument("--aggregate-csv", default="", help="Optional aggregate summary CSV path.")
    parser.add_argument("--fe-auth-csv", default="", help="Optional FE/auth summary CSV path.")
    parser.add_argument("--out-dir", required=True, help="Directory for analysis outputs.")
    return parser.parse_args()



def normalize_hex(value: str) -> str:
    text = value.strip().lower()
    if text.startswith("0x"):
        text = text[2:]
    text = text.replace("_", "")
    return text.upper()



def parse_optional_int(value: str | None) -> int | None:
    if value is None:
        return None
    text = value.strip()
    if text == "":
        return None
    return int(text)



def challenge_key(row: dict[str, str]) -> tuple[str, str]:
    idx = row.get("challenge_index", "").strip()
    hex_text = normalize_hex(row.get("challenge_hex", ""))
    if idx:
        return ("idx", idx)
    if hex_text:
        return ("hex", hex_text)
    raise ValueError("row missing both challenge_index and challenge_hex")



def load_raw_rows(path: Path) -> list[RawRow]:
    required = {
        "board_id",
        "session_id",
        "temperature_label",
        "supply_label",
        "selection_mode",
        "challenge_hex",
        "repeat_index",
        "raw_resp_bit",
        "raw_resp_valid",
    }
    rows: list[RawRow] = []
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"raw CSV missing required columns: {sorted(missing)}")
        for row in reader:
            bit_text = row["raw_resp_bit"].strip()
            valid_text = row["raw_resp_valid"].strip()
            if bit_text not in {"0", "1"}:
                continue
            if valid_text not in {"0", "1"}:
                continue
            mode = row.get("selection_mode", "unknown").strip() or "unknown"
            if mode not in VALID_SELECTION_MODES:
                mode = "unknown"
            key_kind, key_value = challenge_key(row)
            rows.append(
                RawRow(
                    board_id=row["board_id"].strip(),
                    session_id=row["session_id"].strip(),
                    temperature_label=row["temperature_label"].strip(),
                    supply_label=row["supply_label"].strip(),
                    selection_mode=mode,
                    challenge_key=f"{key_kind}:{key_value}",
                    challenge_hex=normalize_hex(row["challenge_hex"]),
                    repeat_index=int(row["repeat_index"]),
                    raw_resp_bit=int(bit_text),
                    raw_resp_valid=int(valid_text),
                    reference_resp_bit=parse_optional_int(row.get("reference_resp_bit")),
                )
            )
    if not rows:
        raise ValueError("no valid raw rows found")
    return rows



def majority_bit(bits: list[int]) -> tuple[int, float]:
    ones = sum(bits)
    zeros = len(bits) - ones
    if ones > zeros:
        return 1, ones / len(bits)
    if zeros > ones:
        return 0, zeros / len(bits)
    first = bits[0]
    matches = sum(1 for b in bits if b == first)
    return first, matches / len(bits)



def build_aggregate_from_raw(rows: list[RawRow]) -> list[AggregateBit]:
    grouped: dict[tuple[str, str], list[RawRow]] = defaultdict(list)
    for row in rows:
        if row.raw_resp_valid == 1:
            grouped[(row.board_id, row.challenge_key)].append(row)

    aggregate: list[AggregateBit] = []
    for (board_id, chal_key), samples in grouped.items():
        samples_sorted = sorted(samples, key=lambda x: x.repeat_index)
        bits = [s.raw_resp_bit for s in samples_sorted]
        agg_bit, confidence = majority_bit(bits)
        reference_bits = [s.reference_resp_bit for s in samples_sorted if s.reference_resp_bit is not None]
        ref = reference_bits[0] if reference_bits else None
        raw_ber = None
        if ref is not None and bits:
            raw_ber = sum(1 for b in bits if b != ref) / len(bits)
        aggregate.append(
            AggregateBit(
                board_id=board_id,
                challenge_key=chal_key,
                challenge_hex=samples_sorted[0].challenge_hex,
                selection_mode=samples_sorted[0].selection_mode,
                aggregate_bit=agg_bit,
                reference_bit=ref,
                reliability=confidence,
                raw_ber_for_challenge=raw_ber,
                valid_repeats=len(bits),
                unreliable_bit=1 if confidence < 0.8 else 0,
            )
        )
    if not aggregate:
        raise ValueError("no aggregate bits could be built from raw rows")
    return aggregate



def load_aggregate_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        return list(reader)



def compute_aggregate_ber_from_csv(rows: list[dict[str, str]]) -> dict[str, float | None]:
    by_board_total: dict[str, int] = defaultdict(int)
    by_board_err: dict[str, int] = defaultdict(int)
    for row in rows:
        board = row.get("board_id", "").strip()
        agg = row.get("aggregate_resp_bit", "").strip()
        ref = row.get("reference_resp_bit", "").strip()
        if not board or agg not in {"0", "1"} or ref not in {"0", "1"}:
            continue
        by_board_total[board] += 1
        if agg != ref:
            by_board_err[board] += 1
    out: dict[str, float | None] = {}
    for board, total in by_board_total.items():
        out[board] = (by_board_err[board] / total) if total else None
    return out



def load_fe_auth_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        return list(reader)



def pct(value: float | None) -> str:
    if value is None:
        return "N/A"
    return f"{value * 100:.4f}%"



def compute_uniformity(rows: Iterable[RawRow]) -> dict[str, float]:
    by_board: dict[str, list[int]] = defaultdict(list)
    for row in rows:
        if row.raw_resp_valid == 1:
            by_board[row.board_id].append(row.raw_resp_bit)
    return {board: (sum(bits) / len(bits)) for board, bits in by_board.items() if bits}



def compute_reliability(aggregate_bits: Iterable[AggregateBit]) -> dict[str, float]:
    by_board: dict[str, list[float]] = defaultdict(list)
    for row in aggregate_bits:
        by_board[row.board_id].append(row.reliability)
    return {board: mean(vals) for board, vals in by_board.items() if vals}



def compute_raw_ber(aggregate_bits: Iterable[AggregateBit]) -> dict[str, float | None]:
    by_board: dict[str, list[float]] = defaultdict(list)
    for row in aggregate_bits:
        if row.raw_ber_for_challenge is not None:
            by_board[row.board_id].append(row.raw_ber_for_challenge)
    return {board: (mean(vals) if vals else None) for board, vals in by_board.items()}



def compute_aggregate_ber(aggregate_bits: Iterable[AggregateBit]) -> dict[str, float | None]:
    by_board_total: dict[str, int] = defaultdict(int)
    by_board_err: dict[str, int] = defaultdict(int)
    for row in aggregate_bits:
        if row.reference_bit is None:
            continue
        by_board_total[row.board_id] += 1
        if row.aggregate_bit != row.reference_bit:
            by_board_err[row.board_id] += 1
    out: dict[str, float | None] = {}
    for board, total in by_board_total.items():
        out[board] = (by_board_err[board] / total) if total else None
    return out



def build_common_set(aggregate_bits: list[AggregateBit]) -> tuple[list[str], dict[str, dict[str, int]], set[str], set[str]]:
    by_board: dict[str, dict[str, int]] = defaultdict(dict)
    selection_modes: set[str] = set()
    challenge_sets: dict[str, set[str]] = defaultdict(set)
    for row in aggregate_bits:
        by_board[row.board_id][row.challenge_key] = row.aggregate_bit
        challenge_sets[row.board_id].add(row.challenge_key)
        selection_modes.add(row.selection_mode)
    boards = sorted(by_board)
    if not boards:
        return [], {}, set(), selection_modes
    common = set.intersection(*(challenge_sets[b] for b in boards))
    return boards, by_board, common, selection_modes



def compute_pairwise_hd(boards: list[str], by_board: dict[str, dict[str, int]], common: set[str]) -> list[PairwiseMetric]:
    metrics: list[PairwiseMetric] = []
    ordered_chals = sorted(common)
    for a, b in combinations(boards, 2):
        compared = len(ordered_chals)
        if compared == 0:
            metrics.append(PairwiseMetric(a, b, 0, 0.0))
            continue
        diff = sum(1 for c in ordered_chals if by_board[a][c] != by_board[b][c])
        metrics.append(PairwiseMetric(a, b, compared, diff / compared))
    return metrics



def compute_bit_aliasing(boards: list[str], by_board: dict[str, dict[str, int]], common: set[str]) -> list[tuple[str, float]]:
    out: list[tuple[str, float]] = []
    for chal in sorted(common):
        bits = [by_board[b][chal] for b in boards]
        out.append((chal, sum(bits) / len(bits)))
    return out



def summarize_fe_auth(rows: list[dict[str, str]]) -> dict[str, float | None]:
    def mean_binary(field: str) -> float | None:
        vals = [int(r[field]) for r in rows if r.get(field, '').strip() in {'0', '1'}]
        return mean(vals) if vals else None
    return {
        'fe_recovery_success_rate': mean_binary('fe_recover_success'),
        'checksum_success_rate': mean_binary('checksum_match'),
        'auth_success_rate': mean_binary('auth_pass'),
    }



def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    raw_rows = load_raw_rows(Path(args.raw_csv))
    aggregate_bits = build_aggregate_from_raw(raw_rows)

    uniformity = compute_uniformity(raw_rows)
    reliability = compute_reliability(aggregate_bits)
    raw_ber = compute_raw_ber(aggregate_bits)
    aggregate_ber = compute_aggregate_ber(aggregate_bits)
    if args.aggregate_csv:
        aggregate_ber = compute_aggregate_ber_from_csv(load_aggregate_csv(Path(args.aggregate_csv)))

    boards, by_board, common_set, selection_modes = build_common_set(aggregate_bits)
    pairwise = compute_pairwise_hd(boards, by_board, common_set)
    bit_aliasing = compute_bit_aliasing(boards, by_board, common_set)

    uniqueness_label = 'inter_chip_uniqueness'
    uniqueness_note = '基于共同 challenge set 的传统 inter-chip Hamming distance。'
    if selection_modes - {'global_shared', 'common_challenge'}:
        uniqueness_label = 'selected_response_diversity'
        uniqueness_note = '当前 selection_mode 不是全局共同 challenge set，结果只能视为筛选后响应材料差异，不能直接当传统 uniqueness。'

    fe_auth_summary = {}
    if args.fe_auth_csv:
        fe_auth_summary = summarize_fe_auth(load_fe_auth_csv(Path(args.fe_auth_csv)))

    board_metrics_path = out_dir / 'board_metrics.csv'
    with board_metrics_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['board_id', 'uniformity', 'reliability', 'raw_ber', 'aggregate_ber'])
        for board in boards:
            writer.writerow([
                board,
                f"{uniformity.get(board, float('nan')):.6f}" if board in uniformity else '',
                f"{reliability.get(board, float('nan')):.6f}" if board in reliability else '',
                f"{raw_ber.get(board, float('nan')):.6f}" if raw_ber.get(board) is not None else '',
                f"{aggregate_ber.get(board, float('nan')):.6f}" if aggregate_ber.get(board) is not None else '',
            ])

    pairwise_path = out_dir / 'pairwise_distance.csv'
    with pairwise_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['board_a', 'board_b', 'compared_bits', uniqueness_label])
        for row in pairwise:
            writer.writerow([row.board_a, row.board_b, row.compared_bits, f"{row.hamming_distance:.6f}"])

    alias_path = out_dir / 'bit_aliasing.csv'
    with alias_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['challenge_key', 'ones_ratio_across_boards'])
        for chal, ratio in bit_aliasing:
            writer.writerow([chal, f"{ratio:.6f}"])

    summary = {
        'input_files': {
            'raw_csv': args.raw_csv,
            'aggregate_csv': args.aggregate_csv or None,
            'fe_auth_csv': args.fe_auth_csv or None,
        },
        'board_count': len(boards),
        'common_challenge_count': len(common_set),
        'selection_modes': sorted(selection_modes),
        'uniqueness_label': uniqueness_label,
        'uniqueness_note': uniqueness_note,
        'notes': [
            '3~5块板只能支撑有限样本FPGA级验证，不能夸大为大规模芯片统计结论。',
            'uniqueness必须基于共同challenge set；若使用per-device BestIdx，应改称selected response diversity。',
            'NIST SP 800-22只能作为统计随机性补充，不能替代PUF指标或安全性证明。',
        ],
        'board_metrics': {
            board: {
                'uniformity': uniformity.get(board),
                'reliability': reliability.get(board),
                'raw_ber': raw_ber.get(board),
                'aggregate_ber': aggregate_ber.get(board),
            }
            for board in boards
        },
        'summary_rates': fe_auth_summary,
    }

    summary_path = out_dir / 'summary.json'
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    print('Real PUF sampling analysis complete.')
    print(f'Boards: {len(boards)}')
    print(f'Common challenge count: {len(common_set)}')
    print(f'Uniqueness label: {uniqueness_label}')
    if fe_auth_summary:
        print('FE/auth summary:')
        for key, value in fe_auth_summary.items():
            print(f'  {key}: {pct(value)}')
    print(f'Outputs written to: {out_dir}')


if __name__ == '__main__':
    main()

