
module systolic_array_4x4 (

    input wire clk,
    input wire reset,
    input wire clear_acc,

    // Four signed INT8 operands for A
    input wire [31:0] a_in,

    // Four signed INT8 operands for B
    input wire [31:0] b_in,

    // Per-row and per-column validity
    input wire [3:0] a_valid,
    input wire [3:0] b_valid,

    // Sixteen signed INT32 outputs
    output wire [511:0] c_out

);

// --------------------------------------------------
// 1. Internal datapath connections
// --------------------------------------------------

wire signed [7:0] a_bus [0:3][0:4];
wire signed [7:0] b_bus [0:4][0:3];

wire signed [31:0] acc_bus [0:3][0:3];

// Validity propagation buses
wire a_valid_bus [0:3][0:4];
wire b_valid_bus [0:4][0:3];

genvar r, c;

// --------------------------------------------------
// 2. Boundary operand connections
// --------------------------------------------------

generate

    for (r = 0; r < 4; r = r + 1) begin : A_INPUT

        assign a_bus[r][0] = a_in[r*8 +: 8];

        assign a_valid_bus[r][0] = a_valid[r];

    end

    for (c = 0; c < 4; c = c + 1) begin : B_INPUT

        assign b_bus[0][c] = b_in[c*8 +: 8];

        assign b_valid_bus[0][c] = b_valid[c];

    end

endgenerate

// --------------------------------------------------
// 3. Instantiate 16 MAC PEs
// --------------------------------------------------

generate

    for (r = 0; r < 4; r = r + 1) begin : ROW

        for (c = 0; c < 4; c = c + 1) begin : COL

            mac_pe pe_inst (

                .clk(clk),
                .reset(reset),
                .clear_acc(clear_acc),

                .a_in(a_bus[r][c]),
                .b_in(b_bus[r][c]),

                .valid_a_in(a_valid_bus[r][c]),
                .valid_b_in(b_valid_bus[r][c]),

                .a_out(a_bus[r][c+1]),
                .b_out(b_bus[r+1][c]),

                .valid_a_out(a_valid_bus[r][c+1]),
                .valid_b_out(b_valid_bus[r+1][c]),

                .acc_out(acc_bus[r][c])

            );

        end

    end

endgenerate

// --------------------------------------------------
// 4. Pack all 16 accumulator outputs
// --------------------------------------------------

generate

    for (r = 0; r < 4; r = r + 1) begin : OUTPUT_ROW

        for (c = 0; c < 4; c = c + 1) begin : OUTPUT_COL

            assign c_out[(r*4+c)*32 +: 32]
                       = acc_bus[r][c];

        end

    end

endgenerate

endmodule
