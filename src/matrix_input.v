`timescale 1ns / 1ps

module matrix_input (

    input wire clk,
    input wire reset,

    // =========================================================
    // Keypad interface
    //
    // key_value:
    //   0-9 = numbers
    //   A   = 4'hA
    //   B   = 4'hB
    //   *   = 4'hE
    //   #   = 4'hF
    // =========================================================

    input wire       key_valid,
    input wire [3:0] key_value,

    // =========================================================
    // Matrix outputs
    // =========================================================

    output reg [127:0] matrix_a,
    output reg [127:0] matrix_b,

    // Goes HIGH for one clock when # confirms both matrices
    output reg matrices_ready,

    // =========================================================
    // OLED/status information
    // =========================================================

    output reg [2:0] display_state,
    output reg [4:0] element_count,
    output reg [3:0] current_value

);

    // =========================================================
    // STATES
    // =========================================================

    localparam STATE_A     = 2'd0;
    localparam STATE_B     = 2'd1;
    localparam STATE_READY = 2'd2;

    // OLED display states
    localparam DISP_A      = 3'd0;
    localparam DISP_B      = 3'd1;
    localparam DISP_READY  = 3'd2;
    localparam DISP_RESET  = 3'd3;

    reg [1:0] state;

    // =========================================================
    // INTERNAL MATRIX STORAGE
    // =========================================================

    reg [7:0] A [0:15];
    reg [7:0] B [0:15];

    integer i;

    // =========================================================
    // MAIN FSM
    // =========================================================

    always @(posedge clk) begin

        if (reset) begin

            state          <= STATE_A;

            matrix_a       <= 128'd0;
            matrix_b       <= 128'd0;

            matrices_ready <= 1'b0;

            element_count  <= 5'd0;
            current_value  <= 4'd0;

            display_state  <= DISP_A;

            for (i = 0; i < 16; i = i + 1) begin
                A[i] <= 8'd0;
                B[i] <= 8'd0;
            end

        end

        else begin

            // matrices_ready is a one-clock pulse
            matrices_ready <= 1'b0;


            // =================================================
            // PROCESS KEYPAD INPUT
            // =================================================

            if (key_valid) begin

                case (state)

                    // =========================================
                    // MATRIX A
                    // =========================================

                    STATE_A: begin

                        // -------------------------------------
                        // 0-9
                        // -------------------------------------

                        if (key_value <= 4'd9) begin

                            A[element_count] <= {
                                4'd0,
                                key_value
                            };

                            current_value <= key_value;

                            // Last element of A
                            if (element_count == 5'd15) begin

                                element_count <= 5'd0;

                                state <= STATE_B;

                                display_state <= DISP_B;

                                current_value <= 4'd0;

                            end

                            else begin

                                element_count <=
                                    element_count + 1'b1;

                            end

                        end


                        // -------------------------------------
                        // A key
                        // Restart Matrix A entry
                        // -------------------------------------

                        else if (key_value == 4'hA) begin

                            state <= STATE_A;

                            element_count <= 5'd0;

                            current_value <= 4'd0;

                            display_state <= DISP_A;

                            for (i = 0; i < 16; i = i + 1)
                                A[i] <= 8'd0;

                        end


                        // -------------------------------------
                        // * = RESET EVERYTHING
                        // -------------------------------------

                        else if (key_value == 4'hE) begin

                            state <= STATE_A;

                            element_count <= 5'd0;

                            current_value <= 4'd0;

                            display_state <= DISP_RESET;

                            for (i = 0; i < 16; i = i + 1) begin
                                A[i] <= 8'd0;
                                B[i] <= 8'd0;
                            end

                            matrix_a <= 128'd0;
                            matrix_b <= 128'd0;

                        end

                    end


                    // =========================================
                    // MATRIX B
                    // =========================================

                    STATE_B: begin

                        // -------------------------------------
                        // 0-9
                        // -------------------------------------

                        if (key_value <= 4'd9) begin

                            B[element_count] <= {
                                4'd0,
                                key_value
                            };

                            current_value <= key_value;

                            // Last element of B
                            if (element_count == 5'd15) begin

                                element_count <= 5'd0;

                                state <= STATE_READY;

                                display_state <= DISP_READY;

                                current_value <= 4'd0;

                            end

                            else begin

                                element_count <=
                                    element_count + 1'b1;

                            end

                        end


                        // -------------------------------------
                        // B key
                        // Restart Matrix B entry
                        // -------------------------------------

                        else if (key_value == 4'hB) begin

                            state <= STATE_B;

                            element_count <= 5'd0;

                            current_value <= 4'd0;

                            display_state <= DISP_B;

                            for (i = 0; i < 16; i = i + 1)
                                B[i] <= 8'd0;

                        end


                        // -------------------------------------
                        // * = RESET EVERYTHING
                        // -------------------------------------

                        else if (key_value == 4'hE) begin

                            state <= STATE_A;

                            element_count <= 5'd0;

                            current_value <= 4'd0;

                            display_state <= DISP_RESET;

                            for (i = 0; i < 16; i = i + 1) begin
                                A[i] <= 8'd0;
                                B[i] <= 8'd0;
                            end

                            matrix_a <= 128'd0;
                            matrix_b <= 128'd0;

                        end

                    end


                    // =========================================
                    // BOTH MATRICES ENTERED
                    // =========================================

                    STATE_READY: begin

                        // -------------------------------------
                        // # = CONFIRM
                        // -------------------------------------

                        if (key_value == 4'hF) begin

                            // Pack A and B into 128-bit buses
                            //
                            // A[0] -> matrix_a[7:0]
                            // A[1] -> matrix_a[15:8]
                            // ...
                            // A[15] -> matrix_a[127:120]

                            for (i = 0; i < 16; i = i + 1) begin

                                matrix_a[i*8 +: 8] <= A[i];

                                matrix_b[i*8 +: 8] <= B[i];

                            end

                            // Tell accelerator wrapper
                            // that new matrices are available.
                            matrices_ready <= 1'b1;

                            display_state <= DISP_READY;

                        end


                        // -------------------------------------
                        // * = START OVER
                        // -------------------------------------

                        else if (key_value == 4'hE) begin

                            state <= STATE_A;

                            element_count <= 5'd0;

                            current_value <= 4'd0;

                            matrices_ready <= 1'b0;

                            display_state <= DISP_RESET;

                            matrix_a <= 128'd0;
                            matrix_b <= 128'd0;

                            for (i = 0; i < 16; i = i + 1) begin
                                A[i] <= 8'd0;
                                B[i] <= 8'd0;
                            end

                        end

                    end


                    default: begin

                        state <= STATE_A;

                    end

                endcase

            end

        end

    end

endmodule