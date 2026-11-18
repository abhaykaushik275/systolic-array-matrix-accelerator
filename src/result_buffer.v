
module result_buffer (
    input wire clk,
    input wire reset,

    // Capture the completed matrix result
    input wire capture_en,

    // 16 outputs from the systolic array
    input wire [511:0] c_in,

    // Stored 4x4 result matrix
    output reg [511:0] result_out,

    // Indicates that results have been captured
    output reg result_valid
);

    always @(posedge clk) begin

        if (reset) begin
            result_out  <= 512'b0;
            result_valid <= 1'b0;
        end

        else if (capture_en) begin
            result_out  <= c_in;
            result_valid <= 1'b1;
        end

    end

endmodule
