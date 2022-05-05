// DIFT extension for CV32E40P
// Tag Check Unit
// Autor:   Jakob Sailer, Bsc
// created: 2021-04-13

`include "riscv_dift_config.sv"

import riscv_defines::*;


module dift_tag_check
(
    input  logic          clk,
    input  logic          rst_n,

    // tag bits of the instruction currently provided by IF
    input  logic [3:0]    instr_tag_i,        // for execution check (all instructions)
    // jump indicator (if any occurs and also which type of jump/branch) decoded in ID
    input logic [1:0]     jump_in_i,          // for jump/branch instructions
    // tag bits of jump target (calculated in ID)
    input dift_tag_t      jump_target_tag_i,  // only for jump instructions (JALR)
    // tag bits of operand a and b
    input  dift_tag_t     operand_a_tag_i,    // for branch and load/store instructions
    input  dift_tag_t     operand_b_tag_i,    // for branch insructions
    // type of instruction that is executed
    input  dift_opclass_t opclass_i,          // for load/store instructions

    // TCCR (tag check configuration register)
    input  dift_tccr_t    tccr_i,

    // output signals
    output logic        trap_o,
    output dift_trap_t  trap_type_o
);

  // check implementation
  logic result_exec;
  logic result_jalr;
  logic result_branch;
  logic temp_result_b_single_mode;
  logic result_store;
  logic result_load;
  logic trap_result;
  logic trap_result_q;
  dift_trap_t trap_type;

  // CHECK EXECUTION
  always_comb
  begin
    // default assignment
    result_exec = 1'b0;
    // is the policy activated for this check?
    if (tccr_i.exec == DIFT_CHECKMODE1_ON) begin
      // apply check logic
      result_exec = |instr_tag_i;
    end
  end

  // CHECK JALR
  always_comb
  begin
    // default assignment
    result_jalr = 1'b0;
    // is a JALR instruction executed?
    // is the policy activated for this check?
    if ((jump_in_i == BRANCH_JALR) && (tccr_i.jalr == DIFT_CHECKMODE1_ON)) begin
      // apply check logic
      result_jalr = |jump_target_tag_i;
    end
  end

  // CHECK BRANCH
  always_comb
  begin
    // default assignment
    result_branch = 1'b0;
    // is a branch instruction executed?
    if (jump_in_i == BRANCH_COND) begin
      // apply check logic for single-mode (only checking one operand of the branch decision expression)
      unique case (tccr_i.branch.single_mode_select)
        DIFT_CHECK_SINGLEMODESELECT_OP_A:   temp_result_b_single_mode = (|operand_a_tag_i);
        DIFT_CHECK_SINGLEMODESELECT_OP_B:   temp_result_b_single_mode = (|operand_b_tag_i);
      endcase

      // apply check logic depending on configured check policy
      unique case (tccr_i.branch.mode)
        DIFT_CHECKMODE2_OFF:    result_branch = 1'b0;
        DIFT_CHECKMODE2_OR:     result_branch = (|operand_a_tag_i) | (|operand_b_tag_i);
        DIFT_CHECKMODE2_AND:    result_branch = (|operand_a_tag_i) & (|operand_b_tag_i);
        DIFT_CHECKMODE2_SINGL:  result_branch = temp_result_b_single_mode;
      endcase
    end
  end

  // CHECK STORE
  always_comb
  begin
    // default assignment
    result_store = 1'b0;
    // is a store instruction executed?
    // is the policy activated for this check?
    if ((opclass_i == DIFT_OPCLASS_STORE) && (tccr_i.store == DIFT_CHECKMODE1_ON)) begin
      // apply check logic
      result_store = |operand_a_tag_i;  // operand a holdds the read address (source address)
    end
  end

  // CHECK LOAD
  always_comb
  begin
    // default assignment
    result_load = 1'b0;
    // is a load instruction executed?
    // is the policy activated for this check?
    if ((opclass_i == DIFT_OPCLASS_LOAD) && (tccr_i.load == DIFT_CHECKMODE1_ON)) begin
      // apply check logic
      result_load = |operand_a_tag_i; // operand a holds the write address (desination address)
    end
  end


  assign trap_result = (result_exec | result_jalr | result_branch | result_store | result_load);

  // create trap type output signal
  always_comb
  begin
    // default assignment
    trap_type = DIFT_TRAP_TYPE_NONE;

    if (result_exec) begin
      trap_type = DIFT_TRAP_TYPE_EXEC;
    end else if (result_jalr) begin
      trap_type = DIFT_TRAP_TYPE_JALR;
    end else if (result_branch) begin
      trap_type = DIFT_TRAP_TYPE_BRAN;
    end else if (result_store) begin
      trap_type = DIFT_TRAP_TYPE_STOR;
    end else if (result_load) begin
      trap_type = DIFT_TRAP_TYPE_LOAD;
    end
  end


  // create tick from signal (in order to not retrigger the trap immediately)
  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_RESULT_FF
    if (rst_n == 1'b0) begin
      trap_result_q  = 1'b0;
    end
    else begin
      trap_result_q  = trap_result;
    end
  end

  always_comb
  begin
    if ((trap_result_q == 1'b0) && (trap_result == 1'b1)) begin
      trap_o      = trap_result;
      trap_type_o = trap_type;
    end
    else begin
      trap_o      = 1'b0;
      trap_type_o = DIFT_TRAP_TYPE_NONE;
    end
  end


endmodule
