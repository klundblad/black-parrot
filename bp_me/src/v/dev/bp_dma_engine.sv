/**
 *
 * Name:
 *   bp_dma_engine.sv
 *
 * Description: This is a Direct Memory Access Engine that currently
 * instantiates bsg_tdma_decode_csr.v CSR's and connects to the BP
 * Unicore Bedrock Register to connect a client node to a control
 * node
 *
 */

`include "bp_common_defines.svh"
`include "bp_me_defines.svh"
`include "bsg_cache.vh"
`include "bsg_noc_links.vh"

// from dma
`include "bp_top_defines.svh"

`include "/mnt/users/ssd2/homes/klundb/bsg_ml_atoms/vsrc/tdma/bsg_tdma_decode_csr.v"

module bp_dma_engine
 import bsg_wormhole_router_pkg::*;
 import bp_be_pkg::*;
 import bp_common_pkg::*;
 import bp_me_pkg::*;
 import bsg_noc_pkg::*;
 import bsg_cache_pkg::*;
 import bp_top_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
  `declare_bp_proc_params(bp_params_p)
  `declare_bp_bedrock_mem_if_widths(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p)
    // bsg_tdma_decode_csr.v
   , parameter cmd_addr_width_p = 32
   , parameter cmd_data_width_p = 64

   , parameter addr_width_p = 32
   , parameter data_width_p = 32 // size of dword_width_gp in bp_unicore top is 64, in csr rmt width is 32

   , parameter stride_width_p = 32
   , parameter count_width_p  = 32
   , parameter rank_p         = 1
   , parameter bedrock_fill_width_p = 64 // added for uce

  // data that that
   , parameter dma_width_gp = 64 // the width of dma data
   , parameter dma_assoc_p = 2 // 2 set associative? cache is not being affected
   , parameter dma_sets_p = 2 // 2 sets?
   , parameter dma_fill_width_p = 64 // 64 bit width of the dma to match the address
   , parameter dma_ctag_width_p = 64
   , parameter dma_block_width_p = 64

  //  .cmd_addr_width_p(5)
  //       ,.cmd_data_width_p(32)
  //       ,.rmt_addr_width_p(32)
  //       ,.loc_addr_width_p(28)
  //       ,.data_width_p(32)
    
  //       ,.stride_width_p(32)
  //       ,.count_width_p (32)
  //       ,.rank_p(4)


   )
   // bp_me_cfg_slice exposed module top
  (  input                                               clk_i
   , input                                               reset_i

   , input  [mem_fwd_header_width_lp-1:0]                mem_fwd_header_i
   , input  [cmd_data_width_p-1:0]                       mem_fwd_data_i      // used to be [cmd_data_width_p-1:0] 
   , input                                               mem_fwd_v_i
   , output logic                                        mem_fwd_ready_and_o
   , input                                               mem_fwd_last_i

   , output logic [mem_rev_header_width_lp-1:0]          mem_rev_header_o
   , output logic [cmd_data_width_p-1:0]                 mem_rev_data_o      // used to be [cmd_data_width_p-1:0] 
   , output logic                                        mem_rev_v_o
   , input                                               mem_rev_ready_and_i 
   , output logic                                        mem_rev_last_o
   
   

   );

  logic lce_id_li; // UCE input logic
  localparam reg_els_lp = 1;
  
  logic [addr_width_p-1:0] rd_base_addr_lo, wr_base_addr_lo;
  // bsg_tdma_sequencer exposed module top
  logic [cmd_addr_width_p-1:0]                 cmd_addr_i; // command address for csr (size is -1?) // used to be cmd_addr_width_p-1
  logic [cmd_data_width_p-1:0]                 cmd_data_i; // command datat for csr
  logic [reg_els_lp-1:0]                       cmd_v_i;    // command valid in for csr

  logic [addr_width_p-1:0]                     wr_base_addr_o;
  logic [stride_width_p-1:0]                   wr_stride_o;
  logic [count_width_p-1:0]                    wr_count_o;

  // temp logic for rd
  logic [addr_width_p-1:0]                     rd_base_addr_o;
  logic [stride_width_p-1:0]                   rd_stride_o;
  logic [count_width_p-1:0]                    rd_count_o;
  
  
  
  //`bp_cast_o(bp_dcache_req_s, cache_req);
  logic temp_ready_and_o; 
  // using valid and ready handshake
  bsg_fifo_1r1w_small
   #(.width_p(1+mem_fwd_header_width_lp), // size of control data, used to be $bits(bp_bedrock_mem_fwd_header_s)
     .els_p(64))
   read_request_fifo
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i({68'b0}) // csr data or actual data? tag data, cmd and stat, oroginally mem_fwd_data_i
     ,.v_i(mem_fwd_v_i)
     ,.ready_o(temp_ready_and_o)

     ,.data_o({temp_data_o}) // output data? connected to bp uce data_i, used to be _mem_rev_data_i
     ,.v_o(temp_mem_rev_v_o) // 
     ,.yumi_i(temp_mem_rev_v_o) // lce_fill_header_ready_and_i & lce_fill_header_v_o, used to be mem_rev_ready_and_i & mem_rev_v_o
     );
  
  assign temp_mem_rev_v_o = mem_rev_v_o; 

  `declare_bp_cfg_bus_s(vaddr_width_p, hio_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p);
  `declare_bp_cache_engine_if(paddr_width_p, dcache_ctag_width_p, dcache_sets_p, dcache_assoc_p, dword_width_gp, dcache_block_width_p, dcache_fill_width_p, dcache);
  `declare_bp_cache_engine_if(paddr_width_p, icache_ctag_width_p, icache_sets_p, icache_assoc_p, dword_width_gp, icache_block_width_p, icache_fill_width_p, icache);
  `declare_bp_bedrock_mem_if(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p);
  //`bp_cast_i(bp_cfg_bus_s, cfg_bus);
  
  // pulled from unicore_lite
  // bp_dcache_req_s dcache_req_lo;
  logic dcache_req_v_lo, dcache_req_ready_and_li, dcache_req_busy_li, dcache_req_metadata_v_lo;
  bp_dcache_req_metadata_s dcache_req_metadata_lo;
  logic dcache_req_critical_tag_li, dcache_req_critical_data_li, dcache_req_complete_li;
  logic dcache_req_credits_full_li, dcache_req_credits_empty_li;

  bp_dcache_tag_mem_pkt_s dcache_tag_mem_pkt_li;
  logic dcache_tag_mem_pkt_v_li, dcache_tag_mem_pkt_yumi_lo;
  bp_dcache_tag_info_s dcache_tag_mem_lo;
  bp_dcache_data_mem_pkt_s dcache_data_mem_pkt_li;
  logic dcache_data_mem_pkt_v_li, dcache_data_mem_pkt_yumi_lo;
  logic [dcache_block_width_p-1:0] dcache_data_mem_lo;
  bp_dcache_stat_mem_pkt_s dcache_stat_mem_pkt_li;
  logic dcache_stat_mem_pkt_v_li, dcache_stat_mem_pkt_yumi_lo;
  bp_dcache_stat_info_s dcache_stat_mem_lo;

  bp_bedrock_mem_fwd_header_s [1:1] _mem_fwd_header_o;
  logic [1:1][bedrock_fill_width_p-1:0] _mem_fwd_data_o;
  logic [1:1] _mem_fwd_v_o, _mem_fwd_ready_and_i;
  bp_bedrock_mem_rev_header_s [1:1] _mem_rev_header_i;
  logic [1:1][bedrock_fill_width_p-1:0] _mem_rev_data_i;
  logic [1:1] _mem_rev_v_i, _mem_rev_ready_and_o;

  // signals for dcache not declared
  logic dcache_req_lo, cache_req_cast_o;
  
  // uce cache module logic
  logic dma_req_v_lo, dma_req_ready_and_li, dma_req_busy_li,
        dma_req_metadata_v_lo, dma_req_critical_tag_li, dma_req_critical_data_li, dma_req_complete_li,
        dma_req_credits_full_li, dma_req_credits_empty_li;
  
  // uce cache module logic
  logic dma_tag_mem_pkt_v_li, dma_tag_mem_pkt_yumi_lo; 

  // // uce data module logic
  logic dma_data_mem_pkt_v_li, dma_data_mem_pkt_yumi_lo, dma_data_mem_lo;

  // // uce stat module logic
  logic dma_stat_mem_pkt_v_li, dma_stat_mem_pkt_yumi_lo;
  
  logic [115:0] dma_req_lo;
  logic [1:0] dma_req_metadata_lo; //
  logic [71:0] dma_tag_mem_pkt_li;
  logic [66:0] dma_tag_mem_lo;
  logic [68:0] dma_data_mem_pkt_li;
  logic [63:0] dma_data_mem_lo;
  logic [3:0] dma_stat_mem_pkt_li;
  //logic [2:0] dma_stat_mem_lo;
  logic [66:0] temp_mem_rev_header_o, temp_mem_fwd_header_i; 
  logic [63:0] temp_mem_fwd_data_i; // temp_mem_rev_data_o, 
 
  bp_uce
   #(.bp_params_p(bp_params_p)
     ,.assoc_p(2) // dma_assoc_p
     ,.sets_p(2) // dma_sets_p
     ,.block_width_p(64) // dma_block_width_p 
     ,.fill_width_p(uce_fill_width_p)
     ,.ctag_width_p(64) // dma_ctag_width_p
     ,.writeback_p(2) // dma_features_p[e_cfg_writeback]
     ,.metadata_latency_p(1)
     )
   dma_uce
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.lce_id_i(4'b1)

     ,.cache_req_i(dma_req_lo)                                                // was dma_req_lo
     ,.cache_req_v_i(dma_req_v_lo)                                        // dma_req_v_lo
     ,.cache_req_ready_and_o(dma_req_ready_and_li)                        // dma_req_ready_and_li
     ,.cache_req_busy_o(dma_req_busy_li)                                  // dma_req_busy_li
     ,.cache_req_metadata_i(dma_req_metadata_lo)                          // dma_req_metadata_lo
     ,.cache_req_metadata_v_i(dma_req_metadata_v_lo)                      // dma_req_metadata_v_lo
     ,.cache_req_critical_tag_o(dma_req_critical_tag_li)                  // dma_req_critical_tag_li
     ,.cache_req_critical_data_o(dma_req_critical_data_li)                // dma_req_critical_data_li
     ,.cache_req_complete_o(dma_req_complete_li)                          // dma_req_complete_li
     ,.cache_req_credits_full_o(dma_req_credits_full_li)                  // dma_req_credits_full_li
     ,.cache_req_credits_empty_o(dma_req_credits_empty_li)                // dma_req_credits_empty_li

     ,.tag_mem_pkt_o(dma_tag_mem_pkt_li)            // dma_tag_mem_pkt_li
     ,.tag_mem_pkt_v_o(dma_tag_mem_pkt_v_li)        // dma_tag_mem_pkt_v_li
     ,.tag_mem_pkt_yumi_i(dma_tag_mem_pkt_yumi_lo)  // dma_tag_mem_pkt_yumi_lo
     ,.tag_mem_i(dma_tag_mem_lo)                    // dma_tag_mem_lo

     ,.data_mem_pkt_o(dma_data_mem_pkt_li)           // dma_data_mem_pkt_li
     ,.data_mem_pkt_v_o(dma_data_mem_pkt_v_li)       // dma_data_mem_pkt_v_li
     ,.data_mem_pkt_yumi_i(dma_data_mem_pkt_yumi_lo) // dma_data_mem_pkt_yumi_lo
     ,.data_mem_i(dma_data_mem_lo)                   // dma_data_mem_lo

     ,.stat_mem_pkt_o(dma_stat_mem_pkt_li)           // dma_stat_mem_pkt_li
     ,.stat_mem_pkt_v_o(dma_stat_mem_pkt_v_li)       // dma_stat_mem_pkt_v_li
     ,.stat_mem_pkt_yumi_i(dma_stat_mem_pkt_yumi_lo) // dma_stat_mem_pkt_yumi_lo
     ,.stat_mem_i(dma_stat_mem_lo)                   // dma_stat_mem_lo

     ,.mem_fwd_header_o(mem_fwd_header_o)       // fwd linked to rev signals?
     ,.mem_fwd_data_o(temp_mem_rev_data_o)           
     ,.mem_fwd_v_o(temp_mem_rev_v_o)                 // mem forward valid and out, used to be _mem_fwd_v_o
     ,.mem_fwd_ready_and_i(temp_mem_rev_ready_and_i)
     ,.mem_fwd_last_o(temp_mem_rev_last_o)

     ,.mem_rev_header_i(temp_mem_fwd_header_i)
     ,.mem_rev_data_i(temp_mem_fwd_data_i)           // connected to the data_o of the fifo
     ,.mem_rev_v_i(temp_mem_fwd_v_i)
     ,.mem_rev_ready_and_o(temp_mem_fwd_ready_and_o)    // used to be mem_fwd_ready_and_o
     ,.mem_rev_last_i(temp_mem_fwd_last_i)
     );
  
  logic [66:0] mem_fwd_header_o; 
  logic temp_mem_rev_header_o, temp_mem_rev_v_o, temp_mem_rev_ready_and_i, temp_mem_rev_last_o,
        temp_mem_fwd_header_i, temp_mem_fwd_data_i, temp_mem_fwd_v_i, temp_mem_fwd_ready_and_o, temp_mem_fwd_last_i; 

  assign temp_mem_rev_header_o = mem_rev_header_o;
  assign temp_mem_rev_data_o = mem_rev_data_o;
  assign temp_mem_rev_v_o = mem_rev_v_o; 
  assign temp_mem_rev_ready_and_i = mem_rev_ready_and_i; 
  assign temp_mem_rev_last_o = mem_rev_last_o; 
  assign temp_mem_fwd_header_i = mem_fwd_header_i; 
  assign temp_mem_fwd_data_i = mem_fwd_data_i; 
  assign temp_mem_fwd_v_i = mem_fwd_v_i; 
  assign temp_mem_fwd_ready_and_o = mem_fwd_ready_and_o; 
  assign temp_mem_fwd_last_i = mem_fwd_last_i; 

  // Control Status Register
  // CSR will take signals from the Bedrock Register and
  // write to an address that will execute a command
  bsg_tdma_decode_csr #
    (.cmd_addr_width_p(cmd_addr_width_p) // command address wdith
    ,.cmd_data_width_p(cmd_data_width_p)
    ,.base_addr_width_p(addr_width_p)
    ,.stride_width_p(stride_width_p)
    ,.count_width_p(count_width_p)
    ,.rank_p(rank_p))
  csr_bank
    (.clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.addr_i(cmd_addr_i)
    ,.data_i(cmd_data_i)
    ,.v_i(cmd_v_i)      // 1 bit port

    ,.start_o(start_lo)
    // we only support writes
    ,.rd_base_addr_r_o(rd_base_addr_o)     // not connected
    ,.rd_stride_r_o(rd_stride_o)
    ,.rd_count_r_o(rd_count_o)

    ,.wr_base_addr_r_o(wr_base_addr_lo)
    ,.wr_stride_r_o(wr_stride_o)           // 32 bits
    ,.wr_count_r_o(wr_count_o)             // 32 bits
    );

  // pulled from bsg_tdma_decode_csr.v
  `bp_cast_o(bp_cfg_bus_s, cfg_bus);

  `declare_bp_cache_engine_if(paddr_width_p, dma_ctag_width_p, dma_sets_p, dma_assoc_p, dma_width_gp, dma_block_width_p, dma_fill_width_p, dma);
 
  logic r_v_o; 
  // this is the config register
  // Bedrock Register will take signals from the crossbar (ie. mem_*) and
  // feed data into the CSR
  bp_me_bedrock_register
   #(
     .bp_params_p(bp_params_p) 
     ,.els_p(reg_els_lp)                  // the number of registers?
     ,.reg_addr_width_p(cmd_addr_width_p) // command address width from the cmd address width in CSR
     ,.base_addr_p(dma_dev_base_addr_gp)                      // base address for the writes
     )

   register
    (.*                                  // mem values which is connected to the crossbar, instantiated in module head
     ,.r_v_o(r_v_o)                      // A bunch of read enables (CSR only supports writes)
     ,.w_v_o(cmd_v_i)                    // A bunch of write enables, one for each register (write valid out goes to CSR?)
     ,.addr_o(cmd_addr_i) 
     ,.size_o()                          // register width, can vary from 0 to register width
     ,.data_o(cmd_data_i)
     ,.data_i(64'b0)                     // we are not writing in the csr, so tie to 0
     );

  



endmodule // bsg_dma_engine
