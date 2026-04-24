`timescale 1ns/1ps

// Mock define if file not present: 
// Assume 100MHz clock and 115200 baud -> ~868 cycles
`ifndef CYCLES_PER_BIT
    `define CYCLES_PER_BIT 868
`endif

module tb_uart_tx;
    reg clk = 0;
    reg rstn = 0;
    reg [7:0] tx_byte = 0;
    reg tx_valid = 0;
    wire tx_o, tx_ready;

    // 100MHz clock (10ns period)
    always #5 clk = ~clk;

    uart_tx dut (
        .clk_i      (clk),
        .rst_ni     (rstn),
        .tx_byte_i  (tx_byte),
        .tx_valid_i (tx_valid),
        .tx_o       (tx_o),
        .tx_ready_o (tx_ready)
    );

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        // Reset Sequence
        repeat(5) @(posedge clk);
        rstn = 1;
        repeat(2) @(posedge clk);

        // Check idle line is HIGH
        if(tx_o == 1'b1 && tx_ready == 1'b1)
            $display("[T=%0t] PASS: idle line HIGH, ready HIGH", $time);
        else 
            $display("[T=%0t] FAIL: idle state wrong", $time);

        // Send byte 0x55 (8'b01010101)
        @(posedge clk);
        tx_byte = 8'h55;
        tx_valid = 1'b1;
        @(posedge clk);
        tx_valid = 1'b0;

        // Monitor deassertion
        if (tx_ready == 1'b0)
            $display("[T=%0t] INFO: tx_ready successfully dropped", $time);

        // Wait for transmission (~10 bits * CYCLES_PER_BIT)
        // Adjust repeat based on CYCLES_PER_BIT
        repeat(10 * `CYCLES_PER_BIT + 100) @(posedge clk);

        if(tx_ready == 1'b1)
            $display("[T=%0t] PASS: tx_ready back HIGH after send", $time);
        else 
            $display("[T=%0t] FAIL: tx_ready still LOW", $time);

        $display("uart_tx test done");
        $finish;
    end
endmodule
