/*
 * Testbench for MIPS-Lite 8-bit Processor
 * Copyright (c) 2025 Jesus (jalperdev)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

module tb ();

    // Dump the signals to a VCD file for viewing
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

    // Signals
    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // Instantiate the DUT
    tt_um_jalper_mips tt_um_jalper_mips (
`ifdef GL_TEST
        .VPWR(VPWR),
        .VGND(VGND),
`endif
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // Clock generation: 50 MHz (20ns period)
    initial clk = 0;
    always #10 clk = ~clk;

    // Helper signals for readability
    wire [4:0] pc   = uio_out[4:0];
    wire       halt = uio_out[5];
    wire [7:0] reg_val = uo_out;

    // Expected register values after program execution
    reg [7:0] expected [0:7];
    initial begin
        expected[0] = 8'd0;    // R0 is hardwired to 0
        expected[1] = 8'd3;    // R1 = 3 (Fibonacci intermediate)
        expected[2] = 8'd5;    // R2 = 5 (Fibonacci result)
        expected[3] = 8'd5;    // R3 = 5 (Fibonacci result)
        expected[4] = 8'd21;   // R4 = 21 (ADDI)
        expected[5] = 8'd15;   // R5 = 15 (ORI)
        expected[6] = 8'd254;  // R6 = -2 (SUB: 3 - 5 = 254 in 8-bit unsigned)
        expected[7] = 8'd1;    // R7 = 1 (SLT: 3 < 5)
    end

    reg test_failed;
    initial test_failed = 0;

    // Main test sequence
    initial begin
        // Initialize inputs
        ui_in  = 8'd0;
        uio_in = 8'd0;
        ena    = 1'b1;
        rst_n  = 1'b0;  // Assert reset

        // Hold reset for a few cycles
        repeat (3) @(posedge clk);
        rst_n = 1'b1;  // Release reset

        // Wait for the CPU to halt (max 30 cycles)
        repeat (30) begin
            @(posedge clk);
            if (halt) begin
                $display("CPU HALTED at PC=%d", pc);
                // Read all registers
                check_registers();
                if (test_failed) begin
                    $display("=== TEST FAILED ===");
                    #20;
                    $finish_and_return(1);
                end else begin
                    $display("=== ALL TESTS PASSED ===");
                    #20;
                    $finish_and_return(0);
                end
            end
        end

        $display("ERROR: CPU did not halt within 30 cycles!");
        $finish_and_return(1);
    end

    // Task to read and display all registers
    task check_registers;
        integer r;
        begin
            for (r = 0; r < 8; r = r + 1) begin
                ui_in[2:0] = r[2:0];
                #1; // Allow combinational logic to settle
                $display("  R%0d = %0d (0x%02h)", r, uo_out, uo_out);
                if (uo_out !== expected[r]) begin
                    $display("  ERROR: R%0d expected %0d (0x%02h), got %0d (0x%02h)", r, expected[r], expected[r], uo_out, uo_out);
                    test_failed = 1;
                end
            end
        end
    endtask

endmodule
