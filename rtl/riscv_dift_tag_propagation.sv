// DIFT extension for CV32E40P
// Tag Propagation Unit
// Autor:   Jakob Sailer, Bsc
// created: 2021-03-20


import riscv_defines::*;


module dift_tag_propagation
(
    // operand's tag bits (alu operands, mult operands, mult_dot operands)
    input  logic alu_operand_a_tag_i,
    input  logic alu_operand_b_tag_i,
    input  logic alu_operand_c_tag_i,
    input  logic mult_operand_a_tag_i,
    input  logic mult_operand_b_tag_i,
    input  logic mult_operand_c_tag_i,
    input  logic mult_dot_op_a_tag_i,
    input  logic mult_dot_op_b_tag_i,
    input  logic mult_dot_op_c_tag_i,
    
    // enable bits (ALU or MULT or CSR)
    input  logic alu_en_i,
    input  logic mult_en_i,
    input  logic csr_access_i,
    // operation
    input  logic [ALU_OP_WIDTH-1:0] alu_operator_i,
    input  logic [2:0] mult_operator_i,
    // output (resulting tag)
    output logic tag_result_o
);

  logic tag_result_alu;
  logic tag_result_mult;
  logic tag_result_mult_dot;
  
  // ALU tag propagation
  // TODO: implement different ALU classes
  // TODO: clarify when to use which operands (a, b, c)
  assign tag_result_alu = alu_operand_a_tag_i | alu_operand_b_tag_i | alu_operand_c_tag_i;
  
  // MULT tag propagation
  assign tag_result_mult = mult_operand_a_tag_i | mult_operand_b_tag_i | mult_operand_c_tag_i;
  
  // MULT_DOT tag propagation
  assign tag_result_mult_dot = mult_dot_op_a_tag_i | mult_dot_op_b_tag_i | mult_dot_op_c_tag_i;
  
  // result output MUX
  always_comb
  begin
    tag_result_o = 1'b0;

    // APU single cycle operations, and multicycle operations (>2cycles) are written back on ALU port
    if (alu_en_i) begin
      tag_result_o = tag_result_alu;
    end
    if (mult_en_i) begin
      // TODO: distinguish between MULT and MULT_DOT
      tag_result_o = tag_result_mult;
    end
    if (csr_access_i) begin
      tag_result_o = 1'b0;  // reading CSRs results always in not tainted data
    end
  end
  
endmodule
