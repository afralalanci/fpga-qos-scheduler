// =============================================================================
// FILE: uart_rx.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person A
// =============================================================================
//
// PURPOSE:
//   8N1 UART receiver at 115200 baud / 100 MHz clock.
//   Deserializes incoming serial bytes and presents each with a 1-cycle strobe.
//
// FSM STATES: IDLE(0) → START(1) → DATA(2) → STOP(3)
//
// IMPLEMENTATION NOTES:
//   1. Two-FF synchronizer on rx_i to prevent metastability.
//   2. Sample at center of each bit (CYCLES_PER_BIT/2 offset from start bit edge).
//   3. Glitch rejection: re-check rx_i at center of start bit; abort if high.
//
// PARAMETERS TO IMPLEMENT:
//   CYCLES_PER_BIT = 868
//   HALF_BIT       = 434
//
// VERIFICATION CHECKLIST:
//   [ ] Correctly decodes 0x00, 0xFF, 0xA5, 0x55, 0xAA.
//   [ ] rx_valid_o asserted for exactly 1 cycle.
//   [ ] Back-to-back bytes without gaps.
//   [ ] Glitch < half-bit wide rejected.
// =============================================================================

`timescale 1ns/1ps
`define CYCLES_PER_BIT 868 // Define here, no include

module uart_rx (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       rx_i,

    output reg  [7:0] rx_byte_o,
    output reg        rx_valid_o
);

    // Sync rx
    reg rx_meta, rx_sync;
    always @(posedge clk_i) begin
        rx_meta <= rx_i;
        rx_sync <= rx_meta;
    end

    // FSM states
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    localparam HALF_BIT = `CYCLES_PER_BIT / 2;

    // FSM regs
    reg [1:0]  state;
    reg [9:0]  baud_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  shift_reg;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            // Rst defaults
            state      <= IDLE;
            baud_cnt   <= 10'd0;
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'd0;
            rx_byte_o  <= 8'd0;
            rx_valid_o <= 1'b0;
        end else begin
            // Clear valid
            rx_valid_o <= 1'b0;

            case (state)
                IDLE: begin
                    // Wait fall
                    if (!rx_sync) begin
                        state    <= START;
                        baud_cnt <= HALF_BIT; 
                    end
                end

                START: begin
                    // Wait half
                    if (baud_cnt == 10'd0) begin
                        // Glitch chk
                        if (!rx_sync) begin
                            state    <= DATA;
                            baud_cnt <= `CYCLES_PER_BIT;
                            bit_cnt  <= 3'd0;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 10'd1;
                    end
                end

                DATA: begin
                    // Shift LSB
                    if (baud_cnt == 10'd0) begin
                        shift_reg <= {rx_sync, shift_reg[7:1]};
                        baud_cnt  <= `CYCLES_PER_BIT;
                        // Chk last
                        if (bit_cnt == 3'd7) begin
                            state   <= STOP;
                            bit_cnt <= 3'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 10'd1;
                    end
                end

                STOP: begin
                    // Out byte
                    if (baud_cnt == 10'd0) begin
                        rx_byte_o  <= shift_reg;
                        rx_valid_o <= 1'b1;
                        state      <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt - 10'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
