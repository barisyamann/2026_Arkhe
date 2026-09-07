#!/usr/bin/env python3
"""
Arkhe NPU deterministic golden reference.

Bu test GERÇEK SES testi değildir. Amaç RTL aritmetiğini önce deterministik bir
1960 INT8 vektör üzerinde self-checking olarak doğrulamaktır.
"""
from pathlib import Path
import json

HERE = Path(__file__).resolve().parent

def read_hex_signed(path, bits):
    vals = []
    for line in Path(path).read_text().split():
        u = int(line, 16)
        if u >= (1 << (bits - 1)):
            u -= 1 << bits
        vals.append(u)
    return vals

def trunc_div(a, b):
    return a // b if a >= 0 else -((-a) // b)

def sat_round_high_mul(a, b):
    if a == -(1 << 31) and b == -(1 << 31):
        return (1 << 31) - 1
    ab = a * b
    nudge = (1 << 30) if ab >= 0 else (1 - (1 << 30))
    return trunc_div(ab + nudge, 1 << 31)

def rounding_divide_by_pot(x, exponent):
    mask = (1 << exponent) - 1
    remainder = x & mask
    threshold = (mask >> 1) + (1 if x < 0 else 0)
    return (x >> exponent) + (1 if remainder > threshold else 0)

def multiply_quantized(x, multiplier, right_shift):
    return rounding_divide_by_pot(
        sat_round_high_mul(x, multiplier), right_shift
    )

def main():
    candidates = [
        HERE / "weights",
        HERE.parent / "weights",
        HERE.parent.parent / "weights",
    ]
    weights_dir = next((p for p in candidates if (p / "dw_weights.mem").exists()), None)
    if weights_dir is None:
        raise FileNotFoundError(
            "weights klasoru bulunamadi. Scripti repo icinde calistirin "
            "ve repo kokunde weights/ klasorunun bulundugundan emin olun."
        )

    dw_weights = read_hex_signed(weights_dir / "dw_weights.mem", 8)
    dw_bias    = read_hex_signed(weights_dir / "dw_bias.mem", 32)
    fc_weights = read_hex_signed(weights_dir / "fc_weights.mem", 8)
    fc_bias    = read_hex_signed(weights_dir / "fc_bias.mem", 32)
    lut = [int(x,16) for x in (weights_dir/"softmax_exp_lut.mem").read_text().split()]

    DW_MULT = [1653229999,1516545207,2000799311,1159928266,
               1498403863,1285645282,2146175029,1756589032]
    DW_RSHIFT = [10,12,10,10,10,10,10,10]
    FC_MULT = 1932201080
    FC_RSHIFT = 11

    qin = [((i*37+13)%256)-128 for i in range(1960)]

    conv = []
    for t in range(25):
        for f in range(20):
            for d in range(8):
                acc = dw_bias[d]
                for kh in range(10):
                    ti = t*2 - 4 + kh
                    for kw in range(8):
                        fi = f*2 - 3 + kw
                        xc = qin[ti*40+fi] + 128 if 0 <= ti < 49 and 0 <= fi < 40 else 0
                        acc += xc * dw_weights[kh*64 + kw*8 + d]
                sc = multiply_quantized(acc, DW_MULT[d], DW_RSHIFT[d])
                conv.append(max(0, min(255, sc)))

    fc_acc = fc_bias[:]
    for i,y in enumerate(conv):
        for c in range(4):
            fc_acc[c] += y * fc_weights[c*4000+i]

    logits = []
    for a in fc_acc:
        q = multiply_quantized(a, FC_MULT, FC_RSHIFT) + 14
        logits.append(max(-128,min(127,q)))

    m = max(logits)
    exps = [4096 if m-x <= 0 else 0 if m-x >= 256 else lut[m-x] for x in logits]
    den = sum(exps)
    probs = [(e<<12)//den if den else 0 for e in exps]

    cls = 0
    for i in range(1,4):
        if logits[i] > logits[cls]:
            cls = i

    print("fc_acc      =", fc_acc)
    print("fc_logits   =", logits)
    print("probs Q0.12 =", probs)
    print("class       =", cls, ["SILENCE","UNKNOWN","YES","NO"][cls])

if __name__ == "__main__":
    main()
