/*
 * MIPS-Lite 8-bit Processor for Tiny Tapeout
 * Copyright (c) 2025 Jesus (jalperdev)
 * SPDX-License-Identifier: Apache-2.0
 *
 * An 8-bit MIPS-inspired single-cycle processor that preserves the
 * architectural concepts of a full 32-bit MIPS:
 *   - 8 general-purpose registers (R0 hardwired to 0)
 *   - 8-bit ALU with ADD, SUB, AND, OR, SLT
 *   - 16-bit instruction format (R-type, I-type, J-type)
 *   - Branch (BEQ, BNE), Jump (J), and HALT instructions
 *   - 32-entry combinational instruction ROM
 *   - Single-cycle execution
 *
 * Instruction Formats (16-bit):
 *   R-type: [opcode(4)][rs(3)][rt(3)][rd(3)][funct(3)]
 *   I-type: [opcode(4)][rs(3)][rt(3)][imm(6)]
 *   J-type: [opcode(4)][addr(5)][unused(7)]
 *
 * Pin Mapping:
 *   ui_in[2:0]  = reg_sel: select register to display on uo_out
 *   ui_in[7:3]  = unused
 *   uo_out[7:0] = selected register value (8-bit)
 *   uio_out[4:0]= current PC value
 *   uio_out[5]  = halt flag
 *   uio_out[6]  = alu zero flag
 *   uio_out[7]  = unused (0)
 */

