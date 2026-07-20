# INT8 Convolution Core for Quantized CNN Acceleration on FPGA

A Verilog RTL implementation of a streaming, quantization-aware CNN convolution engine for edge FPGAs. Instead of buffering a whole image frame, the design reconstructs the 3×3 spatial neighborhood on the fly from a **1-pixel-per-clock stream**, and computes convolution using **signed INT8 arithmetic** in a **single-cycle-latency, register-bounded** MAC core with INT32 accumulation and saturation clipping.

Verified bit-exact against an independent Python Golden Model — **100% match, 676/676 pixels**, independently re-derived and confirmed byte-for-byte in this repository — and synthesized on Gowin EDA at **170.5 MHz** using **under 1% of device logic resources**.

📄 Full IEEE-format paper: [`docs/INT8_Convolution_Core_for_Quantized_CNN_Acceleration_on_FPGA.docx`](docs/INT8_Convolution_Core_for_Quantized_CNN_Acceleration_on_FPGA.docx)

---

## Authors
Lê Tiến Thành · Huỳnh Thiên Vũ · Hoàng Minh Nhật · Trịnh Trần Minh Quân
Advisor: M.S. Phạm Thế Vinh
Faculty of Semiconductor and Automotive Microchips, FPT University Ho Chi Minh City Campus, Vietnam
---

## Scope

This project isolates the **single-channel streaming datapath** — sliding-window generation plus INT8 MAC/clipping — as the unit of design and verification, prioritizing per-pixel latency, on-chip storage footprint, and bit-exact numerical correctness over channel-level parallelism. It is a **rigorously verified, resource-minimal streaming primitive**, suitable as a building block for larger multi-channel CNN accelerators, rather than a complete multi-channel engine.

