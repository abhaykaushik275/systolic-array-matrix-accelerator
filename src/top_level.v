
module top_level (
    input wire clk,
    input wire reset,
    input wire start,

    // Matrix loading interface
    input wire load_en,
    input wire [127:0] matrix_a,
    input wire [127:0] matrix_b,

    // Status outputs
    output wire busy,
    output wire done,
    output wire result_valid,

    // Final 4x4 matrix: 16 x 32-bit values
    output wire [511:0] result_out
);

    // ------------------------------------------------
    // Internal wires
    // ------------------------------------------------

    // Controller to matrix loader
    wire [1:0] input_index;
    wire data_ready;

    // Controller control signals
    wire clear_acc;
    wire [3:0] a_valid;
    wire [3:0] b_valid;

    // Matrix loader outputs
    wire [31:0] a_loader_out;
    wire [31:0] b_loader_out;

    // Skew module outputs
    wire [31:0] a_skew_out;
    wire [31:0] b_skew_out;
    wire [3:0] a_skew_valid;
    wire [3:0] b_skew_valid;

    // Systolic array output
    wire [511:0] c_out;

    // Result capture control
    wire capture_en;

    // ------------------------------------------------
    // 1. Matrix Loader
    // ------------------------------------------------

    matrix_loader matrix_loader_inst (
        .clk(clk),
        .reset(reset),
        .load_en(load_en),

        .matrix_a(matrix_a),
        .matrix_b(matrix_b),

        .input_index(input_index),

        .a_out(a_loader_out),
        .b_out(b_loader_out),

        .data_ready(data_ready)
    );

    // ------------------------------------------------
    // 2. Input Controller
    // ------------------------------------------------

    input_controller input_controller_inst (
        .clk(clk),
        .reset(reset),
        .start(start),

        .data_ready(data_ready),

        .clear_acc(clear_acc),
        .input_index(input_index),

        .a_valid(a_valid),
        .b_valid(b_valid),

        .busy(busy),
        .done(done)
    );

    // ------------------------------------------------
    // 3. Input Skew
    // ------------------------------------------------

    input_skew input_skew_inst (
        .clk(clk),
        .reset(reset),

        .a_in(a_loader_out),
        .b_in(b_loader_out),

        .a_valid(a_valid),
        .b_valid(b_valid),

        .a_skew(a_skew_out),
        .b_skew(b_skew_out),

        .a_valid_skew(a_skew_valid),
        .b_valid_skew(b_skew_valid)
    );

    // ------------------------------------------------
    // 4. 4x4 Systolic Array
    // ------------------------------------------------

    systolic_array_4x4 systolic_array_inst (
        .clk(clk),
        .reset(reset),
        .clear_acc(clear_acc),

        .a_in(a_skew_out),
        .b_in(b_skew_out),

        .a_valid(a_skew_valid),
        .b_valid(b_skew_valid),

        .c_out(c_out)
    );

    // ------------------------------------------------
    // 5. Result Buffer
    // ------------------------------------------------

    // Capture the result when the controller asserts done.
    assign capture_en = done;

    result_buffer result_buffer_inst (
        .clk(clk),
        .reset(reset),

        .capture_en(capture_en),
        .c_in(c_out),

        .result_out(result_out),
        .result_valid(result_valid)
    );

endmodule
