`timescale 1ns / 1ps

module system_top (

    // =========================================================
    // CLOCK / RESET
    // =========================================================

    input  wire clk,
    input  wire reset,


    // =========================================================
    // Pmod KYPD
    //
    // KYPD rows  -> FPGA inputs
    // KYPD cols  -> FPGA outputs
    // =========================================================

    input  wire [3:0] keypad_row,
    output wire [3:0] keypad_col,


    // =========================================================
    // Pmod OLED
    // =========================================================

    output wire oled_cs,
    output wire oled_sdin,
    output wire oled_sclk,
    output wire oled_dc,
    output wire oled_res,
    output wire oled_vbatc,
    output wire oled_vddc,


    // =========================================================
    // OPTIONAL DEBUG / STATUS OUTPUTS
    // =========================================================

    output wire busy,
    output wire done,
    output wire result_valid,

    output wire [511:0] result_out

);


    // =========================================================
    // INTERNAL CONNECTIONS
    // =========================================================


    // ---------------------------------------------------------
    // keypad_scanner -> matrix_input
    // ---------------------------------------------------------

    wire       key_valid;
    wire [3:0] key_value;


    // ---------------------------------------------------------
    // matrix_input -> accelerator_wrapper
    // ---------------------------------------------------------

    wire [127:0] matrix_a;
    wire [127:0] matrix_b;

    wire matrices_ready;


    // ---------------------------------------------------------
    // matrix_input -> oled_controller
    // ---------------------------------------------------------

    wire [2:0] display_state;
    wire [4:0] element_count;
    wire [3:0] current_value;


    // ---------------------------------------------------------
    // accelerator_wrapper -> oled_controller
    // ---------------------------------------------------------

    wire [511:0] accelerator_result;
    wire         accelerator_result_valid;


    // =========================================================
    // 1. KEYPAD SCANNER
    //
    // Physically scans the 4x4 Pmod keypad.
    //
    // Outputs:
    //
    // key_valid = 1 for one clock when a new key is detected
    // key_value = decoded key
    //
    // Key encoding from keypad_scanner.v:
    //
    // 0-9 -> 0-9
    // A   -> 4'hA
    // B   -> 4'hB
    // C   -> 4'hC
    // D   -> 4'hD
    // *   -> 4'hE
    // #   -> 4'hF
    //
    // =========================================================

    keypad_scanner keypad_scanner_inst (

        .clk(clk),
        .reset(reset),

        .row(keypad_row),
        .col(keypad_col),

        .key_valid(key_valid),
        .key_value(key_value)

    );


    // =========================================================
    // 2. MATRIX INPUT
    //
    // Receives decoded keypad keys.
    //
    // It stores:
    //
    //      Matrix A = 16 x 8-bit values
    //      Matrix B = 16 x 8-bit values
    //
    // and packs them into:
    //
    //      matrix_a = 128 bits
    //      matrix_b = 128 bits
    //
    // When # is pressed after both matrices are entered,
    // matrices_ready becomes HIGH for one clock.
    //
    // It also generates the information required by the OLED:
    //
    //      display_state
    //      element_count
    //      current_value
    //
    // =========================================================

    matrix_input matrix_input_inst (

        .clk(clk),
        .reset(reset),

        // From keypad scanner
        .key_valid(key_valid),
        .key_value(key_value),

        // To accelerator wrapper
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrices_ready(matrices_ready),

        // To OLED controller
        .display_state(display_state),
        .element_count(element_count),
        .current_value(current_value)

    );


    // =========================================================
    // 3. ACCELERATOR WRAPPER
    //
    // Receives the two completed matrices from matrix_input.
    //
    // The wrapper generates:
    //
    //      load_en
    //      start
    //
    // for the existing top_level accelerator.
    //
    // Internally:
    //
    //      accelerator_wrapper
    //              |
    //              v
    //          top_level
    //
    // =========================================================

    accelerator_wrapper accelerator_wrapper_inst (

        .clk(clk),
        .reset(reset),

        // From matrix_input
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrices_ready(matrices_ready),

        // Accelerator status
        .busy(busy),
        .done(done),
        .result_valid(accelerator_result_valid),

        // Accelerator result
        .result_out(accelerator_result)

    );


    // =========================================================
    // 4. OLED CONTROLLER
    //
    // Converts:
    //
    //      display_state
    //      element_count
    //      current_value
    //
    // and
    //
    //      result_out
    //      result_valid
    //
    // into SPI signals for the Pmod OLED.
    //
    // =========================================================

    oled_controller oled_controller_inst (

        .clk(clk),
        .reset(reset),

        // From matrix_input
        .display_state(display_state),
        .element_count(element_count),
        .current_value(current_value),

        // From accelerator
        .result_out(accelerator_result),
        .result_valid(accelerator_result_valid),

        // To Pmod OLED
        .oled_cs(oled_cs),
        .oled_sdin(oled_sdin),
        .oled_sclk(oled_sclk),
        .oled_dc(oled_dc),
        .oled_res(oled_res),
        .oled_vbatc(oled_vbatc),
        .oled_vddc(oled_vddc)

    );


    // =========================================================
    // 5. CONNECT ACCELERATOR RESULT TO SYSTEM OUTPUT
    //
    // This is optional, but allows you to observe the result
    // from system_top as well.
    // =========================================================

    assign result_out   = accelerator_result;
    assign result_valid = accelerator_result_valid;


endmodule