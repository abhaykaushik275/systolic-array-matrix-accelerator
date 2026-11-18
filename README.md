# 4x4 INT8 Systolic-Array Matrix Accelerator

A Verilog matrix-multiplication accelerator built around a 4x4 output-stationary systolic array. Matrices are entered on a Pmod keypad and the result is shown on a Pmod OLED.

## Design
- 16 signed INT8 multiply-accumulate processing elements with 32-bit accumulators (`mac_pe.v`, `systolic_array_4X4.v`)
- Input skewing, matrix loader, FSM input controller and result buffer (`input_skew.v`, `matrix_loader.v`, `input_controller.v`, `result_buffer.v`, `top_level.v`)
- Keypad scanner for matrix entry (`keypad_scanner.v`, `matrix_input.v`)
- SPI controller for the OLED display (`oled_controller.v`, 100 MHz clock, 1 MHz SPI)
- Full system integration (`accelerator_wrapper.v`, `system_top.v`)

## Data flow
Keypad -> `keypad_scanner` -> `matrix_input` (A and B, 16 x INT8 each) -> `accelerator_wrapper` -> `top_level` (loader, skew, systolic array, result buffer) -> `oled_controller` -> Pmod OLED
