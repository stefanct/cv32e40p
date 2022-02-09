// DIFT extension for CV32E40P
// DIFT Manipulation Unit
//   implementing custom instructions to manually read/write tag bits of registers
// Autor:   Jakob Sailer, Bsc
// created: 2022-02-01

`include "riscv_dift_config.sv"

import riscv_defines::*;


module riscv_dift_tag_manipulation
(
    input  logic [ 2:0] operator_i,
    input  logic [31:0] operand_a_i,
    input  logic [31:0] operand_b_i,
    input  logic [31:0] operand_c_i,
    input  dift_tag_t   operand_a_tag_i,
    input  dift_tag_t   operand_b_tag_i,
    input  dift_tag_t   operand_c_tag_i,

    output logic [31:0] result_o,
    output dift_tag_t   result_tag_o
);

  logic  [3:0] tagset_bitmask;
  logic  [3:0] tagset_newvalues;
  dift_tag_t   tagset_result_tag;

  logic  [3:0] tagrd_bitmask;
  logic [31:0] tagrd_result;


  // tagset: calculation logic
  assign tagset_bitmask   = operand_a_i[3:0] | operand_b_i[3:0];
  assign tagset_newvalues = operand_a_i[7:4] | operand_b_i[7:4];
  generate
    if (DIFT_TAG_SIZE == 1)
      assign tagset_result_tag = tagset_bitmask[0] ? tagset_newvalues[0] : operand_c_tag_i;
    else if (DIFT_TAG_SIZE == 4) begin
      assign tagset_result_tag[0] = tagset_bitmask[0] ? tagset_newvalues[0] : operand_c_tag_i[0];
      assign tagset_result_tag[1] = tagset_bitmask[1] ? tagset_newvalues[1] : operand_c_tag_i[1];
      assign tagset_result_tag[2] = tagset_bitmask[2] ? tagset_newvalues[2] : operand_c_tag_i[2];
      assign tagset_result_tag[3] = tagset_bitmask[3] ? tagset_newvalues[3] : operand_c_tag_i[3];
    end
  endgenerate


  // tagrd: calculation logic
  assign tagrd_bitmask    = operand_b_i[3:0];
  generate
    if (DIFT_TAG_SIZE == 1)
      assign tagrd_result = { {31{1'b0}} , operand_a_tag_i & tagrd_bitmask[0] };
    else if (DIFT_TAG_SIZE == 4)
      assign tagrd_result = { {28{1'b0}} , operand_a_tag_i & tagrd_bitmask };
  endgenerate


  // opcode mux
  always_comb
  begin
    result_o     = '0;
    result_tag_o = '0;

    unique case (operator_i)
      // TAG.SET
      // set (overwrite) tag bits of rd as specified with bitmask and values
      // bitmask and values are given either via operand a (register value) or operand b (immediate value)
      // the original data of rd must be preserved (is passed through via operand c)
      DIFT_OP_TAGSET: begin
        result_o     = operand_c_i;
        result_tag_o = tagset_result_tag;
      end

      // TAG.RD
      // read out tag bits of rs1 into rd
      DIFT_OP_TAGRD: begin
        result_o     = tagrd_result;
        result_tag_o = '0;
      end

      // no operation
      // this should never happen
      default:;
    endcase
  end

endmodule
