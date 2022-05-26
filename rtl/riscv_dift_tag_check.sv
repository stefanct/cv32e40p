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
    // tag data for BRANCH, LOAD, STORE checks
    input  dift_tag_t     operand_a_tag_i,
    input  dift_tag_t     operand_b_tag_i,
    input  dift_tag_t     operand_c_tag_i,
    // output: raising trap
    output logic          trap_o,
    output dift_trap_t    trap_type_o
);

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
    unique case (tccr_i.bran.single_mode_select)
      DIFT_CHECK_SINGLEMODESELECT_OP_A:   temp_result_b_single_mode = (|operand_a_tag_i);
      DIFT_CHECK_SINGLEMODESELECT_OP_B:   temp_result_b_single_mode = (|operand_b_tag_i);
    endcase

    // apply check logic depending on configured check policy
    unique case (tccr_i.bran.mode)
      DIFT_CHECKMODE2_OFF:    result_branch = 1'b0;
      DIFT_CHECKMODE2_OR:     result_branch = (|operand_a_tag_i) | (|operand_b_tag_i);
      DIFT_CHECKMODE2_AND:    result_branch = (|operand_a_tag_i) & (|operand_b_tag_i);
      DIFT_CHECKMODE2_SINGL:  result_branch = temp_result_b_single_mode;
    endcase
  end


  // Check Type MUX: apply (select) the check type that matches the current instruction class
  logic       trap_int;
  dift_trap_t trap_type_int;

  always_comb
  begin
    // default assignment (no trap)
    trap_int      = '0;
    trap_type_int = '0;

    if (~branch_taken_ex_i)
    begin
      // EXEC CHECK overrules all other CHECKs (if it is triggered)
      if (result_exec)
      begin
        trap_int      = result_exec;
        trap_type_int = DIFT_TRAP_TYPE_EXEC;  // 0x0
      end
      // all other CHECKs
      else
      begin
        case (opclass_i)
          DIFT_CHECK_OPCLASS_JALR:  // 0x3
          begin
            trap_int      = result_jalr;
            trap_type_int = DIFT_TRAP_TYPE_JALR;
          end

          DIFT_CHECK_OPCLASS_BRAN:  // 0x4
          begin
            trap_int      = result_branch;
            trap_type_int = DIFT_TRAP_TYPE_BRAN;
          end
        endcase
      end
    end
  end


  logic trap_int_q;

  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_OUTPUT_FF
    if (rst_n == 1'b0) begin
      trap_o     <= '0;
      trap_int_q <= '0;
    end
    else begin
      trap_int_q <= trap_int;

      // deassert raising of trap
      if ((~trap_int_q) && (is_decoding_i)) begin
        trap_o      <= trap_int;
        trap_type_o <= trap_type_int;
      end else begin
        trap_o      <= '0;
        trap_type_o <= '0;
      end
    end
  end



/*
  // output a tick instead of a constant signal (to avoid retriggering the trap again and again)
  logic deassert;

  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_TICK_GEN
    if (rst_n == 1'b0) begin
      deassert <= '0;
    end
    else begin
      // deassert raising of trap
      if ((~is_decoding_i) || (trap_o)) begin
        deassert <= 1'b1;
      end else begin
        deassert <= 1'b0;
      end
    end
  end

  always_comb
  begin
    // did we trigger the trap last cycle? then we have to unset it now
    if (deassert) begin
      trap_o      = '0;
      trap_type_o = '0;
    end else begin
      trap_o      = trap_int;
      trap_type_o = trap_type_int;
    end
  end

*/

endmodule





module dift_tag_check_lsu
(
    input  logic          clk,
    input  logic          rst_n,

    // configuration
    input  dift_tccr_t    tccr_i,
    // info about executing instruction (which check logic has to be applied)
    input  dift_check_opclass_t  opclass_i,   // which basic opclass
    input  logic          is_decoding_i,      // indicates if the decoded instruction (provided by ID/EX) is actually executed (valid)
    // operands' tag bits
    input  dift_tag_t     operand_a_tag_i, // base address tags
    input  dift_tag_t     operand_b_tag_i, // address offset tags
    input  dift_tag_t     operand_c_tag_i, // value tags
    // output: raising trap
    output logic          trap_o,
    output dift_trap_t    trap_type_o
);
  logic       is_decoding_q;
  logic       trap_int;
  dift_trap_t trap_type_int;

  // delay is_decoding signal by 1 cycle
  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_TICK_GEN
    if (rst_n == 1'b0) begin
      is_decoding_q <= '0;
    end
    else begin
      is_decoding_q <= is_decoding_i;
    end
  end

  // CHECK
  always_comb
  begin
    // default assignment
    trap_int      = '0;
    trap_type_int = '0;

    // STORE instruction and check policy activated?
    if ((opclass_i == DIFT_CHECK_OPCLASS_STOR) && (tccr_i.stor == DIFT_CHECKMODE1_ON)) begin
      // apply check logic
      trap_int      = |operand_a_tag_i;  // operand a holds the write address (destination address)
      trap_type_int = DIFT_TRAP_TYPE_STOR;
    end

    // LOAD instruction and check policy activated?
    if ((opclass_i == DIFT_CHECK_OPCLASS_LOAD) && (tccr_i.load == DIFT_CHECKMODE1_ON)) begin
      // apply check logic
      trap_int      = |operand_a_tag_i;  // operand a holds the read address (source address)
      trap_type_int = DIFT_TRAP_TYPE_LOAD;
    end
  end


  logic trap_int_q;

  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_OUTPUT_FF
    if (rst_n == 1'b0) begin
      trap_o     <= '0;
      trap_int_q <= '0;
    end
    else begin
      trap_int_q <= trap_int;

      // deassert raising of trap
      //if (trap_int_q | ~is_decoding_i) begin
      if (trap_int_q) begin
        trap_o      <= '0;
        trap_type_o <= '0;
      end else begin
        trap_o      <= trap_int;
        trap_type_o <= trap_type_int;
      end
    end
  end


/*
  // output a tick instead of a constant signal (to avoid retriggering the trap again and again)
  logic deassert;

  always_ff @(posedge clk , negedge rst_n)
  begin : TRAP_TICK_GEN
    if (rst_n == 1'b0) begin
      deassert <= '0;
    end
    else begin
      // deassert raising of trap
      if ((~is_decoding_i) || (trap_o)) begin
        deassert <= 1'b1;
      end else begin
        deassert <= 1'b0;
      end
    end
  end

  always_comb
  begin
    // did we trigger the trap last cycle? then we have to unset it now
    if (deassert) begin
      trap_o      = '0;
      trap_type_o = '0;
    end else begin
      trap_o      = trap_int;
      trap_type_o = trap_type_int;
    end
  end
*/


endmodule
