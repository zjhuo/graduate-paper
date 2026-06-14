#!/usr/bin/env python3
"""Build real-PUF binding materials from sampling data.

This tool is a pre-board / pre-real-data skeleton for the later
"real sampling -> constant regeneration -> authentication re-binding" flow.
It does not prove real PUF authentication success.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

THIS_DIR = Path(__file__).resolve().parent
SCRIPTS_ROOT = THIS_DIR.parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from analyze_real_puf_sampling import build_aggregate_from_raw, load_raw_rows  # type: ignore
from spongent_ref import spongent_hash  # type: ignore

BRAND = b"PUFv1-SPONGENT"
DOMAIN = b"KDF"
FE_KDF_LABEL = b"FE_HAMMING1611_KEY"
RV_LABEL = b"R_virtual"
SK_LABEL = b"SK"
HTAG_LABEL = b"H_tag"
SRVAUTH_LABEL = b"SrvAuth"
CHECKSUM_PREFIX = b"PUFv1 FE Hamming1611 checksum\n"
MSG_BITS = 176
KEY_BYTES = 16
CODE_N = 16
CODE_K = 11
CURRENT_FE_MODE = "hamming1611_code_offset_skeleton"
CURRENT_SPONGENT_PROFILE = "spongent128_128_8"
CURRENT_KDF_PROFILE = "rtl_spongent_core_stub_segmented"
MANIFEST_VERSION = "real_puf_binding_manifest_0.2"


@dataclass(frozen=True)
class AggregateRecord:
    board_id: str
    session_id: str
    temperature_label: str
    supply_label: str
    selection_mode: str
    challenge_index: int
    challenge_hex: str
    aggregate_bit: int
    reference_bit: int | None
    valid_repeats: int
    unreliable_bit: int
    raw_ber_for_challenge: float | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build binding materials from real/synthetic PUF samples.")
    parser.add_argument("--raw-csv", default="", help="Raw sampling CSV path.")
    parser.add_argument("--aggregate-csv", default="", help="Optional aggregate summary CSV path.")
    parser.add_argument("--out-dir", required=True, help="Output directory.")
    parser.add_argument("--board-id", default="", help="Board ID when the input contains multiple boards.")
    parser.add_argument("--device-id", required=True, help="Logical device identifier.")
    parser.add_argument("--device-id-hex", default="", help="Optional exact device_id bytes for RTL binding.")
    parser.add_argument("--challenge-table-version", required=True, help="Restricted challenge subset / ROM version string.")
    parser.add_argument("--salt-hex", required=True, help="Salt used by the current FE/KDF chain.")
    parser.add_argument("--target-bits", type=int, default=0, help="Target response width in bits. Defaults to next multiple of 16.")
    parser.add_argument("--registration-rsel-hex", default="", help="Optional registration reference response bits (hex).")
    parser.add_argument("--message-bits-hex", default="", help="Optional registration message bits (hex, trimmed to message-bits-len).")
    parser.add_argument("--message-bits-len", type=int, default=0, help="Explicit message bit length when message-bits-hex is provided.")
    parser.add_argument("--fill-missing", choices=["zero", "registration"], default="registration", help="How to fill unobserved challenges when target_bits exceeds observed challenges.")
    parser.add_argument("--nonce-d-hex", default="", help="Optional nonce_d for placeholder session material generation.")
    parser.add_argument("--nonce-s-hex", default="", help="Optional nonce_s for placeholder session material generation.")
    parser.add_argument("--v-i-hex", default="", help="Optional V_i for placeholder session material generation.")
    parser.add_argument("--c-init-hex", default="", help="Optional C_init for placeholder session material generation.")
    parser.add_argument("--synthetic", action="store_true", help="Mark this run as synthetic self-test only.")
    args = parser.parse_args()
    if not args.raw_csv and not args.aggregate_csv:
        parser.error("at least one of --raw-csv or --aggregate-csv is required")
    return args


def normalize_hex(text: str) -> str:
    value = text.strip().replace("_", "")
    if value.lower().startswith("0x"):
        value = value[2:]
    return value.upper()


def pack_bits_msb(bits: list[int]) -> bytes:
    out = bytearray((len(bits) + 7) // 8)
    for idx, bit in enumerate(bits):
        if bit:
            out[idx // 8] |= 1 << (7 - (idx % 8))
    return bytes(out)


def bits_to_hex(bits: list[int]) -> str:
    return pack_bits_msb(bits).hex().upper()


def hex_to_bits(hex_text: str, bit_length: int) -> list[int]:
    data = bytes.fromhex(normalize_hex(hex_text))
    if bit_length > len(data) * 8:
        raise ValueError(f"hex text only provides {len(data) * 8} bits, cannot trim/extend to {bit_length}")
    bits: list[int] = []
    for idx in range(bit_length):
        bits.append((data[idx // 8] >> (7 - (idx % 8))) & 1)
    return bits


def next_multiple_of_16(value: int) -> int:
    if value <= 0:
        return 16
    return ((value + 15) // 16) * 16


def parse_device_id_bytes(device_id: str, device_id_hex: str) -> bytes:
    if device_id_hex:
        return bytes.fromhex(normalize_hex(device_id_hex))
    return device_id.encode("utf-8")


def parse_optional_hex_bytes(value: str) -> bytes | None:
    return bytes.fromhex(normalize_hex(value)) if value.strip() else None


def encode_len(data: bytes) -> bytes:
    return len(data).to_bytes(2, "big")


def message_bits_bytes(message_bits: list[int]) -> bytes:
    return pack_bits_msb(message_bits)


def build_checksum_message(device_id_bytes: bytes, salt: bytes, message_bits: list[int]) -> bytes:
    return CHECKSUM_PREFIX + device_id_bytes + b"\x0A" + salt + message_bits_bytes(message_bits)


def build_segmented_message(key_bytes: bytes, label: bytes, extra_segments: list[bytes], message_bits: list[int] | None = None, device_id_bytes: bytes | None = None, salt: bytes | None = None) -> bytes:
    out = bytearray()
    out.extend(encode_len(BRAND))
    out.extend(BRAND)
    out.extend(encode_len(DOMAIN))
    out.extend(DOMAIN)
    if message_bits is not None:
        msg_bytes = message_bits_bytes(message_bits)
        out.extend(encode_len(msg_bytes))
        out.extend(msg_bytes)
    else:
        out.extend(encode_len(key_bytes))
        out.extend(key_bytes)
    out.extend(encode_len(label))
    out.extend(label)
    out.extend((1).to_bytes(2, "big"))
    out.extend(b"\x00")
    for segment in extra_segments:
        out.extend(encode_len(segment))
        out.extend(segment)
    if device_id_bytes is not None:
        out.extend(encode_len(device_id_bytes))
        out.extend(device_id_bytes)
    if salt is not None:
        out.extend(encode_len(salt))
        out.extend(salt)
        out.extend((1).to_bytes(2, "big"))
        out.extend(b"\xB0")
    return bytes(out)


def derive_key_from_message_bits(message_bits: list[int], device_id_bytes: bytes, salt: bytes) -> bytes:
    message = build_segmented_message(b"", FE_KDF_LABEL, [], message_bits=message_bits, device_id_bytes=device_id_bytes, salt=salt)
    return spongent_hash(message, out_bytes=KEY_BYTES)


def derive_r_virtual(key: bytes, v_i: bytes, c_init: bytes) -> bytes:
    return spongent_hash(build_segmented_message(key, RV_LABEL, [v_i, c_init]), out_bytes=KEY_BYTES)


def derive_sk(r_virtual: bytes, nonce_s: bytes, nonce_d: bytes, c_init: bytes) -> bytes:
    return spongent_hash(build_segmented_message(r_virtual, SK_LABEL, [nonce_s, nonce_d, c_init]), out_bytes=KEY_BYTES)


def derive_h_tag(r_virtual: bytes, nonce_s: bytes, nonce_d: bytes) -> bytes:
    return spongent_hash(build_segmented_message(r_virtual, HTAG_LABEL, [nonce_s, nonce_d]), out_bytes=KEY_BYTES)


def derive_s_tag(sk: bytes) -> bytes:
    return spongent_hash(build_segmented_message(sk, SRVAUTH_LABEL, []), out_bytes=KEY_BYTES)


def derive_placeholder_message_bits(device_id: str, salt: bytes, challenge_table_version: str, bit_length: int) -> list[int]:
    if bit_length <= 0:
        return []
    seed_material = f"{device_id}|{challenge_table_version}|{salt.hex().upper()}|message_bits".encode("utf-8")
    material = bytearray()
    counter = 0
    while len(material) * 8 < bit_length:
        material.extend(hashlib.sha256(seed_material + counter.to_bytes(4, "big")).digest())
        counter += 1
    bits: list[int] = []
    for idx in range(bit_length):
        bits.append((material[idx // 8] >> (7 - (idx % 8))) & 1)
    return bits


def hamming1611_encode_block(data_bits: list[int]) -> list[int]:
    if len(data_bits) != CODE_K:
        raise ValueError(f"Hamming(16,11) block expects {CODE_K} data bits, got {len(data_bits)}")
    block = [0] * CODE_N
    data_positions = [2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14]
    for bit, pos in zip(data_bits, data_positions):
        block[pos] = bit
    for parity_position in (1, 2, 4, 8):
        parity = 0
        for position in range(1, CODE_N):
            if position & parity_position:
                if position != parity_position:
                    parity ^= block[position - 1]
        block[parity_position - 1] = parity
    overall = 0
    for position in range(CODE_N - 1):
        overall ^= block[position]
    block[15] = overall
    return block


def encode_hamming1611_message(message_bits: list[int]) -> list[int]:
    if len(message_bits) % CODE_K != 0:
        raise ValueError("message_bits length must be a multiple of 11 for hamming1611 skeleton")
    codeword: list[int] = []
    for start in range(0, len(message_bits), CODE_K):
        codeword.extend(hamming1611_encode_block(message_bits[start:start + CODE_K]))
    return codeword


def correct_hamming_block(block: list[int]) -> tuple[list[int], bool]:
    if len(block) != CODE_N:
        raise ValueError("expected 16-bit Hamming block")
    corrected = list(block)
    syndrome = 0
    for parity_position in (1, 2, 4, 8):
        parity = 0
        for position in range(1, CODE_N):
            if position & parity_position:
                parity ^= corrected[position - 1]
        if parity:
            syndrome += parity_position
    overall = 0
    for bit in corrected:
        overall ^= bit
    success = True
    if syndrome == 0 and overall == 0:
        pass
    elif syndrome == 0 and overall == 1:
        corrected[15] ^= 1
    elif syndrome != 0 and overall == 1:
        corrected[syndrome - 1] ^= 1
    else:
        success = False
    return corrected, success


def extract_hamming1611_data(block: list[int]) -> list[int]:
    positions = [2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14]
    return [block[pos] for pos in positions]


def fe_recover_message_bits(rsel_bits: list[int], helper_xor_bits: list[int]) -> tuple[bool, list[int]]:
    if len(rsel_bits) != len(helper_xor_bits):
        raise ValueError("rsel/helper_xor length mismatch")
    if len(rsel_bits) % CODE_N != 0:
        raise ValueError("selected response length must be a multiple of 16")
    message_bits: list[int] = []
    ok = True
    for start in range(0, len(rsel_bits), CODE_N):
        noisy_codeword = [rsel_bits[start + i] ^ helper_xor_bits[start + i] for i in range(CODE_N)]
        corrected, block_ok = correct_hamming_block(noisy_codeword)
        if not block_ok:
            ok = False
        message_bits.extend(extract_hamming1611_data(corrected))
    return ok, message_bits


def read_aggregate_csv(path: Path) -> list[AggregateRecord]:
    rows: list[AggregateRecord] = []
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            board_id = row.get("board_id", "").strip()
            if not board_id:
                continue
            idx_text = row.get("challenge_index", "").strip()
            if not idx_text:
                continue
            agg_text = row.get("aggregate_resp_bit", "").strip()
            if agg_text not in {"0", "1"}:
                continue
            ref_text = row.get("reference_resp_bit", "").strip()
            ber_text = row.get("raw_ber_for_challenge", "").strip()
            rows.append(
                AggregateRecord(
                    board_id=board_id,
                    session_id=row.get("session_id", "").strip(),
                    temperature_label=row.get("temperature_label", "").strip(),
                    supply_label=row.get("supply_label", "").strip(),
                    selection_mode=row.get("selection_mode", "unknown").strip() or "unknown",
                    challenge_index=int(idx_text),
                    challenge_hex=normalize_hex(row.get("challenge_hex", "")),
                    aggregate_bit=int(agg_text),
                    reference_bit=int(ref_text) if ref_text in {"0", "1"} else None,
                    valid_repeats=int(row.get("valid_repeats", "0") or 0),
                    unreliable_bit=int(row.get("unreliable_bit", "0") or 0),
                    raw_ber_for_challenge=float(ber_text) if ber_text else None,
                )
            )
    if not rows:
        raise ValueError(f"no valid aggregate rows found in {path}")
    return rows


def build_aggregate_records_from_raw(path: Path) -> list[AggregateRecord]:
    raw_rows = load_raw_rows(path)
    aggregate_rows = build_aggregate_from_raw(raw_rows)
    meta: dict[tuple[str, str], tuple[str, str, str, str]] = {}
    for row in raw_rows:
        if row.raw_resp_valid != 1:
            continue
        if row.challenge_key.startswith("idx:"):
            challenge_index = row.challenge_key.split(":", 1)[1]
        else:
            challenge_index = "-1"
        meta[(row.board_id, challenge_index)] = (
            row.session_id,
            row.temperature_label,
            row.supply_label,
            row.selection_mode,
        )
    result: list[AggregateRecord] = []
    for item in aggregate_rows:
        if not item.challenge_key.startswith("idx:"):
            raise ValueError("build_binding_from_samples currently expects challenge_index-based input")
        idx = int(item.challenge_key.split(":", 1)[1])
        session_id, temp, supply, mode = meta.get((item.board_id, str(idx)), ("", "", "", item.selection_mode))
        result.append(
            AggregateRecord(
                board_id=item.board_id,
                session_id=session_id,
                temperature_label=temp,
                supply_label=supply,
                selection_mode=mode,
                challenge_index=idx,
                challenge_hex=item.challenge_hex,
                aggregate_bit=item.aggregate_bit,
                reference_bit=item.reference_bit,
                valid_repeats=item.valid_repeats,
                unreliable_bit=item.unreliable_bit,
                raw_ber_for_challenge=item.raw_ber_for_challenge,
            )
        )
    return result


def choose_board(records: list[AggregateRecord], board_id: str) -> str:
    boards = sorted({r.board_id for r in records})
    if board_id:
        if board_id not in boards:
            raise ValueError(f"board_id {board_id!r} not found; available boards: {boards}")
        return board_id
    if len(boards) != 1:
        raise ValueError(f"multiple boards found {boards}; please provide --board-id")
    return boards[0]


def bit_length_from_hex(hex_text: str) -> int:
    return len(normalize_hex(hex_text)) * 4


def build_vector_from_records(
    records: list[AggregateRecord],
    board_id: str,
    target_bits: int,
    registration_bits: list[int] | None,
    fill_missing: str,
) -> tuple[list[int], int, int, dict[int, str], dict[int, int | None], str, str, str]:
    board_rows = [r for r in records if r.board_id == board_id]
    if not board_rows:
        raise ValueError(f"no rows found for board_id={board_id}")
    vector = [0] * target_bits
    challenge_hex_by_index: dict[int, str] = {}
    reference_by_index: dict[int, int | None] = {}
    for row in board_rows:
        if row.challenge_index >= target_bits:
            continue
        vector[row.challenge_index] = row.aggregate_bit
        challenge_hex_by_index[row.challenge_index] = row.challenge_hex
        reference_by_index[row.challenge_index] = row.reference_bit
    observed = len(challenge_hex_by_index)
    filled = 0
    if observed < target_bits:
        for idx in range(target_bits):
            if idx in challenge_hex_by_index:
                continue
            if fill_missing == "registration" and registration_bits is not None:
                vector[idx] = registration_bits[idx]
            else:
                vector[idx] = 0
            filled += 1
    session_id = board_rows[0].session_id
    temperature_label = board_rows[0].temperature_label
    supply_label = board_rows[0].supply_label
    selection_mode = board_rows[0].selection_mode
    return vector, observed, filled, challenge_hex_by_index, reference_by_index, session_id, temperature_label, supply_label, selection_mode


def resolve_target_bits(args: argparse.Namespace, records: list[AggregateRecord]) -> int:
    if args.target_bits:
        if args.target_bits % CODE_N != 0:
            raise ValueError("--target-bits must be a multiple of 16 for the current hamming1611 skeleton")
        return args.target_bits
    if args.registration_rsel_hex:
        bits = bit_length_from_hex(args.registration_rsel_hex)
        if bits % CODE_N != 0:
            raise ValueError("registration reference response length must be a multiple of 16")
        return bits
    max_idx = max(r.challenge_index for r in records) + 1
    return next_multiple_of_16(max_idx)


def parse_message_bits(args: argparse.Namespace, bit_length: int) -> tuple[list[int], str]:
    if args.message_bits_hex:
        target_len = args.message_bits_len if args.message_bits_len else bit_length
        return hex_to_bits(args.message_bits_hex, target_len), "provided_message_bits_hex"
    return derive_placeholder_message_bits(args.device_id, bytes.fromhex(normalize_hex(args.salt_hex)), args.challenge_table_version, bit_length), "derived_placeholder_message_bits"


def maybe_write_text(path: Path, text: str) -> None:
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    records = build_aggregate_records_from_raw(Path(args.raw_csv)) if args.raw_csv else read_aggregate_csv(Path(args.aggregate_csv))
    board_id = choose_board(records, args.board_id)
    target_bits = resolve_target_bits(args, records)

    registration_bits = None
    registration_source = "aggregate_as_placeholder_registration"
    if args.registration_rsel_hex:
        registration_bits = hex_to_bits(args.registration_rsel_hex, target_bits)
        registration_source = "provided_registration_rsel_hex"

    aggregate_bits, observed_challenges, filled_missing_count, challenge_hex_by_index, reference_by_index, session_id, temperature_label, supply_label, selection_mode = build_vector_from_records(
        records, board_id, target_bits, registration_bits, args.fill_missing
    )

    if registration_bits is None:
        registration_bits = list(aggregate_bits)

    blocks = target_bits // CODE_N
    message_bits_len = blocks * CODE_K
    message_bits, message_source = parse_message_bits(args, message_bits_len)
    codeword_bits = encode_hamming1611_message(message_bits)
    helper_xor_bits = [registration_bits[idx] ^ codeword_bits[idx] for idx in range(target_bits)]
    helper_mask_bits = [1] * target_bits

    fe_recover_success, recovered_message_bits = fe_recover_message_bits(aggregate_bits, helper_xor_bits)
    registration_checksum = spongent_hash(build_checksum_message(parse_device_id_bytes(args.device_id, args.device_id_hex), bytes.fromhex(normalize_hex(args.salt_hex)), message_bits), out_bytes=KEY_BYTES)
    recovered_checksum = spongent_hash(build_checksum_message(parse_device_id_bytes(args.device_id, args.device_id_hex), bytes.fromhex(normalize_hex(args.salt_hex)), recovered_message_bits), out_bytes=KEY_BYTES)
    checksum_match = fe_recover_success and (registration_checksum == recovered_checksum)

    salt = bytes.fromhex(normalize_hex(args.salt_hex))
    device_id_bytes = parse_device_id_bytes(args.device_id, args.device_id_hex)
    registration_key = derive_key_from_message_bits(message_bits, device_id_bytes, salt)
    recovered_key = derive_key_from_message_bits(recovered_message_bits, device_id_bytes, salt)

    nonce_d = parse_optional_hex_bytes(args.nonce_d_hex)
    nonce_s = parse_optional_hex_bytes(args.nonce_s_hex)
    v_i = parse_optional_hex_bytes(args.v_i_hex)
    c_init = parse_optional_hex_bytes(args.c_init_hex)
    session_fields_complete = all(x is not None for x in (nonce_d, nonce_s, v_i, c_init))

    h_tag = None
    s_tag = None
    r_virtual = None
    sk = None
    if session_fields_complete:
        assert nonce_d is not None and nonce_s is not None and v_i is not None and c_init is not None
        r_virtual = derive_r_virtual(registration_key, v_i, c_init)
        sk = derive_sk(r_virtual, nonce_s, nonce_d, c_init)
        h_tag = derive_h_tag(r_virtual, nonce_s, nonce_d)
        s_tag = derive_s_tag(sk)

    helper_xor_path = out_dir / "helper_xor.hex"
    helper_mask_path = out_dir / "helper_mask.hex"
    checksum_path = out_dir / "checksum.txt"
    s_tag_path = out_dir / "s_tag.txt"
    manifest_path = out_dir / "binding_manifest.json"
    fe_auth_summary_path = out_dir / "fe_auth_summary.csv"

    maybe_write_text(helper_xor_path, bits_to_hex(helper_xor_bits))
    maybe_write_text(helper_mask_path, bits_to_hex(helper_mask_bits))
    maybe_write_text(checksum_path, registration_checksum.hex().upper())
    if s_tag is None:
        maybe_write_text(s_tag_path, "PLACEHOLDER_NEEDS_NONCE_D_NONCE_S_V_I_C_INIT")
    else:
        maybe_write_text(s_tag_path, s_tag.hex().upper())

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "synthetic": args.synthetic,
        "tool": "build_binding_from_samples.py",
        "board_id": board_id,
        "device_id": args.device_id,
        "device_id_hex": device_id_bytes.hex().upper(),
        "session_id": session_id,
        "temperature_label": temperature_label,
        "supply_label": supply_label,
        "selection_mode": selection_mode,
        "challenge_table_version": args.challenge_table_version,
        "fe_mode": CURRENT_FE_MODE,
        "spongent_profile": CURRENT_SPONGENT_PROFILE,
        "kdf_profile": CURRENT_KDF_PROFILE,
        "target_bits": target_bits,
        "blocks": blocks,
        "message_bits": message_bits_len,
        "observed_challenge_count": observed_challenges,
        "filled_missing_count": filled_missing_count,
        "fill_missing_policy": args.fill_missing,
        "registration_source": registration_source,
        "message_bits_source": message_source,
        "session_fields_complete": session_fields_complete,
        "helper_xor_file": helper_xor_path.name,
        "helper_mask_file": helper_mask_path.name,
        "checksum_file": checksum_path.name,
        "s_tag_file": s_tag_path.name,
        "fe_auth_summary_csv": fe_auth_summary_path.name,
        "notes": [
            "This run may be synthetic and is not real PUF evidence.",
            "helper can be public but must not be described as revealing the long-term key K.",
            "checksum is an integrity/binding material, not a session key.",
            "s_tag should not be treated as a permanently fixed protocol value in the final real system.",
            "Current wrapper constants are still fixed-value placeholders until real board sampling is available.",
        ],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    with fe_auth_summary_path.open("w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "board_id",
            "device_id",
            "selection_mode",
            "challenge_table_version",
            "target_bits",
            "observed_challenge_count",
            "filled_missing_count",
            "registration_source",
            "message_bits_source",
            "helper_mask_all_ones",
            "fe_recover_success",
            "checksum_match",
            "session_fields_complete",
            "s_tag_generated",
            "auth_pass_checked",
            "auth_pass_result",
            "registration_key_hex",
            "recovered_key_hex",
            "registration_checksum_hex",
            "recovered_checksum_hex",
            "h_tag_hex",
            "s_tag_hex",
            "notes",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow(
            {
                "board_id": board_id,
                "device_id": args.device_id,
                "selection_mode": selection_mode,
                "challenge_table_version": args.challenge_table_version,
                "target_bits": target_bits,
                "observed_challenge_count": observed_challenges,
                "filled_missing_count": filled_missing_count,
                "registration_source": registration_source,
                "message_bits_source": message_source,
                "helper_mask_all_ones": 1,
                "fe_recover_success": int(fe_recover_success),
                "checksum_match": int(checksum_match),
                "session_fields_complete": int(session_fields_complete),
                "s_tag_generated": int(s_tag is not None),
                "auth_pass_checked": 0,
                "auth_pass_result": "N/A",
                "registration_key_hex": registration_key.hex().upper(),
                "recovered_key_hex": recovered_key.hex().upper(),
                "registration_checksum_hex": registration_checksum.hex().upper(),
                "recovered_checksum_hex": recovered_checksum.hex().upper(),
                "h_tag_hex": h_tag.hex().upper() if h_tag is not None else "",
                "s_tag_hex": s_tag.hex().upper() if s_tag is not None else "",
                "notes": "Synthetic/placeholder-capable binding skeleton; auth_pass is not proven here.",
            }
        )

    summary = {
        "board_id": board_id,
        "device_id": args.device_id,
        "observed_challenge_count": observed_challenges,
        "target_bits": target_bits,
        "message_bits": message_bits_len,
        "fe_recover_success": fe_recover_success,
        "checksum_match": checksum_match,
        "session_fields_complete": session_fields_complete,
        "s_tag_generated": s_tag is not None,
        "binding_manifest": str(manifest_path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
