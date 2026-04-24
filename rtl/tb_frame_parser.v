`timescale 1ns/1ps

// Macros replacing qos_defines.v
`define CYCLES_PER_BIT 868
`define FRAME_SOF      8'hA5

module tb_uart_rx;
  reg clk=0, rstn=0, rx_line=1;
  wire [7:0] rx_byte; 
  wire rx_valid;
  
  // 100MHz clk
  always #5 clk=~clk;  

  uart_rx dut(
    .clk_i(clk),
    .rst_ni(rstn),
    .rx_i(rx_line),
    .rx_byte_o(rx_byte),
    .rx_valid_o(rx_valid)
  );

  // Send byte
  task send_byte(input [7:0] data);
    integer i;
    // Start bit
    @(negedge clk); rx_line=0;         
    repeat(868) @(posedge clk);
    for(i=0; i<8; i=i+1) begin
      // LSB first
      rx_line=data[i];                 
      repeat(868) @(posedge clk);
    end
    // Stop bit
    rx_line=1;                         
    repeat(868) @(posedge clk);
  endtask

  initial begin
    // Dump waves
    $dumpfile("dump.vcd");
    $dumpvars(0,tb_uart_rx);
    
    repeat(5) @(posedge clk); rstn=1;

    // Test 0xA5
    fork
      send_byte(8'hA5);
      begin
        // Catch pulse
        @(posedge rx_valid);           
        if(rx_byte == 8'hA5)
          $display("PASS: 0xA5");
        else
          $display("FAIL: 0xA5");
      end
    join

    // Gap
    repeat(50) @(posedge clk);         

    // Test 0x00
    fork
      send_byte(8'h00);
      begin
        // Catch pulse
        @(posedge rx_valid);           
        if(rx_byte == 8'h00) 
          $display("PASS: 0x00");
        else 
          $display("FAIL: 0x00");
      end
    join

    // End
    $display("Test done");
    $finish;
  end
endmodule
