import os
import re

def main():
    log_path = "simulation.log"
    if not os.path.exists(log_path):
        # try default relative path if running from root
        log_path = "tb/T2.1_core_trace/simulation.log"
        if not os.path.exists(log_path):
            print("HATA: simulation.log bulunamadi!")
            return

    # Sentezlenen/Derlenen boot programinin ilk 20 buyruk PC adresi (Spike ISS / Referans Modeli)
    reference_trace = [
        "0x00000004", "0x00000008", "0x0000000c", "0x00000010",
        "0x00000014", "0x00000018", "0x0000001c", "0x0000000c",
        "0x00000010", "0x00000014", "0x00000018", "0x0000001c",
        "0x0000000c", "0x00000010", "0x00000014", "0x00000018",
        "0x0000001c", "0x0000000c", "0x00000010", "0x00000014"
    ]

    pc_pattern = re.compile(r"PC_ID=(0x[0-9a-fA-F]+)")
    extracted_pcs = []

    with open(log_path, "r") as f:
        for line in f:
            match = pc_pattern.search(line)
            if match:
                extracted_pcs.append(match.group(1).lower())

    print("======================================================================")
    print(" RISC-V CORE INSTRUCTION TRACE VS SPIKE ISS COMPARISON REPORT")
    print("======================================================================")
    
    match_count = 0
    mismatch_count = 0
    
    print(f"{'Adim':<6} | {'Simulasyon PC (Donanim)':<25} | {'Spike ISS (Referans)':<25} | {'Durum':<10}")
    print("-" * 75)
    
    # Karsilastir
    for idx, ref_pc in enumerate(reference_trace):
        if idx < len(extracted_pcs):
            sim_pc = extracted_pcs[idx]
            if sim_pc == ref_pc.lower():
                status = "UYUMLU"
                match_count += 1
            else:
                status = "HATA"
                mismatch_count += 1
            print(f"{idx+1:<6} | {sim_pc:<25} | {ref_pc:<25} | {status:<10}")
        else:
            print(f"{idx+1:<6} | {'N/A':<25} | {ref_pc:<25} | {'EKSIK':<10}")
            mismatch_count += 1
            
    print("-" * 75)
    total_checks = len(reference_trace)
    accuracy = (match_count / total_checks) * 100
    print(f"Dogrulama Sonucu: {match_count}/{total_checks} Uyumlu Adim | Basari Orani: {accuracy:.2f}%")
    
    if mismatch_count == 0:
        print("[BASARILI] RISC-V Cekirdek Komut Izleri referans model ile %100 uyumludur.")
        # Write report to markdown or print
    else:
        print("[HATA] Komut izlerinde uyumsuzluk tespit edildi!")

if __name__ == "__main__":
    main()
