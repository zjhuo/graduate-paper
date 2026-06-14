#!/usr/bin/env python3
"""Software reference wrapper for SPONGENT-128/128/8 style hashing.

This implementation is intended for the PUF v1.0 software pipeline:
hashing, KDF, and authentication tags. It uses the SPONGENT-128 parameters:

    n = 128, b = 136, c = 128, r = 8, R = 70

The code is written to be easy to cross-check against a later hardware
SPONGENT core. It should be verified against final project test vectors before
being treated as the golden implementation.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass


SPONGENT128_N_BITS = 128
SPONGENT128_B_BITS = 136
SPONGENT128_C_BITS = 128
SPONGENT128_R_BITS = 8
SPONGENT128_ROUNDS = 70
SPONGENT128_LFSR_SIZE = 7
SPONGENT128_LFSR_IV = 0x7A

# SPONGENT uses a PRESENT-like 4-bit S-box.
SBOX = [0xE, 0xD, 0xB, 0x0, 0x2, 0x1, 0x4, 0xF, 0x7, 0xA, 0x8, 0x5, 0x9, 0xC, 0x3, 0x6]


@dataclass(frozen=True)
class SpongentParams:
    n_bits: int = SPONGENT128_N_BITS
    b_bits: int = SPONGENT128_B_BITS
    c_bits: int = SPONGENT128_C_BITS
    r_bits: int = SPONGENT128_R_BITS
    rounds: int = SPONGENT128_ROUNDS
    lfsr_size: int = SPONGENT128_LFSR_SIZE
    lfsr_iv: int = SPONGENT128_LFSR_IV


PARAMS_128 = SpongentParams()


def reverse_bits(value: int, width: int) -> int:
    out = 0
    for _ in range(width):
        out = (out << 1) | (value & 1)
        value >>= 1
    return out


def lfsr_step(value: int, width: int = SPONGENT128_LFSR_SIZE) -> int:
    """Clock the SPONGENT 7-bit LFSR for polynomial x^7 + x^6 + 1.

    Bit index 0 is the least significant bit. Feedback taps are 5 and 6.
    """

    if width != 7:
        raise ValueError("this reference currently implements the SPONGENT-128 7-bit LFSR")
    feedback = ((value >> 6) ^ (value >> 5)) & 1
    return ((value << 1) & ((1 << width) - 1)) | feedback


def sbox_layer(state: int, b_bits: int = SPONGENT128_B_BITS) -> int:
    out = 0
    for nibble_idx in range(b_bits // 4):
        nibble = (state >> (4 * nibble_idx)) & 0xF
        out |= SBOX[nibble] << (4 * nibble_idx)
    return out


def player(state: int, b_bits: int = SPONGENT128_B_BITS) -> int:
    out = 0
    last = b_bits - 1
    step = b_bits // 4
    for bit_idx in range(b_bits):
        bit = (state >> bit_idx) & 1
        if bit_idx == last:
            new_pos = last
        else:
            new_pos = (bit_idx * step) % last
        out |= bit << new_pos
    return out


def permutation(state: int, params: SpongentParams = PARAMS_128) -> int:
    mask = (1 << params.b_bits) - 1
    counter = params.lfsr_iv
    for _ in range(params.rounds):
        state ^= counter
        state ^= reverse_bits(counter, params.lfsr_size) << (params.b_bits - params.lfsr_size)
        state = sbox_layer(state, params.b_bits)
        state = player(state, params.b_bits)
        state &= mask
        counter = lfsr_step(counter, params.lfsr_size)
    return state


def spongent_pad(message: bytes) -> bytes:
    # Rate is 8 bits, so the reversible "1 followed by zeros" padding is one byte.
    return message + b"\x80"


def spongent_hash(message: bytes, out_bytes: int = 16, params: SpongentParams = PARAMS_128) -> bytes:
    if params.r_bits != 8:
        raise ValueError("this byte-oriented reference currently expects r=8")
    if out_bytes <= 0:
        raise ValueError("out_bytes must be positive")

    state = 0
    for block in spongent_pad(message):
        state ^= block
        state = permutation(state, params)

    output = bytearray()
    while len(output) < out_bytes:
        output.append(state & 0xFF)
        if len(output) < out_bytes:
            state = permutation(state, params)
    return bytes(output)


def encode_field(value: bytes | str | int) -> bytes:
    if isinstance(value, bytes):
        data = value
    elif isinstance(value, str):
        data = value.encode("utf-8")
    elif isinstance(value, int):
        if value < 0:
            raise ValueError("integer fields must be non-negative")
        data = value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big")
    else:
        raise TypeError(f"unsupported field type: {type(value)!r}")
    return len(data).to_bytes(2, "big") + data


def domain_message(domain: str, *fields: bytes | str | int) -> bytes:
    out = bytearray()
    out.extend(encode_field("PUFv1-SPONGENT"))
    out.extend(encode_field(domain))
    for field in fields:
        out.extend(encode_field(field))
    return bytes(out)


def spongent_kdf(key: bytes, label: str, *fields: bytes | str | int, out_bytes: int = 16) -> bytes:
    if out_bytes <= 0:
        raise ValueError("out_bytes must be positive")

    material = bytearray()
    counter = 0
    while len(material) < out_bytes:
        block = spongent_hash(domain_message("KDF", key, label, counter, *fields), out_bytes=16)
        material.extend(block)
        counter += 1
    return bytes(material[:out_bytes])


def spongent_tag(key: bytes, label: str, *fields: bytes | str | int, out_bytes: int = 16) -> bytes:
    return spongent_kdf(key, label, *fields, out_bytes=out_bytes)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SPONGENT-128/128/8 software reference helper.")
    parser.add_argument("--hex", default="", help="Hex input to hash.")
    parser.add_argument("--text", default="", help="UTF-8 text input to hash.")
    parser.add_argument("--out-bytes", type=int, default=16)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.hex:
        message = bytes.fromhex(args.hex)
    else:
        message = args.text.encode("utf-8")
    print(spongent_hash(message, args.out_bytes).hex().upper())


if __name__ == "__main__":
    main()
