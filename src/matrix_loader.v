
module matrix_loader (
    input wire clk,
    input wire reset,

    // Load control
    input wire load_en,

    // Two 4x4 matrices: 16 signed INT8 values each
    input wire [127:0] matrix_a,
    input wire [127:0] matrix_b,

    // Selects the input cycle (0 to 3)
    input wire [1:0] input_index,

    // Four INT8 values packed into each output
    output reg [31:0] a_out,
    output reg [31:0] b_out,

    // Indicates matrices have been loaded
    output reg data_ready
);

    // Internal matrix storage
    reg [127:0] A_reg;
    reg [127:0] B_reg;

    integer i;

    // --------------------------------
    // 1. Store the input matrices
    // --------------------------------
    always @(posedge clk) begin

        if (reset) begin
            A_reg      <= 128'b0;
            B_reg      <= 128'b0;
            data_ready <= 1'b0;
        end

        else if (load_en) begin
            A_reg      <= matrix_a;
            B_reg      <= matrix_b;
            data_ready <= 1'b1;
        end

    end

    // --------------------------------
    // 2. Select the next operands
    // --------------------------------
    always @(*) begin

        a_out = 32'b0;
        b_out = 32'b0;

        if (data_ready) begin

            for (i = 0; i < 4; i = i + 1) begin

                // A: Select one element from each row
                a_out[i*8 +: 8] =
                    A_reg[(i*4 + input_index)*8 +: 8];

                // B: Select one element from the selected row
                // Each output lane corresponds to a column
                b_out[i*8 +: 8] =
                    B_reg[(input_index*4 + i)*8 +: 8];

            end

        end

    end

endmodule
