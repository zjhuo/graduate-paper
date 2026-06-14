#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from build_binding_from_samples import (  # type: ignore
    KEY_BYTES,
    CODE_N,
    FE_KDF_LABEL,
    HTAG_LABEL,
    RV_LABEL,
    SK_LABEL,
    SRVAUTH_LABEL,
    BRAND,
    DOMAIN,
    bits_to_hex,
    build_checksum_message,
    build_segmented_message,
    derive_h_tag,
    derive_key_from_message_bits,
    derive_r_virtual,
    derive_s_tag,
    derive_sk,
    fe_recover_message_bits,
    message_bits_bytes,
)
from spongent_ref import spongent_hash  # type: ignore

SALT = bytes.fromhex('00112233445566778899AABBCCDDEEFF')
DEVICE_ID = bytes.fromhex('4445564943455F303030000000000001')
NONCE_D = bytes.fromhex('ABF82BCE5E84F78F1E3D53F079C3B39D')
NONCE_S = bytes.fromhex('1B7D12F8469162DA6ED72010C60A9CB0')
V_I = bytes.fromhex('EABC8A517BC9C497A063A2C0E5CEB081')
C_INIT = bytes.fromhex('199D985A6675DD1EB87880FB7B399FEE')

CHECKSUM_GOLDEN = '28F6A05B433199F5A0D4801F23939CF0'
K_GOLDEN = 'F7568117C93728F72CA4886F766F3AC3'
H_TAG_GOLDEN = '08CAEB2004860A4EB6C64A1F016E4AD0'
S_TAG_GOLDEN = '6BE0336CEA1FCF61D899F68D71CB04E9'

N_REP = 5
TARGET_BITS = 256


def aggregate_bits_from_standard_tb(target_bits: int = TARGET_BITS, n_rep: int = N_REP) -> list[int]:
    out: list[int] = []
    for chal_idx in range(target_bits):
        cnt1 = 0
        for rep_idx in range(n_rep):
            bit = ((chal_idx * n_rep) + rep_idx) & 1
            cnt1 += bit
        out.append(1 if cnt1 >= 3 else 0)
    return out


def vector_display_hex(bits: list[int]) -> str:
    value = 0
    for idx, bit in enumerate(bits):
        if bit:
            value |= 1 << idx
    width = (len(bits) + 3) // 4
    return f"{value:0{width}X}"


