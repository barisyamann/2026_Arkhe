from pathlib import Path

SRC = Path("weights/fc_weights.mem")
DST = Path("weights/fc_weights_packed32.mem")

lines = [x.strip() for x in SRC.read_text().splitlines() if x.strip()]
weights = [int(x, 16) for x in lines]

if len(weights) != 16000:
    raise SystemExit(f"HATA: 16000 weight bekleniyordu, {len(weights)} bulundu.")

packed = []
for i in range(4000):
    # fc_weights.mem yerleşimi:
    #   0..3999      -> class 0 (Silence)
    #   4000..7999   -> class 1 (Unknown)
    #   8000..11999  -> class 2 (Yes)
    #   12000..15999 -> class 3 (No)
    c0 = weights[i]
    c1 = weights[4000 + i]
    c2 = weights[8000 + i]
    c3 = weights[12000 + i]

    # 32-bit SRAM word:
    # [31:24] class3, [23:16] class2, [15:8] class1, [7:0] class0
    word = c0 | (c1 << 8) | (c2 << 16) | (c3 << 24)
    packed.append(f"{word:08x}")

DST.write_text("\n".join(packed) + "\n")
print(f"OK: {len(packed)} adet 32-bit kelime yazildi -> {DST}")
