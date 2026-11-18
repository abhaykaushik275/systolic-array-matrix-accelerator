
module input_skew (
    input wire clk,
    input wire reset,

    input wire [31:0] a_in,
    input wire [31:0] b_in,

    input wire [3:0] a_valid,
    input wire [3:0] b_valid,

    output wire [31:0] a_skew,
    output wire [31:0] b_skew,

    output wire [3:0] a_valid_skew,
    output wire [3:0] b_valid_skew
);

    // Delay registers
    reg signed [7:0] a_delay [0:3][0:2];
    reg signed [7:0] b_delay [0:3][0:2];

    reg a_valid_delay [0:3][0:2];
    reg b_valid_delay [0:3][0:2];

    genvar i;

    generate
        for (i = 0; i < 4; i = i + 1) begin : SKEW

            if (i == 0) begin

                assign a_skew[i*8 +: 8] = a_in[i*8 +: 8];
                assign b_skew[i*8 +: 8] = b_in[i*8 +: 8];

                assign a_valid_skew[i] = a_valid[i];
                assign b_valid_skew[i] = b_valid[i];

            end

            else begin
                
                integer j;
                
                always @(posedge clk) begin

                    if (reset) begin
                        for (j = 0; j < i; j = j + 1) begin
                            a_delay[i][j] <= 0;
                            b_delay[i][j] <= 0;

                            a_valid_delay[i][j] <= 0;
                            b_valid_delay[i][j] <= 0;
                        end
                    end

                    else begin

                        a_delay[i][0] <= a_in[i*8 +: 8];
                        b_delay[i][0] <= b_in[i*8 +: 8];

                        a_valid_delay[i][0] <= a_valid[i];
                        b_valid_delay[i][0] <= b_valid[i];

                        for (j = 1; j < i; j = j + 1) begin

                            a_delay[i][j] <= a_delay[i][j-1];
                            b_delay[i][j] <= b_delay[i][j-1];

                            a_valid_delay[i][j] <= a_valid_delay[i][j-1];
                            b_valid_delay[i][j] <= b_valid_delay[i][j-1];

                        end
                    end
                end

                assign a_skew[i*8 +: 8] = a_delay[i][i-1];
                assign b_skew[i*8 +: 8] = b_delay[i][i-1];

                assign a_valid_skew[i] = a_valid_delay[i][i-1];
                assign b_valid_skew[i] = b_valid_delay[i][i-1];

            end
        end
    endgenerate

endmodule