`default_nettype none

module tt_um_wokwi_465731481873367041 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // =========================================================================
    // Internal signals
    // =========================================================================
    wire        reset = ~rst_n;      // Convert active-low to active-high
    wire [2:0]  reg_sel = ui_in[2:0]; // Register select for debug output
    wire [7:0]  reg_debug_out;       // Selected register value
    wire [4:0]  pc_out;              // Current PC
    wire        halt_out;            // Halt flag
    wire        alu_zero_out;        // ALU zero flag

    // =========================================================================
    // CPU Core instantiation
    // =========================================================================
    mips_lite_cpu cpu (
        .clk        (clk),
        .reset      (reset),
        .reg_sel    (reg_sel),
        .reg_data   (reg_debug_out),
        .pc_out     (pc_out),
        .halt_out   (halt_out),
        .alu_zero   (alu_zero_out)
    );

    // =========================================================================
    // Output mapping
    // =========================================================================
    assign uo_out  = reg_debug_out;                   // 8-bit register value
    assign uio_out = {1'b0, alu_zero_out, halt_out, pc_out}; // Status + PC
    assign uio_oe  = 8'b1111_1111;                    // All bidirectional as outputs

    // Unused inputs — suppress lint warnings
    wire _unused = &{ena, uio_in, ui_in[7:3], 1'b0};

endmodule


// =============================================================================
// MIPS-Lite CPU Core
// =============================================================================
module mips_lite_cpu (
    input  wire        clk,
    input  wire        reset,
    input  wire [2:0]  reg_sel,    // Debug: which register to output
    output wire [7:0]  reg_data,   // Debug: selected register value
    output wire [4:0]  pc_out,     // Current program counter
    output wire        halt_out,   // CPU halted flag
    output wire        alu_zero    // ALU zero flag (last result)
);

    // =========================================================================
    // Program Counter
    // =========================================================================
    reg [4:0] pc;
    reg       halted;

    assign pc_out   = pc;
    assign halt_out = halted;

    // =========================================================================
    // Instruction Fetch — Combinational ROM
    // =========================================================================
    wire [15:0] instruction;
    instruction_rom rom (
        .addr       (pc),
        .data       (instruction)
    );

    // =========================================================================
    // Instruction Decode
    // =========================================================================
    wire [3:0] opcode = instruction[15:12];
    wire [2:0] rs     = instruction[11:9];
    wire [2:0] rt     = instruction[8:6];
    wire [2:0] rd     = instruction[5:3];
    wire [2:0] funct  = instruction[2:0];
    wire [5:0] imm6   = instruction[5:0];
    wire [4:0] jaddr  = instruction[11:7];

    // Sign-extend immediate (6-bit → 8-bit)
    wire [7:0] sign_ext_imm = {{2{imm6[5]}}, imm6};

    // Opcodes
    localparam OP_RTYPE = 4'b0000;
    localparam OP_ADDI  = 4'b0001;
    localparam OP_ANDI  = 4'b0010;
    localparam OP_ORI   = 4'b0011;
    localparam OP_BEQ   = 4'b0100;
    localparam OP_BNE   = 4'b0101;
    localparam OP_J     = 4'b0110;
    localparam OP_LUI   = 4'b0111;
    localparam OP_HALT  = 4'b1111;

    // R-type function codes
    localparam FUNC_ADD = 3'b000;
    localparam FUNC_SUB = 3'b001;
    localparam FUNC_AND = 3'b010;
    localparam FUNC_OR  = 3'b011;
    localparam FUNC_SLT = 3'b100;

    // =========================================================================
    // Control Signals (combinational)
    // =========================================================================
    wire is_rtype  = (opcode == OP_RTYPE);
    wire is_addi   = (opcode == OP_ADDI);
    wire is_andi   = (opcode == OP_ANDI);
    wire is_ori    = (opcode == OP_ORI);
    wire is_beq    = (opcode == OP_BEQ);
    wire is_bne    = (opcode == OP_BNE);
    wire is_jump   = (opcode == OP_J);
    wire is_lui    = (opcode == OP_LUI);
    wire is_halt   = (opcode == OP_HALT);

    // Register write enable: write for R-type, ADDI, ANDI, ORI, LUI
    wire reg_write = is_rtype | is_addi | is_andi | is_ori | is_lui;

    // ALU source B: immediate for I-type, register for R-type
    wire alu_src_imm = is_addi | is_andi | is_ori;

    // Write destination: rd for R-type, rt for I-type
    wire [2:0] write_reg = is_rtype ? rd : rt;

    // =========================================================================
    // Register File (8 x 8-bit, R0 hardwired to 0)
    // =========================================================================
    reg [7:0] regfile [1:7]; // R1 through R7 (R0 is always 0)

    // Read ports (combinational)
    wire [7:0] rs_data = (rs == 3'd0) ? 8'd0 : regfile[rs];
    wire [7:0] rt_data = (rt == 3'd0) ? 8'd0 : regfile[rt];

    // Debug read port
    assign reg_data = (reg_sel == 3'd0) ? 8'd0 : regfile[reg_sel];

    // =========================================================================
    // ALU (8-bit, combinational)
    // =========================================================================
    wire [7:0] alu_input_b = alu_src_imm ? sign_ext_imm : rt_data;
    reg  [7:0] alu_result;
    reg        alu_zero_flag;

    always @(*) begin
        alu_result = 8'd0;
        if (is_rtype) begin
            case (funct)
                FUNC_ADD: alu_result = rs_data + alu_input_b;
                FUNC_SUB: alu_result = rs_data - alu_input_b;
                FUNC_AND: alu_result = rs_data & alu_input_b;
                FUNC_OR:  alu_result = rs_data | alu_input_b;
                FUNC_SLT: alu_result = ($signed(rs_data) < $signed(alu_input_b)) ? 8'd1 : 8'd0;
                default:  alu_result = 8'd0;
            endcase
        end else if (is_addi) begin
            alu_result = rs_data + sign_ext_imm;
        end else if (is_andi) begin
            alu_result = rs_data & {2'b00, imm6}; // Zero-extend for ANDI
        end else if (is_ori) begin
            alu_result = rs_data | {2'b00, imm6}; // Zero-extend for ORI
        end else if (is_lui) begin
            alu_result = {imm6[5:0], 2'b00};      // Load upper: shift left by 2
        end
        alu_zero_flag = (alu_result == 8'd0);
    end

    assign alu_zero = alu_zero_flag;

    // Write-back data selection
    wire [7:0] write_data = alu_result;

    // =========================================================================
    // Branch logic (combinational)
    // =========================================================================
    wire beq_taken = is_beq & (rs_data == rt_data);
    wire bne_taken = is_bne & (rs_data != rt_data);
    wire branch_taken = beq_taken | bne_taken;

    // Branch target: PC + 1 + sign_ext_imm[4:0] (relative)
    wire [4:0] pc_plus_1    = pc + 5'd1;
    wire [4:0] branch_target = pc_plus_1 + sign_ext_imm[4:0];
    wire [4:0] next_pc = is_jump      ? jaddr :
                         branch_taken ? branch_target :
                                        pc_plus_1;

    // =========================================================================
    // Sequential Logic — Clock Edge
    // =========================================================================
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            pc <= 5'd0;
            halted <= 1'b0;
            for (i = 1; i <= 7; i = i + 1)
                regfile[i] <= 8'd0;
        end else if (!halted) begin
            // Update PC
            if (is_halt)
                halted <= 1'b1;
            else
                pc <= next_pc;

            // Register write-back (never write to R0)
            if (reg_write && (write_reg != 3'd0))
                regfile[write_reg] <= write_data;
        end
    end

endmodule


// =============================================================================
// Instruction ROM — 32 x 16-bit Combinational ROM
// =============================================================================
// This module contains the hardcoded program. Edit the case entries to change
// the program your MIPS-Lite executes.
//
// Instruction encoding reference:
//   R-type: {opcode[3:0], rs[2:0], rt[2:0], rd[2:0], funct[2:0]}
//   I-type: {opcode[3:0], rs[2:0], rt[2:0], imm[5:0]}
//   J-type: {opcode[3:0], addr[4:0], unused[6:0]}
// =============================================================================
module instruction_rom (
    input  wire [4:0]  addr,
    output reg  [15:0] data
);

    always @(*) begin
        case (addr)
            // ---- Arithmetic Demo Program ----
            // R0 = 0 (hardwired), R1-R7 = general purpose
            //
            // Program: Fibonacci-like sequence + branch test
            //   Computes first few Fibonacci numbers, tests branches,
            //   demonstrates all instruction types

            // Phase 1: Load initial values
            5'd0:  data = 16'b0001_000_001_000001;  // ADDI R1, R0, 1     → R1 = 1
            5'd1:  data = 16'b0001_000_010_000001;  // ADDI R2, R0, 1     → R2 = 1

            // Phase 2: Fibonacci iterations (R3 = R1+R2, R1 = R2, R2 = R3)
            5'd2:  data = 16'b0000_001_010_011_000; // ADD  R3, R1, R2    → R3 = R1+R2 = 2
            5'd3:  data = 16'b0000_010_000_001_000; // ADD  R1, R2, R0    → R1 = R2    = 1
            5'd4:  data = 16'b0000_011_000_010_000; // ADD  R2, R3, R0    → R2 = R3    = 2

            5'd5:  data = 16'b0000_001_010_011_000; // ADD  R3, R1, R2    → R3 = 1+2   = 3
            5'd6:  data = 16'b0000_010_000_001_000; // ADD  R1, R2, R0    → R1 = R2    = 2
            5'd7:  data = 16'b0000_011_000_010_000; // ADD  R2, R3, R0    → R2 = R3    = 3

            5'd8:  data = 16'b0000_001_010_011_000; // ADD  R3, R1, R2    → R3 = 2+3   = 5
            5'd9:  data = 16'b0000_010_000_001_000; // ADD  R1, R2, R0    → R1 = R2    = 3
            5'd10: data = 16'b0000_011_000_010_000; // ADD  R2, R3, R0    → R2 = R3    = 5

            // Phase 3: Test ALU operations
            5'd11: data = 16'b0000_001_010_100_010; // AND  R4, R1, R2    → R4 = 3 & 5 = 1
            5'd12: data = 16'b0000_001_010_101_011; // OR   R5, R1, R2    → R5 = 3 | 5 = 7
            5'd13: data = 16'b0000_001_010_110_001; // SUB  R6, R1, R2    → R6 = 3 - 5 = 254 (-2)
            5'd14: data = 16'b0000_001_010_111_100; // SLT  R7, R1, R2    → R7 = (3<5) = 1

            // Phase 4: Test branches
            5'd15: data = 16'b0100_111_001_000001;  // BEQ  R7, R1, +1    → 1==3? No, don't branch
            5'd16: data = 16'b0001_000_100_010101;  // ADDI R4, R0, 21    → R4 = 21
            5'd17: data = 16'b0101_111_100_000001;  // BNE  R7, R4, +1    → 1!=21? Yes, skip next
            5'd18: data = 16'b0001_000_100_011111;  // ADDI R4, R0, 31    → SKIPPED
            5'd19: data = 16'b0011_000_101_001111;  // ORI  R5, R0, 0x0F  → R5 = 15

            // Phase 5: Jump and halt
            5'd20: data = 16'b0110_10101_0000000;   // J    21            → Jump to addr 21
            5'd21: data = 16'b1111_000000000000;    // HALT               → Stop execution

            // Fill remaining slots with HALT
            default: data = 16'b1111_000000000000;  // HALT
        endcase
    end

endmodule
