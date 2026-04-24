// =============================================================================
// FILE: frame_parser.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person A
// =============================================================================
//
// PURPOSE:
//   Binary frame parser FSM. Consumes bytes from uart_rx and assembles
//   complete protocol frames. On a valid frame emits either:
//     - A task_desc_t for the FIFO (SAFETY / AI_TASK / AI_HB)
//     - A metrics request or SET_PARAM command (directly to metrics.v)
//
// FRAME FORMAT: [0xA5][TYPE][LEN][PAYLOAD 0..N][CRC8=0x00 stub]
//
// FSM STATES:
//   WAIT_SOF(0) → RECV_TYPE(1) → RECV_LEN(2) → RECV_PAYLOAD(3) → EMIT(4)
//
// PARAMETERS TO IMPLEMENT:
//   MAX_PAYLOAD = 8  (bytes; reject frames with LEN > this)
//   CRC_ENABLE  = 0  (stub: always pass for MVP)
//
// INTERFACE CONTRACT (outputs to frame_parser):
//   enq_valid_o / enq_task_o / enq_ready_i  → task_fifo
//   ai_heartbeat_o                           → watchdog
//   rd_metrics_req_o                         → metrics
//   set_param_valid_o / _id_o / _val_o       → metrics
//   frame_err_o                              → debug LED
//
// VERIFICATION CHECKLIST:
//   [ ] Valid SAFETY frame → correct task fields.
//   [ ] Valid AI_TASK frame → correct work_cycles.
//   [ ] Unknown TYPE → frame_err, return to WAIT_SOF.
//   [ ] LEN > MAX_PAYLOAD → frame_err, return to WAIT_SOF.
//   [ ] Back-pressure (enq_ready=0) → enq_valid held.
//   [ ] Back-to-back frames both emitted.
//   [ ] ai_heartbeat_o pulses on TYPE_AI_HB.
//   [ ] rd_metrics_req_o pulses on TYPE_RD_MET.
//   [ ] set_param_* correct on TYPE_SET_PAR.
// =============================================================================
`timescale 1ns/1ps

// Macros replacing qos_defines.v
`define CYCLES_PER_BIT 868
`define FRAME_SOF      8'hA5
`define TYPE_SAFETY    8'h01
`define TYPE_AI_HB     8'h02
`define TYPE_AI_TASK   8'h03
`define TYPE_RD_MET    8'h10
`define TYPE_SET_PAR   8'h11
`define TASK_W         104
`define TASK_TYPE_HI   103
`define TASK_TYPE_LO   96
`define TASK_ENQ_HI    95
`define TASK_ENQ_LO    64
`define TASK_P0_HI     63
`define TASK_P0_LO     32
`define TASK_P1_HI     31
`define TASK_P1_LO     0

module uart_rx (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       rx_i,

    output reg  [7:0] rx_byte_o,
    output reg        rx_valid_o
);

    // Sync RX
    reg rx_meta, rx_sync;
    always @(posedge clk_i) begin
        rx_meta <= rx_i;
        rx_sync <= rx_meta;
    end

    // States
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
            // Reset
            state      <= IDLE;
            baud_cnt   <= 10'd0;
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'd0;
            rx_byte_o  <= 8'd0;
            rx_valid_o <= 1'b0;
        end else begin
            // Def low
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
