# NPU expanded accuracy evidence - 2026-09-06

Completed RTL compute-engine simulation: 1,400 inferences, one initial reset, no reset between inputs. Start is held until busy acknowledges it; in DONE, the engine first returns to IDLE. This is a direct engine test, not a new FPGA board run.

| Subset | Count | TFLite correct | RTL correct | RTL accuracy |
|---|---:|---:|---:|---:|
| speech | 1200 | 1000 | 1000 | 83.33% |
| synthetic_silence | 100 | 94 | 94 | 94.00% |
| labelled_combined | 1300 | 1094 | 1094 | 84.15% |
| YES | 400 | 372 | 372 | 93.00% |
| NO | 400 | 347 | 347 | 86.75% |
| UNKNOWN | 400 | 281 | 281 | 70.25% |
| SILENCE | 100 | 94 | 94 | 94.00% |

Official TFLite vs RTL class disagreements: 0/1400.
RTL vs integer reference (class and four Q12 outputs) mismatching inputs: 0/1400.

The 100 stress tensors have no semantic class labels, so they are excluded from classification accuracy. They include constant -128/-1/0/1/127, alternating extremes, impulses, and seeded random INT8 inputs. Compare their decisions with TFLite and numeric results with the independent software execution of the RTL arithmetic.

## Sampling and scope

- 1,200 distinct WAV files: 400 yes, 400 no, 400 unknown pooled from down/go/left/right/stop/up. All previous 75 speech files were excluded. Selection is frozen before either model is run; seed 20260906.
- 100 synthetic silence inputs (zero or very small integer noise) are reported separately; these do not replace real environmental recordings.
- Input tensors use the existing floating-point host frontend. Both classifiers receive exactly the same 1960 INT8 values. This does not prove bit-exact official fixed-point audio preprocessing.
- This is a stratified sample of mini_speech_commands, not an official held-out jury dataset. Training overlap and speaker overlap are unknown. The combined percentage depends on the selected class proportions.
- The measured reference-accuracy window applies only to this evaluated sample. Agreement with the reference is distinct from accuracy against ground-truth labels.
- The test instantiates the NPU compute engine and synchronous TCM model. It does not retest CPU, UART, DMA, AXI or physical ASIC timing. Production RTL and the working FPGA package were not edited.

## Evidence and reproduction

- report.json: measured subsets, confusion matrices (SILENCE, UNKNOWN, YES, NO), mismatches and SHA256 evidence.
- accuracy_dataset.json / selection.json: frozen selection, source/input/model hashes and per-input software outputs.
- sim/accuracy/sim.log: all 1,400 actual RTL result rows; accuracy_result.json: simulator outcome.
- prepare_accuracy.py, run_accuracy.py, summarize.py: preparation, Xsim execution and assertions. Run in this directory with the same Python dependencies and Vivado installation as the prior closure suite.
- The source archive is reused from ../closure_20260905/mini_speech_commands.zip; https://www.tensorflow.org/tutorials/audio/simple_audio

Commands:
```powershell
python prepare_accuracy.py
python run_accuracy.py
python summarize.py
python make_readme.py
```
