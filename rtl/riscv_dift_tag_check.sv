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
    input  dift_check_opclass_t  opclass_i,   // which basic opclass
    input  logic          is_decoding_i,      // indicates if the decoded instruction (provided by ID/EX) is actually valid (will be executed)
    input  logic          branch_taken_ex_i,  // indicates if the decoded instruction (provided by ID/EX) is actually valid (will be executed)
    // tag data for EXEC check
    input  dift_tag_t     instr_rtag_i,
    // tag data for JALR check
    input  dift_tag_t     jump_target_tag_i,
    // tag data for STORE, LOAD, BRANCH checks
    input  dift_tag_t     operand_a_tag_i,
    input  dift_tag_t     operand_b_tag_i,
    // output: raising trap
    output logic          trap_o,
    output dift_trap_t    trap_type_o
);

  // signals for each check type (per opclass)
  logic result_exec;
  logic result_stor;
  logic result_load;
  logic result_jalr;
  logic result_bran;
  logic result_bran_single_mode;

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

  // CHECK STORE
  always_comb
  begin
    // default assignment
    result_stor = 1'b0;
    // is the policy activated for this check?
    if (tccr_i.stor == DIFT_CHECKMODE1_ON) begin
      // apply check logic
      result_stor = (|operand_a_tag_i) | (|operand_b_tag_i);
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
      result_load = (|operand_a_tag_i) | (|operand_b_tag_i);
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
    result_bran = 1'b0;
    // apply check logic for single-mode (only checking one operand of the branch decision expression)
    unique case (tccr_i.bran.single_mode_select)
      DIFT_CHECK_SINGLEMODESELECT_OP_A:   result_bran_single_mode = (|operand_a_tag_i);
      DIFT_CHECK_SINGLEMODESELECT_OP_B:   result_bran_single_mode = (|operand_b_tag_i);
    endcase

    // apply check logic depending on configured check policy
    unique case (tccr_i.bran.mode)
      DIFT_CHECKMODE2_OFF:    result_bran = 1'b0;
      DIFT_CHECKMODE2_OR:     result_bran = (|operand_a_tag_i) | (|operand_b_tag_i);
      DIFT_CHECKMODE2_AND:    result_bran = (|operand_a_tag_i) & (|operand_b_tag_i);
      DIFT_CHECKMODE2_SINGL:  result_bran = result_bran_single_mode;
    endcase
  end


  // Check Type MUX: apply (select) the check type that matches the current instruction class
  logic       trap_sel;
  dift_trap_t trap_type_sel;

  always_comb
  begin
    // default assignment (no trap) -> if a opclass is decoded that has no checking
    trap_sel      = '0;
    trap_type_sel = '0;

    // EXEC CHECK overrules all other CHECKs (if it is triggered)
    if (result_exec)
    begin
      trap_sel      = result_exec;
      trap_type_sel = DIFT_TRAP_TYPE_EXEC;  // 0x0
    end
    // all other CHECKs
    else begin
      case (opclass_i)
        DIFT_CHECK_OPCLASS_STOR:  // 0x1
        begin
          trap_sel      = result_stor;
          trap_type_sel = DIFT_TRAP_TYPE_STOR;
        end

        DIFT_CHECK_OPCLASS_LOAD:  // 0x2
        begin
          trap_sel      = result_load;
          trap_type_sel = DIFT_TRAP_TYPE_LOAD;
        end

        DIFT_CHECK_OPCLASS_JALR:  // 0x3
        begin
          trap_sel      = result_jalr;
          trap_type_sel = DIFT_TRAP_TYPE_JALR;
        end

        DIFT_CHECK_OPCLASS_BRAN:  // 0x4
        begin
          trap_sel      = result_bran;
          trap_type_sel = DIFT_TRAP_TYPE_BRAN;
        end
      endcase
    end
  end


  // Deassert selected trap signal to generate internal trap signal
  //   if a branch is taken in ex stage the currently decoded instruction will NOT be executed
  //   if is_decoding is low, whatever we decoded is garbage (e.g. because of interrupts, mem traps, ...)
  logic trap_int;
  dift_trap_t trap_type_int;

  always_comb
  begin
    if ((branch_taken_ex_i) | (~is_decoding_i))
    begin
      trap_int      = '0;
      trap_type_int = '0;
    end
    else begin
      trap_int      = trap_sel;
      trap_type_int = trap_type_sel;
    end
  end


  // FF for internal trap signal
  //   save the previous trap_int signal to be able to perform the tick generation below
  logic trap_int_q;

  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_INT_FF
    if (rst_n == 1'b0) begin
      trap_int_q <= '0;
    end
    else begin
      trap_int_q <= trap_int;
    end
  end


  // Tick Creation: produce only a tick as output signal
  //   instead of a permanent signal, which would trigger the trap over and over again,
  //   and the trap handler would actually never be executed
  logic trap;
  dift_trap_t trap_type;

  always_comb
  begin
    if (~trap_int_q) begin
      trap      = trap_int;
      trap_type = trap_type_int;
    end
    else begin
      trap      = '0;
      trap_type = '0;
    end
  end


  // Output FF
  //   we have to decouple the trap generation with a flip-flop, because we rely on the
  //   is_decoding_i signal from the controller for generating our internal trap signal
  //   however, the is_decoding_i signal depends on the trap signal we provide to the
  //   controller => so we have to dely the trap creation by 1 cycle here
  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_OUTPUT_FF
    if (rst_n == 1'b0) begin
      trap_o      <= '0;
      trap_type_o <= '0;
    end
    else begin
      trap_o      <= trap;
      trap_type_o <= trap_type;
    end
  end


endmodule
