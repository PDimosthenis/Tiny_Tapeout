`timescale 1ns / 1ps
`default_nettype none

module tt_um_kishorenetheti_tt8_mips (
    input  wire [7:0] ui_in,  //input    
    output wire [7:0] uo_out, //output   
    input  wire [7:0] uio_in, //bi-in  
    output wire [7:0] uio_out,//bi-out  
    output wire [7:0] uio_oe, //mask which controll bidi  
    input  wire       ena,      
    input  wire       clk,
    input  wire       rst_n
);

    // Tiny Tapeout reset is active-low at the top-level pin.
    wire rst = !rst_n;
    // uio_in[7] selects between instruction loading and CPU execution.
    wire mode = uio_in[7];           // Run = 1, Load = 0
    // During load mode, uio_in[6] selects which byte of a 16-bit word is written.
    wire byte_sel = uio_in[6];       // 0 = low byte, 1 = high byte
    wire [7:0] alu_out;
    wire [3:0] pc_out;
    wire write_ena;

    // Writes to instruction memory are only allowed in load mode.
    assign write_ena = ena & !mode;

    mips_single_cycle cpu (
        .clk(clk),
        .rst(rst),
        .run_en(mode),
        .write_enable(write_ena),
        .write_addr(uio_in[3:0]),
        .write_data_byte(ui_in),
        .write_byte_sel(byte_sel),
        .ALU_out(alu_out),
        .pc_out(pc_out)
    );

    // In run mode show ALU result; in load mode echo ui_in for quick bring-up visibility.
    assign uo_out = mode ? alu_out : ui_in;
    assign uio_oe = mode ? 8'b0000_1111 : 8'b0000_0000;
    // In run mode expose PC[3:0] on bidir pins, otherwise leave output value benign.
    assign uio_out = mode ? {4'b0000, pc_out} : 8'b0000_0000;

endmodule

// --- PC Module ---
module PC(
    input wire clk, rst, en, jump,
    input wire [3:0] jump_address,
    output reg [3:0] pc_out
);
    always @(posedge clk) begin
        if (rst) pc_out <= 4'd0;
        else if (en) pc_out <= jump ? jump_address : (pc_out + 1);
    end
endmodule

// --- Instruction Memory ---
module instruction_memory(
    input wire clk, write_enable,
    input wire [3:0] p_in, write_addr,
    input wire byte_select,
    input wire [7:0] write_data_byte,
    output wire [15:0] instruction
);
    reg [15:0] ram [0:15];

    always @(posedge clk) begin
        if (write_enable) begin
            // Assemble one 16-bit instruction from two 8-bit writes to same address.
            if (byte_select)
                ram[write_addr][15:8] <= write_data_byte;
            else
                ram[write_addr][7:0] <= write_data_byte;
        end
    end

    assign instruction = ram[p_in];
endmodule

// --- Decoder ---
module decoder (
    input wire [15:0] instruction_in,
    output reg [3:0] rs, rt, rd,
    output reg [3:0] im,
    output reg [3:0] jump_addr
);

    wire [3:0] opcode = instruction_in[15:12];

    always @(*) begin
        rs = 4'b0000;
        rt = 4'b0000;
        rd = 4'b0000;
        im = 4'b0000;
        jump_addr = 4'b0000;

        case (opcode)
            4'b0000, // add
            4'b0001, // sub
            4'b0010, // xor 
            4'b0011: //or
             begin // R-type: add, sub, xor, or
                rs = instruction_in[11:8];
                rt = instruction_in[7:4];
                rd = instruction_in[3:0];
            end

            4'b0100, //lw
            4'b0101, //sw
            4'b0110: //addi
             begin // lw, sw, addi
                rs = instruction_in[11:8]; //
                rt = instruction_in[7:4];  //
                im = instruction_in[3:0];  //
            end

            4'b0111: begin // jump
                jump_addr = instruction_in[3:0];
            end

            default: begin
            end
        endcase
    end

endmodule

module alu
  #(parameter ADD = 3'b000,
              SUB = 3'b001,
              ORR = 3'b010,
              XORR = 3'b011)
(
    input wire [15:0] A,
    input wire [15:0] B,
    input wire [2:0] alu_op,
    output reg [15:0] alu_out
);

always @(*) begin
        case (alu_op)
            ADD: alu_out = A + B;
            SUB: alu_out = A - B;
            ORR:  alu_out = A | B;
            XORR: alu_out = A ^ B;
            default: alu_out = 16'b0;
        endcase
   end
endmodule

// --- Control Unit ---
module control_unit (
    input wire [3:0] opcode,
    output reg MemRead,
    output reg MemWrite,
    output reg RegWrite,
    output reg ALUsrc,
    output reg RegDst,
    output reg MemtoReg,
    output reg Jump,
    output reg [2:0] alu_op
);

    always @(*) begin
        // Safe defaults: NOP-like behavior unless opcode enables a path.
        MemRead = 1'b0;
        MemWrite = 1'b0;
        RegWrite = 1'b0;
        ALUsrc = 1'b0;
        RegDst = 1'b0;
        MemtoReg = 1'b0;
        Jump = 1'b0;
        alu_op = 3'b000;

        case (opcode)
            4'b0000: begin RegDst = 1'b1; RegWrite = 1'b1; alu_op = 3'b000; end // add
            4'b0001: begin RegDst = 1'b1; RegWrite = 1'b1; alu_op = 3'b001; end // sub
            4'b0010: begin RegDst = 1'b1; RegWrite = 1'b1; alu_op = 3'b011; end // xor
            4'b0011: begin RegDst = 1'b1; RegWrite = 1'b1; alu_op = 3'b010; end // or
            4'b0100: begin ALUsrc = 1'b1; MemtoReg = 1'b1; RegWrite = 1'b1; MemRead = 1'b1; alu_op = 3'b000; end // lw
            4'b0101: begin ALUsrc = 1'b1; MemWrite = 1'b1; alu_op = 3'b000; end // sw
            4'b0110: begin ALUsrc = 1'b1; RegWrite = 1'b1; alu_op = 3'b000; end // addi
            4'b0111: begin Jump = 1'b1; end // jump
            default: begin
            end
        endcase
    end
endmodule

module data_mem(
    input wire clk,
    input wire MemWrite,
    input wire MemRead,
    input wire [1:0] addr,
    input wire [15:0] writeData,
    output reg [15:0] readData
);

    // 4 x 16-bit data memory.
    reg [15:0] memory [0:3];

    always @(*) begin
        if (MemRead)
            readData = memory[addr];
        else
            readData = 16'b0;
    end

    always @(posedge clk) begin
        if (MemWrite)
            memory[addr] <= writeData;
    end

endmodule

module mips_single_cycle(
    input wire clk, rst, run_en, write_enable,
    input wire [3:0] write_addr,
    input wire [7:0] write_data_byte,
    input wire write_byte_sel,
    output wire [7:0] ALU_out,
    output wire [3:0] pc_out
);
    wire [15:0] instr;
    wire [3:0] rs, rt, rd, im_val, jump_addr;
    wire MemRead, MemWrite, RegWrite, ALUsrc, RegDst, MemtoReg, jump;
    wire [2:0] alu_op;
    wire [15:0] rdata1, rdata2, alu_b, alu_result, sign_ext_imm, mem_data, wb_data;
    wire [1:0] rs_idx, rt_idx, wb_addr;
    integer i;

    // 4 x 16-bit register file. We use low 2 bits of decoded register fields.
    reg [15:0] reg_file [0:3];

    PC pc_u (
        .clk(clk),
        .rst(rst),
        .en(run_en),
        .jump(jump),
        .jump_address(jump_addr),
        .pc_out(pc_out)
    );

    instruction_memory imem_u (
        .clk(clk),
        .write_enable(write_enable),
        .p_in(pc_out),
        .write_addr(write_addr),
        .byte_select(write_byte_sel),
        .write_data_byte(write_data_byte),
        .instruction(instr)
    );

    decoder dec_u (
        .instruction_in(instr),
        .rs(rs),
        .rt(rt),
        .rd(rd),
        .im(im_val),
        .jump_addr(jump_addr)
    );

    control_unit cu_u (
        .opcode(instr[15:12]),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .RegWrite(RegWrite),
        .ALUsrc(ALUsrc),
        .RegDst(RegDst),
        .MemtoReg(MemtoReg),
        .Jump(jump),
        .alu_op(alu_op)
    );

    assign rs_idx = rs[1:0];
    assign rt_idx = rt[1:0];
    assign rdata1 = reg_file[rs_idx];
    assign rdata2 = reg_file[rt_idx];
    // Sign-extend 4-bit immediate to full ALU width.
    assign sign_ext_imm = {{12{im_val[3]}}, im_val};
    assign alu_b = ALUsrc ? sign_ext_imm : rdata2;
    assign wb_addr = RegDst ? rd[1:0] : rt[1:0];

    alu alu_u (
        .A(rdata1),
        .B(alu_b),
        .alu_op(alu_op),
        .alu_out(alu_result)
    );

    data_mem dmem_u (
        .clk(clk),
        .MemWrite(MemWrite & run_en),
        .MemRead(MemRead),
        .addr(alu_result[1:0]),
        .writeData(rdata2),
        .readData(mem_data)
    );

    // Final write-back mux selects ALU result or memory data.
    assign wb_data = MemtoReg ? mem_data : alu_result;
    assign ALU_out = alu_result[7:0];

    always @(posedge clk) begin
        if (rst) begin
            // Deterministic non-zero init helps debug early instruction execution.
            for (i = 0; i < 4; i = i + 1)
                reg_file[i] <= i[15:0];
        end else if (RegWrite && run_en) begin
            reg_file[wb_addr] <= wb_data;
        end
    end
endmodule

`default_nettype wire