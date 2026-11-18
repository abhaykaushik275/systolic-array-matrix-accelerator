`timescale 1ns / 1ps

module accelerator_wrapper (

    input wire clk,
    input wire reset,

    // =========================================================
    // From matrix_input
    // =========================================================

    input wire [127:0] matrix_a,
    input wire [127:0] matrix_b,

    // One-clock pulse indicating that A and B are confirmed
    input wire matrices_ready,

    // =========================================================
    // Accelerator outputs
    // =========================================================

    output wire busy,
    output wire done,
    output wire result_valid,

    output wire [511:0] result_out

);


    // =========================================================
    // INTERNAL CONTROL SIGNALS
    // =========================================================

    reg load_en;
    reg start;

    wire top_busy;
    wire top_done;
    wire top_result_valid;
    wire top_data_ready;

    wire [511:0] top_result;


    // =========================================================
    // FSM STATES
    // =========================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_LOAD       = 3'd1;
    localparam STATE_WAIT_READY = 3'd2;
    localparam STATE_START      = 3'd3;
    localparam STATE_COMPUTE    = 3'd4;
    localparam STATE_DONE       = 3'd5;

    reg [2:0] state;


    // =========================================================
    // OUTPUT CONNECTIONS
    // =========================================================

    assign busy         = top_busy;
    assign done         = top_done;
    assign result_valid = top_result_valid;

    assign result_out   = top_result;


    // =========================================================
    // EXISTING ACCELERATOR
    // =========================================================

    top_level accelerator_inst (

        .clk(clk),
        .reset(reset),

        .start(start),

        .load_en(load_en),

        .matrix_a(matrix_a),
        .matrix_b(matrix_b),

        .busy(top_busy),
        .done(top_done),
        .result_valid(top_result_valid),

        .data_ready(top_data_ready),

        .result_out(top_result)

    );


    // =========================================================
    // CONTROL FSM
    // =========================================================

    always @(posedge clk) begin

        if (reset) begin

            state   <= STATE_IDLE;

            load_en <= 1'b0;
            start   <= 1'b0;

        end

        else begin

            // Both control signals are pulses.
            // Keep them LOW unless explicitly asserted.

            load_en <= 1'b0;
            start   <= 1'b0;


            case (state)

                // =================================================
                // IDLE
                //
                // Wait for matrix_input to confirm A and B.
                // =================================================

                STATE_IDLE: begin

                    if (matrices_ready) begin

                        state <= STATE_LOAD;

                    end

                end


                // =================================================
                // LOAD
                //
                // Give matrix_loader a one-clock load_en pulse.
                // =================================================

                STATE_LOAD: begin

                    load_en <= 1'b1;

                    state <= STATE_WAIT_READY;

                end


                // =================================================
                // WAIT FOR MATRIX LOADER
                //
                // matrix_loader asserts data_ready once its
                // internal loading process is complete.
                // =================================================

                STATE_WAIT_READY: begin

                    if (top_data_ready) begin

                        state <= STATE_START;

                    end

                end


                // =================================================
                // START
                //
                // Give input_controller a one-clock start pulse.
                // =================================================

                STATE_START: begin

                    start <= 1'b1;

                    state <= STATE_COMPUTE;

                end


                // =================================================
                // COMPUTE
                //
                // Let the existing accelerator run.
                // =================================================

                STATE_COMPUTE: begin

                    if (top_done) begin

                        state <= STATE_DONE;

                    end

                end


                // =================================================
                // DONE
                //
                // result_out/result_valid are now available.
                //
                // Wait for matrices_ready to return LOW before
                // accepting another operation.
                // =================================================

                STATE_DONE: begin

                    if (!matrices_ready) begin

                        state <= STATE_IDLE;

                    end

                end


                // =================================================
                // DEFAULT
                // =================================================

                default: begin

                    state <= STATE_IDLE;

                end

            endcase

        end

    end

endmodule