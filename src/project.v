`timescale 1ns / 1ps
`default_nettype none

module tt_um_kishorenetheti_tt8_mips (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,
    input  wire       rst_n
);

    wire rst = !rst_n;
    wire mode = uio_in[7];      
    wire [7:0] ALU_out;
    wire [3:0] pc_out;

    mips_single_cycle cpu (
        .clk(clk),
        .rst(rst),
        .run_en(mode),          
        .write_enable(ena & !mode), 
        .write_addr(uio_in[3:0]),
        .write_data(ui_in),
        .ALU_out(ALU_out),
        .pc_out(pc_out)
    );

    assign uo_out = mode ? ALU_out : ui_in;
    assign uio_oe = mode ? 8'b0000_1111 : 8'b0000_0000;
    assign uio_out = mode ? {4'b0, pc_out} : 8'bZZZZ_ZZZZ;

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
    input wire [7:0] write_data,
    output wire [7:0] instruction
);
    reg [7:0] ram [0:15];
    always @(posedge clk) begin
        if(write_enable) ram[write_addr] <= write_data;
    end
    assign instruction = ram[p_in];
endmodule

// --- Fixed Decoder ---
module decode(
    input wire [7:0] instruction_in,
    output reg [1:0] rs, rt, rd,
    output reg [3:0] im
);
    wire [3:0] opcode = instruction_in[7:4];
    always @(*) begin
        rs = 2'b00; rt = 2'b00; rd = 2'b00; im = 4'b0000;
        case(opcode)
            4'b0000, 4'b0001: begin // ADD, SUB
                rd = instruction_in[3:2]; 
                rs = instruction_in[3:2]; // Use target reg as source 1
                rt = 2'b10;               // Use R2 as source 2 (fixed for 8-bit test)
            end
            4'b0010: begin // ADDI
                rd = instruction_in[3:2]; 
                rs = instruction_in[3:2]; // Add immediate to current reg value
                im = {2'b00, instruction_in[1:0]}; 
            end
            4'b0101: im = instruction_in[3:0]; // JUMP
            default: ;
        endcase
    end
endmodule

// --- ALU ---
module ALU(
    input wire [7:0] A, B,
    input wire [2:0] ALUOp,
    output reg [7:0] ALU_out
);
    always @(*) begin
        case(ALUOp)
            3'b000: ALU_out = A + B;
            3'b001: ALU_out = A - B;
            default: ALU_out = 8'b0;
        endcase
    end
endmodule

// --- Control Unit ---
module control_unit(
    input wire [3:0] opcode,
    output reg RegWrite, ALUsrc, jump,
    output reg [2:0] ALUOp
);
    always @(*) begin
        RegWrite=0; ALUsrc=0; jump=0; ALUOp=3'b000;
        case (opcode)
            4'b0000: begin RegWrite=1; ALUOp=3'b000; end // ADD
            4'b0001: begin RegWrite=1; ALUOp=3'b001; end // SUB
            4'b0010: begin RegWrite=1; ALUsrc=1; ALUOp=3'b000; end // ADDI
            4'b0101: begin jump=1; end                             // JUMP
            default: ;
        endcase
    end
endmodule

// --- Fixed CPU Top ---
module mips_single_cycle(
    input wire clk, rst, run_en, write_enable,
    input wire [3:0] write_addr,
    input wire [7:0] write_data,
    output wire [7:0] ALU_out,
    output wire [3:0] pc_out
);
    wire [7:0] instr, rdata1, rdata2, alu_b, sign_ext_imm;
    wire [1:0] rs, rt, rd;
    wire [3:0] im_val; // Local wire for immediate value
    wire ALUsrc, RegWrite, jump;
    wire [2:0] ALUOp;
    integer i;

    PC pc_u (.clk(clk), .rst(rst), .en(run_en), .jump(jump), .jump_address(im_val), .pc_out(pc_out));

    instruction_memory imem_u (
        .clk(clk), .write_enable(write_enable), .p_in(pc_out), 
        .write_addr(write_addr), .write_data(write_data), .instruction(instr)
    );

    decode dec_u (.instruction_in(instr), .rs(rs), .rt(rt), .rd(rd), .im(im_val));
    
    control_unit cu_u (.opcode(instr[7:4]), .RegWrite(RegWrite), .ALUsrc(ALUsrc), .jump(jump), .ALUOp(ALUOp));

    reg [7:0] reg_file [0:3];
    assign rdata1 = reg_file[rs];
    assign rdata2 = reg_file[rt];
    assign sign_ext_imm = {4'b0, im_val};
    assign alu_b = ALUsrc ? sign_ext_imm : rdata2;

    ALU alu_u (.A(rdata1), .B(alu_b), .ALUOp(ALUOp), .ALU_out(ALU_out));

    always @(posedge clk) begin
        if (rst) begin
            for (i=0; i<4; i=i+1) reg_file[i] <= i[7:0]; 
        end else if (RegWrite && run_en) begin 
            reg_file[rd] <= ALU_out;
        end
    end
endmodule