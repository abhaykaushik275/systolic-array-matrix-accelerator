`timescale 1ns / 1ps

module keypad_scanner #(
    parameter CLK_FREQ_HZ = 100_000_000,
    parameter SCAN_FREQ_HZ = 1000
)(
    input  wire       clk,
    input  wire       reset,

    // Pmod KYPD
    input  wire [3:0] row,
    output reg  [3:0] col,

    // Decoded key
    output reg        key_valid,
    output reg  [3:0] key_value
);

    // =========================================================
    // SCANNING
    // =========================================================

    localparam integer SCAN_COUNT =
        CLK_FREQ_HZ / SCAN_FREQ_HZ;

    localparam integer SCAN_WIDTH =
        (SCAN_COUNT <= 1) ? 1 : $clog2(SCAN_COUNT);

    reg [SCAN_WIDTH-1:0] scan_counter;
    reg [1:0] scan_col;

    // =========================================================
    // DEBOUNCE
    // =========================================================

    // Number of complete scans required for a stable key
    localparam integer DEBOUNCE_SCANS = 5;

    reg [3:0] current_key;
    reg [3:0] last_key;

    reg [2:0] debounce_count;

    reg key_down;

    // =========================================================
    // CONSTANTS
    // =========================================================

    localparam KEY_STAR = 4'hE;
    localparam KEY_HASH = 4'hF;

    // =========================================================
    // COLUMN DRIVE
    //
    // Only one column is driven LOW.
    // The others remain HIGH.
    // =========================================================

    always @(*) begin

        case (scan_col)

            2'd0:
                col = 4'b1110;

            2'd1:
                col = 4'b1101;

            2'd2:
                col = 4'b1011;

            2'd3:
                col = 4'b0111;

            default:
                col = 4'b1111;

        endcase

    end

    // =========================================================
    // MAIN SCANNER
    // =========================================================

    always @(posedge clk) begin

        if (reset) begin

            scan_counter  <= 0;
            scan_col      <= 0;

            key_valid     <= 0;
            key_value     <= 0;

            current_key   <= 0;
            last_key      <= 0;

            debounce_count <= 0;
            key_down       <= 0;

        end

        else begin

            // key_valid is a one-clock pulse
            key_valid <= 0;


            // =================================================
            // SCAN TIMER
            // =================================================

            if (scan_counter == SCAN_COUNT - 1) begin

                scan_counter <= 0;

                // Move to next column
                if (scan_col == 2'd3)
                    scan_col <= 2'd0;
                else
                    scan_col <= scan_col + 1'b1;


                // =================================================
                // READ CURRENT COLUMN
                // =================================================

                if (row != 4'b1111) begin

                    // Determine which row is LOW
                    case (row)

                        4'b1110: begin
                            current_key <= decode_key(
                                scan_col, 2'd0
                            );
                        end

                        4'b1101: begin
                            current_key <= decode_key(
                                scan_col, 2'd1
                            );
                        end

                        4'b1011: begin
                            current_key <= decode_key(
                                scan_col, 2'd2
                            );
                        end

                        4'b0111: begin
                            current_key <= decode_key(
                                scan_col, 2'd3
                            );
                        end

                        default:
                            current_key <= 0;

                    endcase

                end

                else begin

                    current_key <= 0;

                end


                // =================================================
                // DEBOUNCE
                // =================================================

                if (current_key == last_key &&
                    current_key != 0) begin

                    if (debounce_count < DEBOUNCE_SCANS)
                        debounce_count <= debounce_count + 1'b1;

                    else if (!key_down) begin

                        key_valid <= 1'b1;
                        key_value <= current_key;

                        key_down <= 1'b1;

                    end

                end

                else begin

                    debounce_count <= 0;

                    if (current_key == 0)
                        key_down <= 1'b0;

                end

                last_key <= current_key;

            end

            else begin

                scan_counter <= scan_counter + 1'b1;

            end

        end

    end


    // =========================================================
    // KEY DECODER
    //
    //       C0 C1 C2 C3
    //
    // R0    1  2  3  A
    // R1    4  5  6  B
    // R2    7  8  9  C
    // R3    *  0  #  D
    //
    // We encode:
    //
    // 0-9 -> 0-9
    // A-F -> A-F
    // *   -> A
    // #   -> B
    //
    // NOTE: Because A/B are also physical keys, this scanner
    // returns special codes for them too.
    // =========================================================

    function [3:0] decode_key;

        input [1:0] column;
        input [1:0] row_number;

        begin

            case ({row_number, column})

                // Row 0
                4'b0000: decode_key = 4'd1;
                4'b0001: decode_key = 4'd2;
                4'b0010: decode_key = 4'd3;
                4'b0011: decode_key = 4'd10;   // A

                // Row 1
                4'b0100: decode_key = 4'd4;
                4'b0101: decode_key = 4'd5;
                4'b0110: decode_key = 4'd6;
                4'b0111: decode_key = 4'd11;   // B

                // Row 2
                4'b1000: decode_key = 4'd7;
                4'b1001: decode_key = 4'd8;
                4'b1010: decode_key = 4'd9;
                4'b1011: decode_key = 4'd12;   // C

                // Row 3
                4'b1100: decode_key = KEY_STAR;
                4'b1101: decode_key = 4'd0;
                4'b1110: decode_key = KEY_HASH;
                4'b1111: decode_key = 4'd13;   // D

                default:
                    decode_key = 0;

            endcase

        end

    endfunction

endmodule