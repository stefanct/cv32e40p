// DIFT extension for CV32E40P
// Tag Propagation Unit
// Autor:   Jakob Sailer, Bsc
// created: 2021-03-20

`include "riscv_dift_config.sv"

import riscv_defines::*;


module dift_tag_propagation
(
    // TPCR (tag propagation configuration register)
    input  dift_tpcr_t  tpcr_i,

    // type of instruction that is executed
    input  dift_prop_opclass_t opclass_i,

    // which registers are used by the instruction
    input  logic        rega_used_i,
    input  logic        regb_used_i,
    input  logic        regc_used_i,

    // tag bits of the operands of the current instruction
    input  dift_tag_t   operand_a_tag_i,
    input  dift_tag_t   operand_b_tag_i,
    input  dift_tag_t   operand_c_tag_i,

    // calculated output tag
    output dift_tag_t   result_o
);

  // operation class mux
  always_comb
  begin
    unique case (opclass_i)

      // No propagation needed
      DIFT_PROP_OPCLASS_NONE:  // tag propagation for LOADs is implemented in LSU (cannot be done here)
      begin
        result_o = '0;
      end

      // LOAD / STORE propagation is basically done in the LSU!
      // However, for misaligned accesses, the ALU is used to calculate the address for the second memory
      // access (new address = old address + 4).
      // While the LSU loads/stores the first value from/to memory, the ALU executes the ADD instruction
      // for the source/destination address of the second memory access.
      // The calculation result (new address) is forwarded via the regfile_alu_wdata_fw signal.
      // Thus we have to do the tag propagation also accordingly here for the ADD instruction.
      DIFT_PROP_OPCLASS_LOAD,
      DIFT_PROP_OPCLASS_STOR:
      begin
        // just and forward the tag bits as they were before the addition with the constant 4
        result_o = operand_a_tag_i;
      end


      // special BRANCH propagation
      // TODO: an implementation like in Chen2005a would be nice
      // TODO: analyse if this is even possible with RISC-V architecture
      DIFT_PROP_OPCLASS_BRAN:
      begin
        // tpcr_i.bran_clr
        result_o = '0;
      end


      // special CSR access propagation (relevant only for CSR reads)
      DIFT_PROP_OPCLASS_CSR:
      begin
        if (~tpcr_i.csr_en)
          result_o = '0;
        else
          result_o = '1;
      end


      // special SHIFT propagation
      DIFT_PROP_OPCLASS_SHFT:
      begin
        if (~tpcr_i.shft.en)
        begin
          result_o = '0;
        end
        else
        begin
          // reg-reg instruction, and both operands shall be used for propagation
          if ((regb_used_i) && (tpcr_i.shft.en_shamt))
          begin
            if (tpcr_i.shft.mode == DIFT_PROP_MODE_OR)
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) | (|operand_b_tag_i) }};  // OR combination
            end
            else  // DIFT_PROP_MODE_AND
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) & (|operand_b_tag_i) }};  // AND combination
            end
          end
          // either it is a reg-imm instruction, or it is a reg-reg instruction but operand b (shamt) shall not be considered
          //  => only operand a has to be considered
          else
          begin
            result_o = {DIFT_TAG_SIZE{ |operand_a_tag_i }};
          end
        end
      end


      // common propagation for normal 2-operand ALU instructions
      DIFT_PROP_OPCLASS_LOG,
      DIFT_PROP_OPCLASS_ADD,
      DIFT_PROP_OPCLASS_MUL,
      DIFT_PROP_OPCLASS_COMP,
      DIFT_PROP_OPCLASS_FPU:
      begin
        // select correct policy configuration
        logic temp_policy_en;
        logic temp_policy_mode;

        unique case (opclass_i)
          DIFT_PROP_OPCLASS_LOG: begin
            temp_policy_en   = tpcr_i.log.en;
            temp_policy_mode = tpcr_i.log.mode;
          end
          DIFT_PROP_OPCLASS_ADD: begin
            temp_policy_en   = tpcr_i.add.en;
            temp_policy_mode = tpcr_i.add.mode;
          end
          DIFT_PROP_OPCLASS_MUL: begin
            temp_policy_en   = tpcr_i.mul.en;
            temp_policy_mode = tpcr_i.mul.mode;
          end
          DIFT_PROP_OPCLASS_COMP: begin
            temp_policy_en   = tpcr_i.comp.en;
            temp_policy_mode = tpcr_i.comp.mode;
          end
          DIFT_PROP_OPCLASS_FPU: begin
            temp_policy_en   = tpcr_i.fpu.en;
            temp_policy_mode = tpcr_i.fpu.mode;
          end
        endcase

        // apply selected policy
        if (~temp_policy_en)
        begin
          result_o = '0;
        end
        else
        begin
          // reg-imm instruction
          if (~regb_used_i)
          begin
            result_o = {DIFT_TAG_SIZE{ |operand_a_tag_i }}; // just forward the only register operand (rs1)
          end
          // reg-reg instruction
          else
          begin
            if (temp_policy_mode == DIFT_PROP_MODE_OR)
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) | (|operand_b_tag_i) }};  // OR combination
            end
            else  // DIFT_PROP_MODE_AND
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) & (|operand_b_tag_i) }};  // AND combination
            end
          end
        end //~apply selected policy

      end //~common propagation for normal 2-operand ALU instructions


      // special Xpulp propagation
      // TODO: maybe some special handling is needed here
      DIFT_PROP_OPCLASS_XPLP:
      begin
        if (~tpcr_i.xplp.en)
        begin
          result_o = '0;
        end
        else
        begin
          // 3-operand-instructions
          if ((rega_used_i) && (regb_used_i) && (regc_used_i))
          begin
            if (tpcr_i.xplp.mode == DIFT_PROP_MODE_OR)
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) | (|operand_b_tag_i) | (|operand_c_tag_i) }};  // OR combination
            end
            else  // DIFT_PROP_MODE_AND
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) & (|operand_b_tag_i) & (|operand_c_tag_i) }};  // AND combination
            end
          end

          // 2-operand-instructions
          else if ((rega_used_i) && (regb_used_i))
          begin
            if (tpcr_i.xplp.mode == DIFT_PROP_MODE_OR)
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) | (|operand_b_tag_i) }};  // OR combination
            end
            else  // DIFT_PROP_MODE_AND
            begin
              result_o = {DIFT_TAG_SIZE{ (|operand_a_tag_i) & (|operand_b_tag_i) }};  // AND combination
            end
          end

          // 1-operand-instructions
          else
          begin
            result_o = {DIFT_TAG_SIZE{ operand_a_tag_i }};
          end
        end
      end

    endcase

  end //~always_comb

endmodule
