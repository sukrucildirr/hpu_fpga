// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Instruction lookahead common definition
// ==============================================================================================

package instruction_scheduler_pkg;
  import regf_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;

//==================================================
// localparam
//==================================================
  // NB: PnR is tight with large pool_nb.
  // From experiment vivado is able to place 16 slot with ease but struggle with higher value.
  // The implementation spread the filtering on INNER_PIPE reduce the Pnr constraints
  // -> Filtering is done on INNER_PIPE stage
  // -> Update is done on INNER_PIPE stage
  // -> Ack/Idle stay on one cycle
  // A set of possible configuration: [64, 2p], [66s, 3p] ...
  localparam int POOL_SLOT_NB = 64;
  localparam int INNER_PIPE = 2;
  localparam int POOL_SLOT_W = $clog2(POOL_SLOT_NB) == 0 ? 1: $clog2(POOL_SLOT_NB);
  localparam int INNER_BATCH = POOL_SLOT_NB / INNER_PIPE;

  // Specify the minimum DOps within an IOp. It enable to size the width of sync_id counter
  // This parameters must be enforced by DOps stream generated by user and prevent sync_id overflow
  localparam int MIN_IOP_SIZE = 4;
  localparam int SYNC_ID_W = $clog2(POOL_SLOT_NB/MIN_IOP_SIZE) == 0 ? 1: $clog2(POOL_SLOT_NB/MIN_IOP_SIZE);

//==================================================
// Common Structure
//==================================================
  // Instruction kind encoded as one-hot
  typedef enum bit[4:0] {
    NULL_KIND = 5'b00000,
    MEM_LD = 5'b00001,
    MEM_ST = 5'b00010,
    ARITH  = 5'b00100,
    PBS    = 5'b01000,
    SYNC   = 5'b10000
  } insn_kind_e;
  localparam int INSN_KIND_W = $bits(insn_kind_e);

  // Use to notify request result
  typedef enum bit{
    FAILURE = 0,
    SUCCESS
  } isc_ack_status_e;

//==================================================
// Pool Structure
//==================================================
  // Instruction Rid/Mid
  // Used as src/dst identifier
  typedef enum bit[1:0] {
    UNUSED = 0,
    MEMORY,
    REGISTER
  } insn_mode_id_e;
  localparam int MAX_RID_MID= (RID_W <= CID_W)? CID_W: RID_W;

  typedef struct packed {
    insn_mode_id_e mode;
    logic [MAX_RID_MID-1: 0] id;
  } insn_id_t;
  localparam int INSN_ID_W = $bits(insn_id_t);

  typedef struct packed {
    insn_id_t isc;
    logic [MAX_RID_MID-1:0] mask;
  } dstn_id_t;
  localparam int DSTN_ID_W = $bits(dstn_id_t);


  // Instruction and extracted fields
  typedef struct packed {
    logic [PE_INST_W-1: 0]   raw_insn;
    logic [INSN_KIND_W-1: 0] kind; // Use raw logic to enable mh filtering
    dstn_id_t dst_id;
    insn_id_t srcA_id;
    insn_id_t srcB_id;
    logic     flush;
  } isc_insn_t;

  // Pool entry state
  typedef struct packed {
    // SyncId -> To which IOp this DOp belong
    logic [SYNC_ID_W-1: 0] sync_id;
    // RdLock -> #instruction before us that need to READ into our destination
    logic [POOL_SLOT_W: 0] rd_lock;
    // WrLock -> #instruction before us that need to Write into one of our sources
    logic [POOL_SLOT_W: 0] wr_lock;
    logic [POOL_SLOT_W: 0] issue_lock;
    logic                  vld;
    logic                  rd_pdg;
    logic                  pdg;
  } isc_pool_state_t;

  // Pool info
  // Used to keep track of instruction state and dependencies
  typedef struct packed {
    isc_insn_t insn;
    isc_pool_state_t state;
  } isc_pool_info_t;

  // Pool filter
  // Use to describe pool search filter
  typedef struct packed {
    // Match on slot state
    logic match_sync_id;
    logic match_vld;
    logic match_rd_pdg;
    logic match_pdg;
    logic match_lock_rdy; // i.e. RdLock == 0 && WrLock == 0 && IssueLock == 0

    // Match on instruction properties
    logic match_insn_kind;
    // Crossed match for lock_cnt extraction
    // req_info.dst == (pool_info.srcA || pool_info.srcB)
    logic match_dst_on_srcs;
    // (req_info.srcA || req_info.srcB) == pool_info.dst
    logic match_srcs_on_dst;
    // req_info.dst == pool_info.dst
    logic match_dst_on_dst;
    logic match_flush;
  } isc_pool_filter_t;

  // Pool update command
  // Describe if the update is from extern pool_info (i.e. refill)
  // or from filtered entries
  typedef enum bit[1:0] {
    POOL_UPDATE= 0,
    POOL_REFILL
  } isc_pool_cmd_e;

  // Pool update request
  // Use to describe pool update request
  typedef struct packed {
    // Update command
    isc_pool_cmd_e cmd;
    logic reorder;

    // Update slot state
    logic toggle_vld;
    logic toggle_rd_pdg;
    logic toggle_pdg;
    logic dec_rd_lock;
    logic dec_wr_lock;
    logic dec_issue_lock;
  } isc_pool_updt_t;

  // Pool request ack
  typedef struct packed {
    isc_ack_status_e       status;
    logic [POOL_SLOT_W: 0] nb_match;
    isc_pool_info_t        info;
  } isc_pool_ack_t;

//==================================================
// Query Structure
//==================================================
  // Query command
  typedef enum bit[2:0] {
    NONE = 0,
    RDUNLOCK,
    RETIRE,
    REFILL,
    ISSUE
  } isc_query_cmd_e;
  localparam int QUERY_CMD_W = $bits(isc_query_cmd_e);

  // Query request ack
  typedef struct packed {
    isc_ack_status_e       status;
    isc_query_cmd_e        cmd;
    isc_pool_info_t        info;
  } isc_query_ack_t;

  function automatic logic dest_within(input dstn_id_t dst, input insn_id_t src);
    return (dst.isc.mode == src.mode) &&
           (((dst.isc.id ^ src.id) & dst.mask) == MAX_RID_MID'(0));
  endfunction

  function automatic logic dest_within_dest(input dstn_id_t dst, input dstn_id_t other);
    logic [MAX_RID_MID-1:0] total_mask;
    total_mask = dst.mask & other.mask;
    return (dst.isc.mode == other.isc.mode) &&
           (((dst.isc.id ^ other.isc.id) & total_mask) == MAX_RID_MID'(0));
  endfunction
endpackage
