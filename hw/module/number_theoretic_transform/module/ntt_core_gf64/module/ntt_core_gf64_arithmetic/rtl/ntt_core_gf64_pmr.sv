// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a partial modular reduction on a 2s complement value in
//                goldilocks 64 field. The result is a 2s complement over MOD_NTT_W+2 bits.
// ----------------------------------------------------------------------------------------------
//
// Performs a partial modular reduction on a 2s complement, and output a 2s complement value with
// MOD_NTT_W+2 bits.
//
// GF64 prime is a solinas2 with this form :
// 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1
// with MOD_NTT_W an even number.
//
// The following properties are used here :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
// 2**(MOD_NTT_W+MOD_NTT_W/2) = -1
//
// Definition of 2s complement representation:
// v[W:0] in 2s complement
// In Z, its value is : -2^W + v[W-1:0]
//
// Then the reduction of all the bits above MOD_NTT_W is done using the properties above.
// The result is a 2s complement number with MOD_NTT_W + 1 bit + 1 sign bit.
//
// Note that the inputs are 2s complement numbers.
//
// This is a smaller version than ntt_core_gf64_pmr_reduction, since it accepts only up to
// MOD_NTT_W + MID_W bits as input. It also accepts 2s complement input.
// ==============================================================================================

module ntt_core_gf64_pmr #(
  parameter int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // Should be even
  parameter int            OP_W      = MOD_NTT_W + 2 + 1, // 2 additional bits + 1bit of sign. Data are in 2s complement.
  parameter bit            IN_PIPE   = 1'b1, // Recommended
  parameter int            SIDE_W    = 0, // Side data size. Set to 0 if not used
  parameter [1:0]          RST_SIDE  = 0  // If side data is used,
                                          // [0] (1) reset them to 0.
                                          // [1] (1) reset them to 1.
) (
  // System interface
  input  logic                 clk,
  input  logic                 s_rst_n,

  // Data interface
  input  logic [OP_W-1:0]      a, // 2s complement
  output logic [MOD_NTT_W+1:0] z, // 2s complement

  // Control + side interface - optional
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);
// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int MID_W      = MOD_NTT_W / 2;
  localparam int C_W        = OP_W-1-MOD_NTT_W;

  generate
    if ((MOD_NTT_W % 2) != 0) begin : __UNSUPPORTED_MOD_NTT_W
      $fatal(1,"> ERROR: MOD_NTT_W (%0d) should be even!", MOD_NTT_W);
    end
    if (C_W < 1) begin : __UNSUPPORTED_OP_W_0
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at least MOD_NTT_W+2 bits (%0d). Here only OP_W=%0d was connected.",MOD_NTT_W + 2, OP_W);
    end
    if (OP_W > MOD_NTT_W + MID_W) begin : __UNSUPPORTED_OP_W_1
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at most MOD_NTT_W+MOD_NTT_W/2 bits (%0d). Here OP_W=%0d was connected.",MOD_NTT_W + MOD_NTT_W/2, OP_W);
    end
    // Simplifications have been made in the code
    if (OP_W <= MOD_NTT_W) begin : __UNSUPPORTED_OP_W_2
      $fatal(1,"> ERROR: OP_W (%0d) should be greater than MOD_NTT_W (%0d)", OP_W, MOD_NTT_W);
    end
  endgenerate

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic [OP_W-1:0]   s0_a;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;
  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_a <= a;
      end
    end else begin : no_gen_input_pipe
      assign s0_a = a;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

// ============================================================================================== //
// s0
// ============================================================================================== //
// Use the following property for the partial reduction :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
// 2**(MOD_NTT_W+MOD_NTT_W/2) = -1

  logic [MOD_NTT_W+1:0] s0_z;
  logic                 s0_sign;
  logic [C_W-1:0]       s0_carry;

  assign s0_sign  = s0_a[OP_W-1];
  assign s0_carry = s0_a[MOD_NTT_W+:C_W];

  assign s0_z = s0_a[MOD_NTT_W-1:0]
                - s0_carry
                + {s0_carry,{MID_W{1'b0}}}
                + {s0_sign, {C_W{1'b0}}}
                - {s0_sign, {C_W + MID_W{1'b0}}};

// ============================================================================================== //
// s1 : Output pipe
// ============================================================================================== //
// Output pipe
  logic [MOD_NTT_W+1:0] s1_z;
  logic                 s1_avail;
  logic [SIDE_W-1:0]    s1_side;

  always_ff @(posedge clk) begin
    s1_z <= s0_z;
  end

  common_lib_delay_side #(
    .LATENCY    (1),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s0_avail ),
    .out_avail(s1_avail ),

    .in_side  (s0_side  ),
    .out_side (s1_side  )
  );

  assign z         = s1_z;
  assign out_avail = s1_avail;
  assign out_side  = s1_side;

endmodule