The paper reports cross-check results on three test datasets (digit, object, footwear images). This repository ships the **fully reproducible Golden Model dataset for the digit ("so") test case** — image, kernel, expected output, and the generator script — as a self-contained, independently re-verified example. See [Verification](#verification) for details.

---

## Architecture

The system is organized as two cooperating pipeline stages: a **stream-based sliding window generator** and an **INT8 Convolution Core**, wired together in `top_module.v`.

<p align="center">
  <img src="docs/figures/fig1_overview.png" width="600" alt="Overall pixel-streaming architecture">
</p>

### 1. Stream-Based Sliding Window Generator (`sliding_window.v`)

- Two cascaded `line_buffer.v` instances (`lb0`, `lb1`), each a parameterizable shift-register FIFO of depth `IMG_WIDTH`, reconstruct three vertically aligned rows from a purely sequential pixel stream — no global 2D array is ever stored.
- A 3×3 register matrix (`p00`…`p22`) shifts spatially every clock cycle, holding the current convolution window as it slides across the frame.
- `out_valid` asserts once `row_cnt ≥ 2` and `col_cnt ≥ 2`, after a deterministic fill latency of `2×IMG_WIDTH + 2` cycles (58 cycles for a 28×28 image).
- **Throughput:** peaks at 1 valid window per clock cycle within a row; `out_valid` briefly deasserts for 2 cycles at the start of each new row while `col_cnt` re-establishes validity, then resumes at peak rate for the rest of the row.
- Implements Valid-Padding: 28×28 input → 26×26 (676-pixel) output.

<p align="center">
  <img src="docs/figures/fig2_linebuffer.png" width="500" alt="Cascaded dual line-buffer structure">
</p>

### 2. INT8 MAC Core & Saturation Clipping (`conv_core_int8.v`)

| Sub-module | Role |
|---|---|
| `mac_3x3.v` | Signed multiply–accumulate over the 3×3 window |
| `kernel_rom.v` | Stores up to 4 selectable 3×3 signed INT8 kernels; `kernel_sel = 0` (Sobel vertical, used for verification) is loaded via `$readmemh` from `kernel.hex` |
| `relu.v` | Optional ReLU stage (disabled during verification to match the Golden Model) |
| `quant_clip.v` | Restricts the INT32 accumulator back into the signed INT8 range `[-128, 127]`; supports an optional `SHIFT` parameter for fixed-point scaling (unused, `SHIFT = 0`, in the verified configuration) |

The nine-multiplier array, adder tree, and clipping logic sit between two register boundaries (input window/weights → registered output) as **purely combinational logic**: post-route static timing reports a critical path of only **2 logic levels**, so the core adds exactly **one clock cycle** of latency — a shallow, register-bounded datapath rather than a deeply pipelined multi-stage MAC.

**Bit-width rationale:** each operand is signed INT8 `[-128, 127]`. The largest-magnitude partial product is `(-128)×(-128) = 16,384` (partial-product range `[-16,256, 16,384]`), which exceeds INT8 and requires signed INT16. Summed over 9 taps, the theoretical extreme sum spans `[-146,304, 147,456]`, exceeding INT16, so each 16-bit product is sign-extended into a signed INT32 accumulator before `quant_clip.v` restricts the result back to INT8 — mirroring NumPy's `np.clip()`.

<p align="center">
  <img src="docs/figures/fig3_mac.png" width="500" alt="3x3 MAC block structure">
</p>

---

## Verification

Verification is layered across **three testbenches**, each covering a different concern:

| Testbench | What it checks | Reference |
|---|---|---|
| `tb_conv_core_int8.v` | `conv_core_int8` + `kernel_rom` arithmetic, self-checked against an expected value computed *inside the testbench itself*, on a synthetic 8×8 image (values 1–64) | None external — pure RTL self-check |
| `tb_compare_python_rtl.v` | Same arithmetic core, cross-checked against an **independent Python Golden Model** on a real 28×28 image | `image.hex`, `kernel.hex`, `expected_output.hex` |
| `tb_top_module.v` | The full streaming pipeline (`sliding_window` → `conv_core_int8`), pixel-by-pixel, confirms fill latency and `in_valid`/`out_valid` timing | Waveform inspection (Fig. 5) |

The Golden Model is deliberately written in Python — a different language/paradigm than the RTL — to avoid common-mode failures. `golden_model/golden_model.py` reads a streamed image (`image.hex`) and a kernel (`kernel.hex`), computes the same signed multiply-accumulate-and-clip arithmetic as `mac_3x3.v` + `quant_clip.v` over every one of the 676 valid output positions, and writes `expected_output.hex` in the same row-major order `tb_compare_python_rtl.v` expects (`out_index = row*26 + col`).

**This repository's `data/` files have been independently re-verified**: running `golden_model.py` on `data/image.hex` reproduces `data/expected_output.hex` **byte-for-byte**, confirming the reproducibility of the reported 676/676 (100%) match.

<p align="center">
  <img src="docs/figures/fig4_modelsim.png" width="500" alt="ModelSim PASS/FAIL transcript"><br>
  <img src="docs/figures/fig5_waveform.png" width="500" alt="in_valid / out_valid waveform">
</p>

### Running the simulation

`tb_compare_python_rtl.v` loads its inputs with hardcoded, path-less filenames:

```verilog
$readmemh("image.hex", image_mem);
$readmemh("expected_output.hex", expected_mem);
```

so **copy the three files from `data/` into the directory you run ModelSim from** before simulating:

```bash
cp data/image.hex data/kernel.hex data/expected_output.hex sim/
cd sim
vsim -do run_modelsim.do
```

A clean run reports `# Errors: 0, Warnings: 0`, followed by `PASS = 676`, `FAIL = 0`.

---

## Synthesis Results (Gowin EDA)

| Metric | Utilization | Role |
|---|---|---|
| LUTs | 84 | Sliding-window control logic, MAC adder tree |
| Registers (Flip-Flops) | 105 | Line-buffer shift chain, 3×3 window registers |
| ALUs | 43 | Arithmetic operations in the Convolution Core |
| DSP Blocks | 5 (1× MULT12X12, 4× MULTADDALU12X12) | Parallel INT8×INT8 multiplication |
| BSRAM | 1 (~2% of device block RAM) | Cascaded line-buffer storage |
| **Max Frequency (Fmax)** | **170.5 MHz** | Post-route, 100 MHz constraint, critical path of 2 logic levels |

Logic and register utilization remain **under 1%** of the target Gowin device; BSRAM usage is slightly higher at **~2%**, since the two cascaded line buffers are the only components mapped to block RAM.

<p align="center">
  <img src="docs/figures/fig6_resources.png" width="500" alt="Gowin resource utilization report"><br>
  <img src="docs/figures/fig7_fmax.png" width="500" alt="Gowin Fmax report">
</p>

---

## Repository Structure

```
.
├── rtl/                         # Verilog RTL source
│   ├── line_buffer.v
│   ├── sliding_window.v
│   ├── mac_3x3.v
│   ├── kernel_rom.v
│   ├── relu.v
│   ├── quant_clip.v
│   ├── conv_core_int8.v
│   └── top_module.v              # wires sliding_window + kernel_rom + conv_core_int8
├── sim/                          # Testbenches + ModelSim scripts
│   ├── tb_conv_core_int8.v        # unit test: synthetic 8x8 image, self-checked
│   ├── tb_compare_python_rtl.v    # cross-check: real 28x28 image vs. Python golden model
│   ├── tb_top_module.v            # streaming/timing test: full pipeline, waveform
│   ├── run_modelsim.do
│   └── wave.do
├── golden_model/                 # Python data-generation / reference model
│   ├── image_to_hex.py           # single image -> .hex
│   ├── convert_all.py            # batch: folder of images -> .hex
│   └── golden_model.py           # full-image convolution + clip -> expected_output.hex
├── data/                         # Verified test vectors (.hex)
│   ├── image.hex                 # 28x28 digit test image (signed INT8)
│   ├── kernel.hex                # Sobel-vertical kernel (signed INT8)
│   └── expected_output.hex       # 26x26 golden reference output (signed INT8)
├── docs/
│   ├── INT8_Convolution_Core_for_Quantized_CNN_Acceleration_on_FPGA.docx
│   └── figures/
├── LICENSE
├── .gitignore
└── README.md
```

---

## Future Work

- AXI4-Stream interface integration for SoC-level composability
- Same-Padding control logic to preserve edge resolution
- Multi-kernel / multi-channel support
- Nonzero trained bias values, plus additional layers (Max Pooling, Fully Connected) toward a complete accelerator
- On-hardware measurement of Fmax, power, and latency on physical FPGA

---

## References

1. M. Tasci, A. Istanbullu, V. Tumen, and S. Kosunalp, "FPGA-QNN: Quantized Neural Network Hardware Acceleration on FPGAs," *Applied Sciences*, vol. 15, no. 2, p. 688, Jan. 2025.
2. C. Zhang, P. Li, G. Sun, Y. Guan, B. Xiao, and J. Cong, "Optimizing FPGA-based Accelerator Design for Deep Convolutional Neural Networks," in *Proc. 2015 ACM/SIGDA Int. Symp. Field-Programmable Gate Arrays (FPGA '15)*, Monterey, CA, USA, 2015, pp. 161–170.
3. C. Latotzke, T. Ciesielski, and T. Gemmeke, "Design of High-Throughput Mixed-Precision CNN Accelerators on FPGA," in *Proc. 32nd Int. Conf. Field-Programmable Logic and Applications (FPL)*, 2022.

---

## License

This project is released under the [MIT License](LICENSE).
