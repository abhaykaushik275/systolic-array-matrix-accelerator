
module mac_pe (
    input clk,
    input reset,
    input wire clear_acc,

    input signed [7:0] a_in,
    input signed [7:0] b_in,

    input valid_a_in,
    input valid_b_in,

    output reg valid_a_out,
    output reg valid_b_out,

    output reg signed [31:0] acc_out,
    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out

);

    wire signed [15:0] product;

    assign product = a_in * b_in;

   always @(posedge clk) begin

    if (reset) begin
        acc_out      <= 0;
        a_out        <= 0;
        b_out        <= 0;
        valid_a_out  <= 0;
        valid_b_out  <= 0;
    end

    else begin

        a_out       <= a_in;
        b_out       <= b_in;

        valid_a_out <= valid_a_in;
        valid_b_out <= valid_b_in;

        if (clear_acc)
            acc_out <= 0;

        else if (valid_a_in && valid_b_in)
            acc_out <= acc_out +
                       {{16{product[15]}}, product};

    end
end
endmodule
