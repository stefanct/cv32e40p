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

    // configuration
    input  dift_tccr_t    tccr_i,
    // info about executing instruction (which check logic has to be applied)
    input  dift_opclass_t opclass_i,          // which basic opclass
    input  logic          is_decoding_i,      // indicates if the decoded instruction (provided by ID/EX) is actually executed (valid)
    //input  logic          branch_decision_i,  // whether or not a branch is taken
    input  logic [1:0]    jump_in_i,          // wonly for JALR check: which type of jump is executed? (JAL or JALR)
    // tag data for EXEC check
    input  dift_tag_t     instr_rtag_i,
    // tag data for JALR check
    input  dift_tag_t     jump_target_tag_i,
    // tag data for BRANCH, LOAD, STORE checks
    input  dift_tag_t     operand_a_tag_i,
    input  dift_tag_t     operand_b_tag_i,
    input  dift_tag_t     operand_c_tag_i,
    // output: raising trap
    output logic          trap_o,
    output dift_trap_t    trap_type_o

/*
    // jump indicator (if any occurs and also which type of jump/branch) decoded in ID
    input  logic [1:0]     jump_in_i,          // for jump/branch instructions

    // type of instruction, provided by ID/EX pipeline 
    input  logic          id_valid_i,         // checks if instruction in ID/EX will be executed next cylce or not
    input  logic          branch_in_ex_i,
    input  logic          branch_decision_i,
*/
);

  // we need to delay the is_decoding signal for 1 cycle, so that it fits to the other pipelined signals
  logic is_decoding_q;
  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_RESULT_FF
    if (rst_n == 1'b0) begin
      is_decoding_q <= 1'b0;
    end
    else begin
      is_decoding_q <= is_decoding_i;
    end
  end

  // signals for each check type (per opclass)
  logic result_exec;
  logic result_jalr;
  logic result_branch;
  logic temp_result_b_single_mode;
  logic result_store;
  logic result_load;

  // CHECK EXECUTION
  always_comb
  begin
    // default assignment
    result_exec = 1'b0;
    // is the policy activated for this check?
    if (tccr_i.exec == DIFT_CHECKMODE1_ON) begin
      // apply check logic
      result_exec = |instr_rtag_i;
    end
  end

  // CHECK JALR
  always_comb
  begin
    // default assignment
    result_jalr = 1'b0;
    // is the policy activated for this check?
    if (tccr_i.jalr == DIFT_CHECKMODE1_ON) begin
      // apply check logic
      result_jalr = |jump_target_tag_i;
    end
  end

  // CHECK BRANCH
  always_comb
  begin
    // default assignment
    result_branch = 1'b0;
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

  // CHECK STORE
  always_comb
  begin
    // default assignment
    result_store = 1'b0;
    // is the policy activated for this check?
    if (tccr_i.store == DIFT_CHECKMODE1_ON) begin
      // apply check logic
      result_store = |operand_a_tag_i;  // operand a holds the read address (source address)
    end
  end

  // CHECK LOAD
  always_comb
  begin
    // default assignment
    result_load = 1'b0;
    // is the policy activated for this check?
    if (tccr_i.load == DIFT_CHECKMODE1_ON) begin
      // apply check logic
      result_load = |operand_a_tag_i; // operand a holds the write address (desination address)
    end
  end

  // result MUX: use the result from the check type that matches the current instruction class
  always_comb
  begin
    // default assignment (no trap)
    trap_o      = '0;
    trap_type_o = DIFT_TRAP_TYPE_NONE;
    
    // only apply check if the provided instruction from ID/EX is also executed (processor "is_decoding")
    //  (is_decoding is not set, if a branch is executed -> the next instruction, which was already 
    //   decoded by ID is never executed as we execute a branch -> the check must not be applied)
    if (is_decoding_q)
    begin
      // EXEC CHECK overrules all other CHECKs (if it is triggered)
      if (result_exec)
      begin
        trap_o      = result_exec;
        trap_type_o = DIFT_TRAP_TYPE_EXEC; 
      end
      // all other CHECKs
      else
      begin
        case (opclass_i)
          DIFT_OPCLASS_JUMP:
          begin
            // only for JALR instructions (but not for JAL)
            if (jump_in_i == BRANCH_JALR)
            begin
              trap_o      = result_jalr;
              trap_type_o = DIFT_TRAP_TYPE_JALR;
            end
          end
          
          DIFT_OPCLASS_BRANCH:
          begin
            trap_o      = result_branch;
            trap_type_o = DIFT_TRAP_TYPE_BRAN;
          end
          
          DIFT_OPCLASS_STORE:
          begin
            trap_o      = result_store;
            trap_type_o = DIFT_TRAP_TYPE_STOR;
          end
          
          DIFT_OPCLASS_LOAD:
          begin
            trap_o      = result_load;
            trap_type_o = DIFT_TRAP_TYPE_LOAD;
          end
        endcase
      end
    end
  end

endmodule