def main() -> int:
    parser = argparse.ArgumentParser(description='Golden-vector self-check for real-PUF binding toolchain.')
    parser.add_argument('--out-dir', required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    aggregate_bits = aggregate_bits_from_standard_tb()
    helper_xor_bits = [0] * TARGET_BITS
    ok, message_bits = fe_recover_message_bits(aggregate_bits, helper_xor_bits)
    if not ok:
        raise SystemExit('Hamming FE recovery failed in golden self-test')

    checksum_msg = build_checksum_message(DEVICE_ID, SALT, message_bits)
    checksum_hex = spongent_hash(checksum_msg, out_bytes=KEY_BYTES).hex().upper()

    key_bytes = derive_key_from_message_bits(message_bits, DEVICE_ID, SALT)
    rv_bytes = derive_r_virtual(key_bytes, V_I, C_INIT)
    sk_bytes = derive_sk(rv_bytes, NONCE_S, NONCE_D, C_INIT)
    h_tag_bytes = derive_h_tag(rv_bytes, NONCE_S, NONCE_D)
    s_tag_bytes = derive_s_tag(sk_bytes)

    fe_kdf_message = build_segmented_message(b'', FE_KDF_LABEL, [], message_bits=message_bits, device_id_bytes=DEVICE_ID, salt=SALT)
    rv_message = build_segmented_message(key_bytes, RV_LABEL, [V_I, C_INIT])
    h_tag_message = build_segmented_message(rv_bytes, HTAG_LABEL, [NONCE_S, NONCE_D])
    s_tag_message = build_segmented_message(sk_bytes, SRVAUTH_LABEL, [])

    summary = {
        'golden_source': {
            'tb': r'D:\zijin\rtl\tb\iotpufs_terminal_top_tb.sv',
            'regression_tb': r'D:\zijin\rtl\tb\iotpufs_terminal_top_regression_tb.sv',
            'rtl_spongent': r'D:\zijin\rtl\spongent_core_stub.sv',
            'python_ref': r'D:\zijin\scripts\spongent_ref.py',
        },
        'assumptions': {
            'response_source': 'standard_tb sample_counter_q[0] fixed/simulated source',
            'n_rep': N_REP,
            'helper_mask': 'all ones',
            'helper_xor': 'all zeros',
            'device_id_mode': 'fixed_16_byte_raw_field',
            'padding_rule': 'SPONGENT r=8 => append one byte 0x80',
            'fixed_zero_field_after_label_hex': '00',
            'fe_kdf_suffix_field_hex': 'B0',
            'kdf_counter_mode': 'no incrementing multi-block KDF counter in current RTL; message contains a fixed single-byte 0x00 field after label',
        },
        'message_bits': {
            'bit_length': len(message_bits),
            'pack_bits_hex': message_bits_bytes(message_bits).hex().upper(),
            'vector_display_hex': vector_display_hex(message_bits),
            'note': 'pack_bits_hex is the true SPONGENT input byte order; vector_display_hex matches Verilog %h display order for message_bits_hat[175:0].',
        },
        'messages': {
            'checksum_message_hex': checksum_msg.hex().upper(),
            'fe_kdf_message_hex': fe_kdf_message.hex().upper(),
            'r_virtual_message_hex': rv_message.hex().upper(),
            'h_tag_message_hex': h_tag_message.hex().upper(),
            's_tag_message_hex': s_tag_message.hex().upper(),
            'checksum_concat': 'CHECKSUM_PREFIX || DEVICE_ID || 0x0A || SALT || pack_bits(message_bits)',
            'fe_kdf_concat': 'len(BRAND)||BRAND||len(DOMAIN)||DOMAIN||len(MSG)||MSG||len(LABEL)||LABEL||len(1)||0x00||len(DEVICE_ID)||DEVICE_ID||len(SALT)||SALT||len(1)||0xB0',
            'h_tag_concat': 'len(BRAND)||BRAND||len(DOMAIN)||DOMAIN||len(R_virtual)||R_virtual||len(H_tag)||H_tag||len(1)||0x00||len(NONCE_S)||NONCE_S||len(NONCE_D)||NONCE_D',
            's_tag_concat': 'len(BRAND)||BRAND||len(DOMAIN)||DOMAIN||len(SK)||SK||len(SrvAuth)||SrvAuth||len(1)||0x00',
        },
        'derived': {
            'checksum_hex': checksum_hex,
            'key_hex': key_bytes.hex().upper(),
            'r_virtual_hex': rv_bytes.hex().upper(),
            'sk_hex': sk_bytes.hex().upper(),
            'h_tag_hex': h_tag_bytes.hex().upper(),
            's_tag_hex': s_tag_bytes.hex().upper(),
        },
        'checks': {
            'checksum_match': checksum_hex == CHECKSUM_GOLDEN,
            'key_match': key_bytes.hex().upper() == K_GOLDEN,
            'h_tag_match': h_tag_bytes.hex().upper() == H_TAG_GOLDEN,
            's_tag_match': s_tag_bytes.hex().upper() == S_TAG_GOLDEN,
        },
        'expected': {
            'checksum_hex': CHECKSUM_GOLDEN,
            'key_hex': K_GOLDEN,
            'h_tag_hex': H_TAG_GOLDEN,
            's_tag_hex': S_TAG_GOLDEN,
        },
        'not_checked_against_explicit_golden': [
            'r_virtual_hex',
            'sk_hex'
        ],
        'boundary': 'This is a golden-vector alignment self-test for the offline toolchain. It is not a real PUF measurement and does not prove real-PUF authentication success.'
    }

    (out_dir / 'golden_selftest_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    all_ok = all(summary['checks'].values())
    print(json.dumps({
        'out_dir': str(out_dir),
        'checksum_match': summary['checks']['checksum_match'],
        'key_match': summary['checks']['key_match'],
        'h_tag_match': summary['checks']['h_tag_match'],
        's_tag_match': summary['checks']['s_tag_match'],
        'message_bits_pack_bits_hex': summary['message_bits']['pack_bits_hex'],
        'message_bits_vector_display_hex': summary['message_bits']['vector_display_hex'],
        'all_ok': all_ok,
    }, ensure_ascii=False, indent=2))
    return 0 if all_ok else 1


if __name__ == '__main__':
    raise SystemExit(main())