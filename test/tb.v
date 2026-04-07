`default_nettype none
`timescale 1ns / 1ps

module tb;
  reg clk, rst_n, ena;
  reg [7:0] ui_in, uio_in;
  wire [7:0] uo_out, uio_out, uio_oe;
  integer errors = 0;

  tt_um_kishorenetheti_tt8_mips dut (
    .clk(clk), .rst_n(rst_n), .ena(ena),
    .ui_in(ui_in), .uo_out(uo_out),
    .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe)
  );

  // 100ns period (10MHz)
  always #50 clk = ~clk;

  // Program one instruction into instruction memory in program mode.
  task load_word(input [3:0] addr, input [15:0] word);
    begin
      @(posedge clk);
      #5;
      uio_in = {1'b0, 3'b000, addr};
      uio_in[6] = 1'b0;
      ui_in = word[7:0];
      ena = 1'b1;
      @(posedge clk);
      #5;
      ena = 1'b0;

      @(posedge clk);
      #5;
      uio_in = {1'b0, 3'b000, addr};
      uio_in[6] = 1'b1;
      ui_in = word[15:8];
      ena = 1'b1;
      @(posedge clk);
      #5;
      ena = 1'b0;
    end
  endtask

  // Check ALU output for current cycle and then advance one CPU cycle.
  task check(input [7:0] exp, input [8*40-1:0] msg);
    begin
      #10;
      if (uo_out !== exp) begin
        $display("[FAIL] %s | Exp: 0x%h, Got: 0x%h", msg, exp, uo_out);
        errors = errors + 1;
      end else begin
        $display("[PASS] %s | Result: 0x%h", msg, uo_out);
      end
      @(posedge clk);
    end
  endtask

  initial begin
    clk = 0;
    rst_n = 0;
    ena = 0;
    ui_in = 8'h00;
    uio_in = 8'h00;

    $dumpfile("tb.vcd");
    $dumpvars(0, tb);

    #200;
    rst_n = 1;
    #100;

    $display("===================================================================");
    $display("                        ASSEMBLY PROGRAM                           ");
    $display("===================================================================");
    $display("PC  | Word  | Assembly      | Expected Execution Result            ");
    $display("----|-------|---------------|--------------------------------------");
    $display("0x0 | 0x6113 | ADDI R1, 3    | R1 = R1 (1) + 3 = 4      (0x04)    ");
    $display("0x1 | 0x0121 | ADD  R1, R2   | R1 = R1 (4) + R2 (2) = 6 (0x06)    ");
    $display("0x2 | 0x1323 | SUB  R3, R2   | R3 = R3 (3) - R2 (2) = 1 (0x01)    ");
    $display("0x3 | 0x6331 | ADDI R3, 1    | R3 = R3 (1) + 1 = 2      (0x02)    ");
    $display("0x4 | 0x1121 | SUB  R1, R2   | R1 = R1 (6) - R2 (2) = 4 (0x04)    ");
    $display("0x5 | 0x7001 | JUMP 1        | PC = 1. (Loops back to PC 0x1)     ");
    $display("===================================================================\n");

    $display("--- Loading Program into Instruction Memory ---");
    load_word(4'd0, 16'h6113); // ADDI R1, 3
    load_word(4'd1, 16'h0121); // ADD  R1, R2
    load_word(4'd2, 16'h1323); // SUB  R3, R2
    load_word(4'd3, 16'h6331); // ADDI R3, 1
    load_word(4'd4, 16'h1121); // SUB  R1, R2
    load_word(4'd5, 16'h7001); // JUMP 1

    #100;
    $display("\n--- Running Program ---");

    @(posedge clk);
    #5;
    uio_in = 8'h80; // run mode, starts execution from PC=0

    check(8'h04, "PC=0: ADDI R1, 3");
    check(8'h06, "PC=1: ADD  R1, R2");
    check(8'h01, "PC=2: SUB  R3, R2");
    check(8'h02, "PC=3: ADDI R3, 1");
    check(8'h04, "PC=4: SUB  R1, R2");

    $display("[INFO] PC=5: JUMP 1 (Advancing clock...)");
    @(posedge clk);

    check(8'h06, "PC=1: ADD  R1, R2 (Second Pass)");

    if (errors == 0)
      $display("\n*** ALL TESTS PASSED ***\n");
    else
      $display("\n!!! FAILED %0d TESTS !!!\n", errors);

    #1000;
    $finish;
  end

endmodule

`default_nettype wire
