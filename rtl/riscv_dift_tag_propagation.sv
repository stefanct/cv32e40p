// DIFT extension for CV32E40P
// Tag Propagation Unit
// Autor:   Jakob Sailer, Bsc
// created: 2021-03-20

`include "riscv_dift_config.sv"

import riscv_defines::*;


module dift_tag_propagation
(
    // tag bits of the operands of the current instruction
    input  dift_tag_t     operand_a_tag_i,
    input  dift_tag_t     operand_b_tag_i,
    input  dift_tag_t     operand_c_tag_i,

    // type of instruction that is executed
    input  dift_opclass_t opclass_i,

    // TPCR (tag propagation configuration register)
    input  dift_tpcr_t    tpcr_i,

    // calculated output tag
    output dift_tag_t     result_o
);

  // configured policy per operation class
  dift_proppol_mem_t policy_store;
  dift_propmode2_t   policy_alu;
  dift_propmode2_t   policy_shift;  // TODO properly !!!
  dift_propmode2_t   policy_comp;
  dift_propmode1_t   policy_csr;
  dift_propmode2_t   policy_mul;
  dift_propmode2_t   policy_float;

  assign policy_store.en_value = tpcr_i[   18];
  assign policy_store.en_addr  = tpcr_i[   17];
  assign policy_store.mode     = tpcr_i[16:15];
  assign policy_alu   = tpcr_i[10:9];
  assign policy_shift = tpcr_i[ 8:7];
  assign policy_comp  = tpcr_i[ 6:5];
  assign policy_csr   = tpcr_i[   4];
  assign policy_mul   = tpcr_i[ 3:2];
  assign policy_float = tpcr_i[ 1:0];


  // operation class mux
  always_comb
  begin

    // 
    unique case (opclass_i)
      DIFT_OPCLASS_LOAD,    // propagation of loads is done in the LSU -> no tag output needed
      DIFT_OPCLASS_XUI,     // LUI, AUIPC: using only immediates -> output is never tagged
      DIFT_OPCLASS_JUMP,    // jumps: current PC + 4 is written to rd (link register) -> output is never tagged
      DIFT_OPCLASS_BRANCH,  // branches have no rd -> no tag output needed
      DIFT_OPCLASS_SYS:     // FENCE, FENCE.I, ECALL, EBREAK -> no tag output needed
      begin
        result_o = '0;
      end

/*
      DIFT_OPCLASS_LOAD: begin
        // the value propagation cannot be done here, but only in the LSU. So (only) for loads, the result_o
        // does not represent the final tag result, but it has to be further combined with the value's tags and
        // propagation configuration in the LSU.
        if (policy_load_addr_en == 1'b1)
          result_o = operand_a_tag_i;
        else
          result_o = '0;
      end
*/

      DIFT_OPCLASS_STORE: begin
        dift_tag_t temp_tag_val_store;
        dift_tag_t temp_tag_addr_store;
        // handle value and address propagation enable policies
        //   operand a holds the base address in store operations
        //   operand b holds the immediate (address offset) in store operations -> can be ignored for propagation
        //   operand c holds the value in store operations
        temp_tag_val_store  = operand_c_tag_i & {DIFT_TAG_SIZE{policy_store.en_value}};
        temp_tag_addr_store = {DIFT_TAG_SIZE{ (|operand_a_tag_i) & policy_store.en_addr }};

        // handle propagation mode policy
        unique case(policy_store.mode)
          DIFT_PROPMODE2_OR:   result_o = temp_tag_val_store | temp_tag_addr_store;
          DIFT_PROPMODE2_AND:  result_o = temp_tag_val_store & temp_tag_addr_store;
          DIFT_PROPMODE2_ZERO: result_o = '0;
          DIFT_PROPMODE2_ONE:  result_o = '1;
          default:             result_o = '0;
        endcase
      end

      // TODO: handle pseudoinstruction properly (e.g. mv: mv rd, rs  ==> addi rd, rs, 0)
      DIFT_OPCLASS_ALU,
      DIFT_OPCLASS_SHIFT, // TODO: special handling for shifts needed?
      DIFT_OPCLASS_COMP,
      DIFT_OPCLASS_MUL,
      DIFT_OPCLASS_FLOAT:
      begin
        logic [1:0] temp_used_policy;

        // select the respective policy
        unique case(opclass_i)
          DIFT_OPCLASS_ALU:   temp_used_policy = policy_alu;
          DIFT_OPCLASS_SHIFT: temp_used_policy = policy_shift;
          DIFT_OPCLASS_COMP:  temp_used_policy = policy_comp;
          DIFT_OPCLASS_MUL:   temp_used_policy = policy_mul;
          DIFT_OPCLASS_FLOAT: temp_used_policy = policy_float;
          default:            temp_used_policy = DIFT_PROPMODE2_ZERO;
        endcase

        // apply the configured propagation policy
        unique case(temp_used_policy)
          DIFT_PROPMODE2_OR:   result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) | (|operand_b_tag_i) }};
          DIFT_PROPMODE2_AND:  result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) & (|operand_b_tag_i) }};
          DIFT_PROPMODE2_ZERO: result_o = '0;
          DIFT_PROPMODE2_ONE:  result_o = '1;
          default:             result_o = '0;
        endcase
      end

      DIFT_OPCLASS_CSR: begin
        if (policy_csr == DIFT_PROPMODE1_ONE)
          result_o = '1;
        else  // DIFT_PROPMODE1_ZERO
          result_o = '0;
      end

      DIFT_OPCLASS_OTHER: result_o = '1; // TODO okay?
      default:            result_o = '1; // TODO okay?
    endcase
  end

endmodule
