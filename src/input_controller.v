
module input_controller (
    input wire clk,
    input wire reset,
    input wire start,

    // Indicates matrices are loaded
    input wire data_ready,

    // Control signal for all PE accumulators
    output reg clear_acc,

    // Selects matrix elements from matrix_loader
    output reg [1:0] input_index,

    // Valid signals for the four A and B lanes
    output reg [3:0] a_valid,
    output reg [3:0] b_valid,

    // Status signals
    output reg busy,
    output reg done
);

    // --------------------------------
    // FSM state definitions
    // --------------------------------

    parameter IDLE    = 3'b000;
    parameter CLEAR   = 3'b001;
    parameter LOAD    = 3'b010;
    parameter COMPUTE = 3'b011;
    parameter DRAIN   = 3'b100;
    parameter DONE    = 3'b101;

    reg [2:0] state;

    // Counters
    reg [1:0] input_count;
    reg [2:0] drain_count;

    // --------------------------------
    // 1. Sequential FSM
    // --------------------------------

    always @(posedge clk) begin

        if (reset) begin
            state       <= IDLE;
            input_count <= 0;
            drain_count <= 0;
        end

        else begin

            case (state)

                // Wait for start
                IDLE: begin
                    if (start) begin
                        state       <= CLEAR;
                        input_count <= 0;
                        drain_count <= 0;
                    end
                end

                // Clear all PE accumulators
                CLEAR: begin
                    state <= LOAD;
                end

                // Wait until matrices are available
                LOAD: begin
                    if (data_ready) begin
                        input_count <= 0;
                        state <= COMPUTE;
                    end
                end

                // Supply four input beats
                COMPUTE: begin

                    if (input_count == 2'd3) begin
                        input_count <= 0;
                        drain_count <= 0;
                        state <= DRAIN;
                    end

                    else begin
                        input_count <= input_count + 1'b1;
                    end

                end

                // Wait for the pipeline to finish
                DRAIN: begin

                    if (drain_count == 3'd5) begin
                        state <= DONE;
                    end

                    else begin
                        drain_count <= drain_count + 1'b1;
                    end

                end

                // Signal completion
                DONE: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase

        end
    end

    // --------------------------------
    // 2. Output control signals
    // --------------------------------

    always @(*) begin

        // Default values
        clear_acc  = 1'b0;
        input_index = input_count;
        a_valid    = 4'b0000;
        b_valid    = 4'b0000;
        busy       = 1'b0;
        done       = 1'b0;

        case (state)

            IDLE: begin
                busy = 1'b0;
            end

            CLEAR: begin
                clear_acc = 1'b1;
                busy = 1'b1;
            end

            LOAD: begin
                busy = 1'b1;
            end

            COMPUTE: begin
                a_valid = 4'b1111;
                b_valid = 4'b1111;
                busy = 1'b1;
            end

            DRAIN: begin
                busy = 1'b1;
            end

            DONE: begin
                done = 1'b1;
            end

            default: begin
                busy = 1'b0;
            end

        endcase

    end

endmodule
