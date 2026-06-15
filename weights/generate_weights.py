import os

def main():
    weights_dir = "c:/Arkhe_2026/weights"
    os.makedirs(weights_dir, exist_ok=True)

    # 1. dw_weights.mem: 640 lines of '01'
    with open(os.path.join(weights_dir, "dw_weights.mem"), "w") as f:
        for _ in range(640):
            f.write("01\n")

    # 2. dw_bias.mem: 8 lines of '00000000'
    with open(os.path.join(weights_dir, "dw_bias.mem"), "w") as f:
        for _ in range(8):
            f.write("00000000\n")

    # 3. fc_weights.mem: 16000 lines, 2nd index is '04', others '00'
    with open(os.path.join(weights_dir, "fc_weights.mem"), "w") as f:
        for i in range(16000):
            if i == 2:
                f.write("04\n")
            else:
                f.write("00\n")

    # 4. fc_bias.mem: 4 lines: 0, 0, 0, 1000 (0x3e8)
    with open(os.path.join(weights_dir, "fc_bias.mem"), "w") as f:
        f.write("00000000\n")
        f.write("00000000\n")
        f.write("00000000\n")
        f.write("000003e8\n")

    print("Weights and bias memory files generated successfully!")

if __name__ == "__main__":
    main()
