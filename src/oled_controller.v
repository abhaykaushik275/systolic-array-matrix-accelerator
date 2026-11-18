`timescale 1ns / 1ps

module oled_controller #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer SPI_FREQ_HZ = 1_000_000
)(
    input wire        clk,
    input wire        reset,

    // =========================================================
    // From matrix_input.v
    // =========================================================
    input wire [2:0] display_state,
    input wire [4:0] element_count,
    input wire [3:0] current_value,

    // =========================================================
    // From accelerator_wrapper.v
    // =========================================================
    input wire [511:0] result_out,
    input wire         result_valid,

    // =========================================================
    // Pmod OLED
    // =========================================================
    output reg oled_cs,
    output reg oled_sdin,
    output reg oled_sclk,
    output reg oled_dc,
    output reg oled_res,
    output reg oled_vbatc,
    output reg oled_vddc
);

    // =========================================================
    // DISPLAY STATES
    // These must match matrix_input.v
    // =========================================================

    localparam DISP_A     = 3'd0;
    localparam DISP_B     = 3'd1;
    localparam DISP_READY = 3'd2;
    localparam DISP_RESET = 3'd3;

    // =========================================================
    // SPI CLOCK DIVIDER
    //
    // 100 MHz FPGA clock
    // 1 MHz SPI clock
    //
    // SPI clock toggles every 50 FPGA clocks.
    // =========================================================

    localparam integer SPI_DIV =
        CLK_FREQ_HZ / (2 * SPI_FREQ_HZ);

    integer spi_counter;

    // =========================================================
    // SSD1306 COMMANDS
    // =========================================================

    localparam [7:0] CMD_DISPLAY_OFF    = 8'hAE;
    localparam [7:0] CMD_DISPLAY_ON     = 8'hAF;

    localparam [7:0] CMD_SET_START_LINE = 8'h40;

    localparam [7:0] CMD_SEG_REMAP      = 8'hA1;
    localparam [7:0] CMD_COM_SCAN       = 8'hC8;

    localparam [7:0] CMD_NORMAL_DISPLAY = 8'hA6;

    localparam [7:0] CMD_CHARGE_PUMP    = 8'h8D;
    localparam [7:0] CMD_CHARGE_ON      = 8'h14;

    localparam [7:0] CMD_MEMORY_MODE    = 8'h20;
    localparam [7:0] CMD_PAGE_MODE      = 8'h02;

    localparam [7:0] CMD_COM_PINS       = 8'hDA;
    localparam [7:0] CMD_COM_PINS_32    = 8'h02;

    localparam [7:0] CMD_CONTRAST       = 8'h81;
    localparam [7:0] CMD_CONTRAST_VAL   = 8'h7F;

    localparam [7:0] CMD_PRECHARGE      = 8'hD9;
    localparam [7:0] CMD_PRECHARGE_VAL  = 8'hF1;

    localparam [7:0] CMD_VCOMH          = 8'hDB;
    localparam [7:0] CMD_VCOMH_VAL      = 8'h40;

    // =========================================================
    // FSM STATES
    // =========================================================

    localparam [4:0]
        ST_POWER_ON      = 5'd0,
        ST_RESET_LOW     = 5'd1,
        ST_INIT_SEND     = 5'd2,
        ST_CLEAR_START   = 5'd3,
        ST_CLEAR_CMD     = 5'd4,
        ST_CLEAR_DATA    = 5'd5,
        ST_VBAT_ON       = 5'd6,
        ST_WAIT_100MS    = 5'd7,
        ST_DISPLAY_ON    = 5'd8,
        ST_IDLE          = 5'd9,
        ST_BUILD_SCREEN  = 5'd10,
        ST_SET_PAGE      = 5'd11,
        ST_SEND_PAGE     = 5'd12,
        ST_DONE          = 5'd13;

    reg [4:0] state;

    // =========================================================
    // SPI TRANSMITTER
    // =========================================================

    reg [7:0] spi_data;
    reg [3:0] spi_bit;
    reg       spi_active;

    // =========================================================
    // INITIALIZATION INDEX
    // =========================================================

    reg [5:0] init_index;

    // =========================================================
    // OLED PAGE / COLUMN
    //
    // 128x32 OLED = 4 pages
    // each page = 128 bytes
    // =========================================================

    reg [2:0] page;
    reg [7:0] column;

    // =========================================================
    // FRAMEBUFFER
    //
    // 4 pages x 128 columns
    // = 512 bytes
    // =========================================================

    reg [7:0] framebuffer [0:511];

    integer i;

    // =========================================================
    // REMEMBER LAST DISPLAY STATE
    // =========================================================

    reg [2:0] last_display_state;
    reg [4:0] last_element_count;
    reg [3:0] last_current_value;
    reg       last_result_valid;

    // =========================================================
    // FONT
    //
    // 5x7 font.
    //
    // Each character uses:
    // 5 pixel columns + 1 blank column
    // =========================================================

    function [7:0] font_col;

        input [7:0] ch;
        input [2:0] col;

        begin

            case (ch)

                " ":
                    font_col = 8'h00;

                "0":
                    case(col)
                        0: font_col = 8'h3E;
                        1: font_col = 8'h51;
                        2: font_col = 8'h49;
                        3: font_col = 8'h45;
                        4: font_col = 8'h3E;
                        default: font_col = 8'h00;
                    endcase

                "1":
                    case(col)
                        0: font_col = 8'h00;
                        1: font_col = 8'h42;
                        2: font_col = 8'h7F;
                        3: font_col = 8'h40;
                        4: font_col = 8'h00;
                        default: font_col = 8'h00;
                    endcase

                "2":
                    case(col)
                        0: font_col = 8'h42;
                        1: font_col = 8'h61;
                        2: font_col = 8'h51;
                        3: font_col = 8'h49;
                        4: font_col = 8'h46;
                        default: font_col = 8'h00;
                    endcase

                "3":
                    case(col)
                        0: font_col = 8'h21;
                        1: font_col = 8'h41;
                        2: font_col = 8'h45;
                        3: font_col = 8'h4B;
                        4: font_col = 8'h31;
                        default: font_col = 8'h00;
                    endcase

                "4":
                    case(col)
                        0: font_col = 8'h18;
                        1: font_col = 8'h14;
                        2: font_col = 8'h12;
                        3: font_col = 8'h7F;
                        4: font_col = 8'h10;
                        default: font_col = 8'h00;
                    endcase

                "5":
                    case(col)
                        0: font_col = 8'h27;
                        1: font_col = 8'h45;
                        2: font_col = 8'h45;
                        3: font_col = 8'h45;
                        4: font_col = 8'h39;
                        default: font_col = 8'h00;
                    endcase

                "6":
                    case(col)
                        0: font_col = 8'h3C;
                        1: font_col = 8'h4A;
                        2: font_col = 8'h49;
                        3: font_col = 8'h49;
                        4: font_col = 8'h30;
                        default: font_col = 8'h00;
                    endcase

                "7":
                    case(col)
                        0: font_col = 8'h01;
                        1: font_col = 8'h71;
                        2: font_col = 8'h09;
                        3: font_col = 8'h05;
                        4: font_col = 8'h03;
                        default: font_col = 8'h00;
                    endcase

                "8":
                    case(col)
                        0: font_col = 8'h36;
                        1: font_col = 8'h49;
                        2: font_col = 8'h49;
                        3: font_col = 8'h49;
                        4: font_col = 8'h36;
                        default: font_col = 8'h00;
                    endcase

                "9":
                    case(col)
                        0: font_col = 8'h06;
                        1: font_col = 8'h49;
                        2: font_col = 8'h49;
                        3: font_col = 8'h29;
                        4: font_col = 8'h1E;
                        default: font_col = 8'h00;
                    endcase

                "A":
                    case(col)
                        0: font_col = 8'h7E;
                        1: font_col = 8'h11;
                        2: font_col = 8'h11;
                        3: font_col = 8'h11;
                        4: font_col = 8'h7E;
                        default: font_col = 8'h00;
                    endcase

                "B":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h49;
                        2: font_col = 8'h49;
                        3: font_col = 8'h49;
                        4: font_col = 8'h36;
                        default: font_col = 8'h00;
                    endcase

                "C":
                    case(col)
                        0: font_col = 8'h3E;
                        1: font_col = 8'h41;
                        2: font_col = 8'h41;
                        3: font_col = 8'h41;
                        4: font_col = 8'h22;
                        default: font_col = 8'h00;
                    endcase

                "D":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h41;
                        2: font_col = 8'h41;
                        3: font_col = 8'h22;
                        4: font_col = 8'h1C;
                        default: font_col = 8'h00;
                    endcase

                "E":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h49;
                        2: font_col = 8'h49;
                        3: font_col = 8'h49;
                        4: font_col = 8'h41;
                        default: font_col = 8'h00;
                    endcase

                "F":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h09;
                        2: font_col = 8'h09;
                        3: font_col = 8'h09;
                        4: font_col = 8'h01;
                        default: font_col = 8'h00;
                    endcase

                "H":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h08;
                        2: font_col = 8'h08;
                        3: font_col = 8'h08;
                        4: font_col = 8'h7F;
                        default: font_col = 8'h00;
                    endcase

                "I":
                    case(col)
                        0: font_col = 8'h00;
                        1: font_col = 8'h41;
                        2: font_col = 8'h7F;
                        3: font_col = 8'h41;
                        4: font_col = 8'h00;
                        default: font_col = 8'h00;
                    endcase

                "L":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h40;
                        2: font_col = 8'h40;
                        3: font_col = 8'h40;
                        4: font_col = 8'h40;
                        default: font_col = 8'h00;
                    endcase

                "M":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h02;
                        2: font_col = 8'h0C;
                        3: font_col = 8'h02;
                        4: font_col = 8'h7F;
                        default: font_col = 8'h00;
                    endcase

                "N":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h04;
                        2: font_col = 8'h08;
                        3: font_col = 8'h10;
                        4: font_col = 8'h7F;
                        default: font_col = 8'h00;
                    endcase

                "P":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h09;
                        2: font_col = 8'h09;
                        3: font_col = 8'h09;
                        4: font_col = 8'h06;
                        default: font_col = 8'h00;
                    endcase

                "R":
                    case(col)
                        0: font_col = 8'h7F;
                        1: font_col = 8'h09;
                        2: font_col = 8'h19;
                        3: font_col = 8'h29;
                        4: font_col = 8'h46;
                        default: font_col = 8'h00;
                    endcase

                "S":
                    case(col)
                        0: font_col = 8'h46;
                        1: font_col = 8'h49;
                        2: font_col = 8'h49;
                        3: font_col = 8'h49;
                        4: font_col = 8'h31;
                        default: font_col = 8'h00;
                    endcase

                "T":
                    case(col)
                        0: font_col = 8'h01;
                        1: font_col = 8'h01;
                        2: font_col = 8'h7F;
                        3: font_col = 8'h01;
                        4: font_col = 8'h01;
                        default: font_col = 8'h00;
                    endcase

                "U":
                    case(col)
                        0: font_col = 8'h3F;
                        1: font_col = 8'h40;
                        2: font_col = 8'h40;
                        3: font_col = 8'h40;
                        4: font_col = 8'h3F;
                        default: font_col = 8'h00;
                    endcase

                "V":
                    case(col)
                        0: font_col = 8'h1F;
                        1: font_col = 8'h20;
                        2: font_col = 8'h40;
                        3: font_col = 8'h20;
                        4: font_col = 8'h1F;
                        default: font_col = 8'h00;
                    endcase

                "X":
                    case(col)
                        0: font_col = 8'h63;
                        1: font_col = 8'h14;
                        2: font_col = 8'h08;
                        3: font_col = 8'h14;
                        4: font_col = 8'h63;
                        default: font_col = 8'h00;
                    endcase

                "Y":
                    case(col)
                        0: font_col = 8'h07;
                        1: font_col = 8'h08;
                        2: font_col = 8'h70;
                        3: font_col = 8'h08;
                        4: font_col = 8'h07;
                        default: font_col = 8'h00;
                    endcase

                "#":
                    case(col)
                        0: font_col = 8'h14;
                        1: font_col = 8'h7F;
                        2: font_col = 8'h14;
                        3: font_col = 8'h7F;
                        4: font_col = 8'h14;
                        default: font_col = 8'h00;
                    endcase

                "-":
                    case(col)
                        0: font_col = 8'h08;
                        1: font_col = 8'h08;
                        2: font_col = 8'h08;
                        3: font_col = 8'h08;
                        4: font_col = 8'h08;
                        default: font_col = 8'h00;
                    endcase

                default:
                    font_col = 8'h00;

            endcase

        end

    endfunction

    // =========================================================
    // CONVERT HEX DIGIT TO ASCII
    // =========================================================

    function [7:0] hex_ascii;

        input [3:0] x;

        begin

            if (x < 10)
                hex_ascii = "0" + x;
            else
                hex_ascii = "A" + (x - 10);

        end

    endfunction

    // =========================================================
    // CONVERT DECIMAL DIGIT TO ASCII
    // =========================================================

    function [7:0] digit_ascii;

        input [3:0] x;

        begin

            digit_ascii = "0" + x;

        end

    endfunction

    // =========================================================
    // DRAW ONE CHARACTER
    // =========================================================

    task draw_char;

        input integer x;
        input integer p;
        input [7:0] ch;

        integer c;

        begin

            for (c = 0; c < 5; c = c + 1) begin

                if ((x + c) < 128)
                    framebuffer[p*128 + x + c]
                        = font_col(ch, c);

            end

            // One blank column after every character

            if ((x + 5) < 128)
                framebuffer[p*128 + x + 5] = 8'h00;

        end

    endtask

    // =========================================================
    // DRAW 16-CHARACTER STRING
    //
    // IMPORTANT:
    //
    // This task takes ONLY 3 arguments:
    //
    //     x
    //     page
    //     128-bit packed string
    //
    // Therefore the previous "expects 19 arguments" problem
    // is completely eliminated.
    // =========================================================

    task draw_string;

        input integer x;
        input integer p;
        input [127:0] str;

        integer k;

        begin

            for (k = 0; k < 16; k = k + 1) begin

                draw_char(
                    x + k*6,
                    p,
                    str[127 - k*8 -: 8]
                );

            end

        end

    endtask

    // =========================================================
    // BUILD INPUT SCREEN
    // =========================================================

    task build_input_screen;

        integer tens;
        integer ones;

        begin

            // -------------------------------------------------
            // MATRIX A
            // -------------------------------------------------

            if (display_state == DISP_A) begin

                // PAGE 0
                // ENTER MATRIX A
                draw_string(
                    0,
                    0,
                    {
                        "E","N","T","E","R"," ",
                        "M","A","T","R","I","X"," ",
                        "A"," "," "
                    }
                );

                // PAGE 1
                // ELEM 00
                tens = element_count / 10;
                ones = element_count % 10;

                draw_string(
                    0,
                    1,
                    {
                        "E","L","E","M"," "," ",
                        digit_ascii(tens),
                        digit_ascii(ones),
                        " "," "," "," "," "," "," "," "
                    }
                );

                // PAGE 2
                // VALUE 0
                draw_string(
                    0,
                    2,
                    {
                        "V","A","L","U","E"," ",
                        digit_ascii(current_value),
                        " "," "," "," "," "," "," "," "," "
                    }
                );

            end

            // -------------------------------------------------
            // MATRIX B
            // -------------------------------------------------

            else if (display_state == DISP_B) begin

                // PAGE 0
                // ENTER MATRIX B
                draw_string(
                    0,
                    0,
                    {
                        "E","N","T","E","R"," ",
                        "M","A","T","R","I","X"," ",
                        "B"," "," "
                    }
                );

                // PAGE 1
                // ELEM 00
                tens = element_count / 10;
                ones = element_count % 10;

                draw_string(
                    0,
                    1,
                    {
                        "E","L","E","M"," "," ",
                        digit_ascii(tens),
                        digit_ascii(ones),
                        " "," "," "," "," "," "," "," "
                    }
                );

                // PAGE 2
                // VALUE 0
                draw_string(
                    0,
                    2,
                    {
                        "V","A","L","U","E"," ",
                        digit_ascii(current_value),
                        " "," "," "," "," "," "," "," "," "
                    }
                );

            end

            // -------------------------------------------------
            // MATRICES READY
            // -------------------------------------------------

            else if (display_state == DISP_READY) begin

                // PAGE 0
                // MATRICES
                draw_string(
                    0,
                    0,
                    {
                        "M","A","T","R","I","X","E","S",
                        " "," "," "," "," "," "," "," "
                    }
                );

                // PAGE 1
                // READY
                draw_string(
                    0,
                    1,
                    {
                        "R","E","A","D","Y"," ",
                        " "," "," "," "," "," "," "," "," "
                    }
                );

                // PAGE 2
                // PRESS #
                draw_string(
                    0,
                    2,
                    {
                        "P","R","E","S","S"," ","#",
                        " "," "," "," "," "," "," "," "," "
                    }
                );

            end

            // -------------------------------------------------
            // RESET
            // -------------------------------------------------

            else if (display_state == DISP_RESET) begin

                draw_string(
                    0,
                    1,
                    {
                        "R","E","S","E","T"," ",
                        " "," "," "," "," "," "," "," "," "
                    }
                );

            end

        end

    endtask

    // =========================================================
    // BUILD RESULT SCREEN
    //
    // Each OLED page displays one row of the 4x4 matrix.
    //
    // Example:
    //
    // R0  000A 0014 0005 0009
    // R1  0003 0007 0012 0001
    //
    // Since your keypad inputs are 0-9, the matrix products
    // are small, so displaying the lower 16 bits as 4 hex
    // digits is sufficient for the result.
    // =========================================================

    task build_result_screen;

        integer r;
        integer base;

        reg [31:0] value0;
        reg [31:0] value1;
        reg [31:0] value2;
        reg [31:0] value3;

        begin

            // Clear framebuffer

            for (i = 0; i < 512; i = i + 1)
                framebuffer[i] = 8'h00;

            for (r = 0; r < 4; r = r + 1) begin

                base = r * 4;

                value0 = result_out[(base + 0)*32 +: 32];
                value1 = result_out[(base + 1)*32 +: 32];
                value2 = result_out[(base + 2)*32 +: 32];
                value3 = result_out[(base + 3)*32 +: 32];

                // R0/R1/R2/R3
                draw_char(0, r, "R");
                draw_char(6, r, digit_ascii(r));

                // Value 0
                draw_char(18, r, hex_ascii(value0[15:12]));
                draw_char(24, r, hex_ascii(value0[11:8]));
                draw_char(30, r, hex_ascii(value0[7:4]));
                draw_char(36, r, hex_ascii(value0[3:0]));

                // Value 1
                draw_char(48, r, hex_ascii(value1[15:12]));
                draw_char(54, r, hex_ascii(value1[11:8]));
                draw_char(60, r, hex_ascii(value1[7:4]));
                draw_char(66, r, hex_ascii(value1[3:0]));

                // Value 2
                draw_char(78, r, hex_ascii(value2[15:12]));
                draw_char(84, r, hex_ascii(value2[11:8]));
                draw_char(90, r, hex_ascii(value2[7:4]));
                draw_char(96, r, hex_ascii(value2[3:0]));

                // Value 3
                draw_char(108, r, hex_ascii(value3[15:12]));
                draw_char(114, r, hex_ascii(value3[11:8]));
                draw_char(120, r, hex_ascii(value3[7:4]));

            end

        end

    endtask

    // =========================================================
    // BUILD COMPLETE SCREEN
    // =========================================================

    task build_screen;

        begin

            // Clear framebuffer first

            for (i = 0; i < 512; i = i + 1)
                framebuffer[i] = 8'h00;

            if (result_valid)
                build_result_screen;
            else
                build_input_screen;

        end

    endtask

    // =========================================================
    // START SPI BYTE
    //
    // is_data = 0 -> command
    // is_data = 1 -> display data
    // =========================================================

    task start_spi;

        input [7:0] data;
        input       is_data;

        begin

            spi_data   <= data;
            spi_bit    <= 4'd0;
            spi_active <= 1'b1;

            oled_dc   <= is_data;
            oled_cs   <= 1'b0;
            oled_sclk <= 1'b0;

            // MSB first

            oled_sdin <= data[7];

        end

    endtask

    // =========================================================
    // MAIN FSM
    // =========================================================

    always @(posedge clk) begin

        if (reset) begin

            state <= ST_POWER_ON;

            oled_cs    <= 1'b1;
            oled_sdin  <= 1'b0;
            oled_sclk  <= 1'b0;
            oled_dc    <= 1'b0;

            // Both controls are active LOW according to
            // the Pmod OLED interface.

            oled_vddc  <= 1'b1;
            oled_vbatc <= 1'b1;

            oled_res <= 1'b0;

            spi_counter <= 0;
            spi_active  <= 1'b0;

            init_index <= 0;

            page   <= 0;
            column <= 0;

            last_display_state <= 3'd7;
            last_element_count <= 5'd31;
            last_current_value <= 4'd15;
            last_result_valid  <= 1'b0;

        end

        else begin

            case (state)

                // =================================================
                // POWER VDD
                // =================================================

                ST_POWER_ON: begin

                    // VDDC active LOW

                    oled_vddc <= 1'b0;

                    spi_counter <= 0;

                    state <= ST_RESET_LOW;

                end

                // =================================================
                // OLED RESET
                //
                // Keep RES low for approximately 5 us.
                // =================================================

                ST_RESET_LOW: begin

                    oled_res <= 1'b0;

                    if (spi_counter >= 500) begin

                        spi_counter <= 0;

                        oled_res <= 1'b1;

                        init_index <= 0;

                        state <= ST_INIT_SEND;

                    end

                    else begin

                        spi_counter <= spi_counter + 1;

                    end

                end

                // =================================================
                // INITIALIZATION
                // =================================================

                ST_INIT_SEND: begin

                    if (!spi_active) begin

                        case (init_index)

                            0:
                                start_spi(CMD_DISPLAY_OFF, 1'b0);

                            1:
                                start_spi(CMD_MEMORY_MODE, 1'b0);

                            2:
                                start_spi(CMD_PAGE_MODE, 1'b0);

                            3:
                                start_spi(CMD_SET_START_LINE, 1'b0);

                            4:
                                start_spi(CMD_SEG_REMAP, 1'b0);

                            5:
                                start_spi(CMD_COM_SCAN, 1'b0);

                            6:
                                start_spi(CMD_COM_PINS, 1'b0);

                            7:
                                start_spi(CMD_COM_PINS_32, 1'b0);

                            8:
                                start_spi(CMD_CONTRAST, 1'b0);

                            9:
                                start_spi(CMD_CONTRAST_VAL, 1'b0);

                            10:
                                start_spi(CMD_PRECHARGE, 1'b0);

                            11:
                                start_spi(CMD_PRECHARGE_VAL, 1'b0);

                            12:
                                start_spi(CMD_VCOMH, 1'b0);

                            13:
                                start_spi(CMD_VCOMH_VAL, 1'b0);

                            14:
                                start_spi(CMD_NORMAL_DISPLAY, 1'b0);

                            15:
                                start_spi(CMD_CHARGE_PUMP, 1'b0);

                            16:
                                start_spi(CMD_CHARGE_ON, 1'b0);

                            default: begin

                                page   <= 0;
                                column <= 0;

                                state <= ST_CLEAR_START;

                            end

                        endcase

                    end

                    else begin

                        // SPI clock generation

                        if (spi_counter >= SPI_DIV - 1) begin

                            spi_counter <= 0;

                            if (oled_sclk == 1'b0) begin

                                // Rising edge

                                oled_sclk <= 1'b1;

                            end

                            else begin

                                // Falling edge

                                oled_sclk <= 1'b0;

                                if (spi_bit == 7) begin

                                    spi_active <= 1'b0;
                                    oled_cs    <= 1'b1;

                                    init_index <=
                                        init_index + 1'b1;

                                end

                                else begin

                                    spi_bit <= spi_bit + 1'b1;

                                    oled_sdin <=
                                        spi_data[7 - (spi_bit + 1)];

                                end

                            end

                        end

                        else begin

                            spi_counter <=
                                spi_counter + 1;

                        end

                    end

                end

                // =================================================
                // START CLEAR
                // =================================================

                ST_CLEAR_START: begin

                    page   <= 0;
                    column <= 0;

                    state <= ST_CLEAR_CMD;

                end

                // =================================================
                // SEND PAGE COMMANDS
                // =================================================

                ST_CLEAR_CMD: begin

                    if (!spi_active) begin

                        if (column == 0) begin

                            start_spi(
                                8'hB0 + page,
                                1'b0
                            );

                            column <= 1;

                        end

                        else if (column == 1) begin

                            start_spi(
                                8'h00,
                                1'b0
                            );

                            column <= 2;

                        end

                        else begin

                            start_spi(
                                8'h10,
                                1'b0
                            );

                            column <= 0;

                            state <= ST_CLEAR_DATA;

                        end

                    end

                    else begin

                        if (spi_counter >= SPI_DIV - 1) begin

                            spi_counter <= 0;

                            if (oled_sclk == 1'b0) begin

                                oled_sclk <= 1'b1;

                            end

                            else begin

                                oled_sclk <= 1'b0;

                                if (spi_bit == 7) begin

                                    spi_active <= 1'b0;
                                    oled_cs    <= 1'b1;

                                end

                                else begin

                                    spi_bit <= spi_bit + 1'b1;

                                    oled_sdin <=
                                        spi_data[
                                            7 - (spi_bit + 1)
                                        ];

                                end

                            end

                        end

                        else begin

                            spi_counter <=
                                spi_counter + 1;

                        end

                    end

                end

                // =================================================
                // CLEAR PAGE DATA
                // =================================================

                ST_CLEAR_DATA: begin

                    if (!spi_active) begin

                        if (column < 128) begin

                            start_spi(
                                8'h00,
                                1'b1
                            );

                        end

                        else begin

                            column <= 0;

                            if (page == 3) begin

                                page <= 0;

                                state <= ST_VBAT_ON;

                            end

                            else begin

                                page <= page + 1'b1;

                                state <= ST_CLEAR_CMD;

                            end

                        end

                    end

                    else begin

                        if (spi_counter >= SPI_DIV - 1) begin

                            spi_counter <= 0;

                            if (oled_sclk == 1'b0) begin

                                oled_sclk <= 1'b1;

                            end

                            else begin

                                oled_sclk <= 1'b0;

                                if (spi_bit == 7) begin

                                    spi_active <= 1'b0;
                                    oled_cs    <= 1'b1;

                                    column <= column + 1'b1;

                                end

                                else begin

                                    spi_bit <= spi_bit + 1'b1;

                                    oled_sdin <=
                                        spi_data[
                                            7 - (spi_bit + 1)
                                        ];

                                end

                            end

                        end

                        else begin

                            spi_counter <=
                                spi_counter + 1;

                        end

                    end

                end

                // =================================================
                // TURN ON OLED PANEL POWER
                // =================================================

                ST_VBAT_ON: begin

                    // VBATC active LOW

                    oled_vbatc <= 1'b0;

                    spi_counter <= 0;

                    state <= ST_WAIT_100MS;

                end

                // =================================================
                // WAIT 100 ms
                // =================================================

                ST_WAIT_100MS: begin

                    if (spi_counter >=
                        (CLK_FREQ_HZ / 10)) begin

                        spi_counter <= 0;

                        state <= ST_DISPLAY_ON;

                    end

                    else begin

                        spi_counter <=
                            spi_counter + 1;

                    end

                end

                // =================================================
                // DISPLAY ON
                // =================================================

                ST_DISPLAY_ON: begin

                    if (!spi_active) begin

                        start_spi(
                            CMD_DISPLAY_ON,
                            1'b0
                        );

                    end

                    else begin

                        if (spi_counter >= SPI_DIV - 1) begin

                            spi_counter <= 0;

                            if (oled_sclk == 1'b0) begin

                                oled_sclk <= 1'b1;

                            end

                            else begin

                                oled_sclk <= 1'b0;

                                if (spi_bit == 7) begin

                                    spi_active <= 1'b0;
                                    oled_cs    <= 1'b1;

                                    state <= ST_BUILD_SCREEN;

                                end

                                else begin

                                    spi_bit <= spi_bit + 1'b1;

                                    oled_sdin <=
                                        spi_data[
                                            7 - (spi_bit + 1)
                                        ];

                                end

                            end

                        end

                        else begin

                            spi_counter <=
                                spi_counter + 1;

                        end

                    end

                end

                // =================================================
                // BUILD SCREEN
                // =================================================

                ST_BUILD_SCREEN: begin

                    build_screen;

                    page   <= 0;
                    column <= 0;

                    last_display_state <=
                        display_state;

                    last_element_count <=
                        element_count;

                    last_current_value <=
                        current_value;

                    last_result_valid <=
                        result_valid;

                    state <= ST_SET_PAGE;

                end

                // =================================================
                // SET OLED PAGE
                // =================================================

                ST_SET_PAGE: begin

                    if (!spi_active) begin

                        if (column == 0) begin

                            start_spi(
                                8'hB0 + page,
                                1'b0
                            );

                            column <= 1;

                        end

                        else if (column == 1) begin

                            start_spi(
                                8'h00,
                                1'b0
                            );

                            column <= 2;

                        end

                        else begin

                            start_spi(
                                8'h10,
                                1'b0
                            );

                            column <= 0;

                            state <= ST_SEND_PAGE;

                        end

                    end

                    else begin

                        if (spi_counter >= SPI_DIV - 1) begin

                            spi_counter <= 0;

                            if (oled_sclk == 1'b0) begin

                                oled_sclk <= 1'b1;

                            end

                            else begin

                                oled_sclk <= 1'b0;

                                if (spi_bit == 7) begin

                                    spi_active <= 1'b0;
                                    oled_cs    <= 1'b1;

                                end

                                else begin

                                    spi_bit <= spi_bit + 1'b1;

                                    oled_sdin <=
                                        spi_data[
                                            7 - (spi_bit + 1)
                                        ];

                                end

                            end

                        end

                        else begin

                            spi_counter <=
                                spi_counter + 1;

                        end

                    end

                end

                // =================================================
                // SEND PAGE DATA
                // =================================================

                ST_SEND_PAGE: begin

                    if (!spi_active) begin

                        if (column < 128) begin

                            start_spi(
                                framebuffer[
                                    page*128 + column
                                ],
                                1'b1
                            );

                        end

                        else begin

                            column <= 0;

                            if (page == 3) begin

                                state <= ST_DONE;

                            end

                            else begin

                                page <= page + 1'b1;

                                state <= ST_SET_PAGE;

                            end

                        end

                    end

                    else begin

                        if (spi_counter >= SPI_DIV - 1) begin

                            spi_counter <= 0;

                            if (oled_sclk == 1'b0) begin

                                oled_sclk <= 1'b1;

                            end

                            else begin

                                oled_sclk <= 1'b0;

                                if (spi_bit == 7) begin

                                    spi_active <= 1'b0;
                                    oled_cs    <= 1'b1;

                                    column <=
                                        column + 1'b1;

                                end

                                else begin

                                    spi_bit <=
                                        spi_bit + 1'b1;

                                    oled_sdin <=
                                        spi_data[
                                            7 - (spi_bit + 1)
                                        ];

                                end

                            end

                        end

                        else begin

                            spi_counter <=
                                spi_counter + 1;

                        end

                    end

                end

                // =================================================
                // FINISHED REFRESH
                // =================================================

                ST_DONE: begin

                    state <= ST_IDLE;

                end

                // =================================================
                // WAIT FOR DISPLAY CHANGE
                // =================================================

                ST_IDLE: begin

                    if (
                        (display_state !=
                            last_display_state) ||

                        (element_count !=
                            last_element_count) ||

                        (current_value !=
                            last_current_value) ||

                        (result_valid !=
                            last_result_valid)
                    ) begin

                        state <= ST_BUILD_SCREEN;

                    end

                end

                default: begin

                    state <= ST_POWER_ON;

                end

            endcase

        end

    end

endmodule