`include "pcie_pkg.sv"   // 临时兜底，确保 pcie_pkg 先被定义
interface pcie_if #(parameter ADDR_W=32, DATA_W=32, LEN_W=10) (input logic clk, rst_n);//#( … )：参数列表，用来参数化接口里信号的位宽等。( … )：端口列表，把外部的 clk、rst_n 传进 interface，供里面的 SVA、covergroup 和任务使用

  import pcie_pkg::*;
  // Request: MRd/MWr/Cfg*
  logic        req_valid, req_ready;//宽度为1，表示握手信号
  tlp_type_e  req_type;    // 事务类型，0:MRd 1:MWr 2:CfgRd 3:CfgWr（示例）
  logic [ADDR_W-1:0] req_addr;// 低位地址，32位或64位。目标地址；在 valid && !ready 期间必须保持稳定
  logic [LEN_W-1:0]  req_len;     // 传输长度，以DW或字节计，统一即可。
  logic [7:0]        req_tag;     // MRd/Cfg* 用
  logic [DATA_W-1:0] req_data;    // 仅 MWr 有效

  // Completion: Cpl/CplD（读必有；写可选“验证友好”状态）
  logic        cpl_valid, cpl_ready;//
  logic [2:0]  cpl_status;  // 完成状态，0=OK
  logic [7:0]  cpl_tag;// MRd/Cfg* 用
  logic [DATA_W-1:0] cpl_data;    // 仅 CplD 有

  // ---------- 默认驱动 ----------
  task automatic drive_defaults(bit accept_cpl = 1'b1);
    req_valid <= 1'b0;
    req_type  <= TLP_MRd;      // 默认给个合法值，避免 X 传播  [ADDED]
    req_addr  <= '0;
    req_len   <= '0;
    req_tag   <= '0;
    req_data  <= '0;
    cpl_ready <= accept_cpl;   // [ADDED]
  endtask

  // ---------- SVA（握手稳定性） ----------
  `define DISABLE_IF disable iff(!rst_n)// 禁用断言和覆盖率，除非 rst_n 为 1
  property p_stable(signal);// 定义一个属性：在 valid 为 1 且 ready 为 0 时，signal 必须保持稳定
    @(posedge clk) `DISABLE_IF (req_valid && !req_ready) |=> $stable(signal);// 如果 req_valid 为 1 且 req_ready 为 0，则在下一个时钟周期 signal 必须保持稳定
  endproperty

  // req_* 在等待 ready 时必须稳定
  a_req_type_stable  : assert property (p_stable(req_type));// 对 req_type 应用该属性
  a_req_addr_stable  : assert property (p_stable(req_addr));// 对 req_addr 应用该属性
  a_req_len_stable   : assert property (p_stable(req_len));// 对 req_len 应用该属性
  a_req_tag_stable   : assert property (p_stable(req_tag));// 对 req_tag 应用该属性
  a_req_data_stable  : assert property (p_stable(req_data));// 对 req_data 应用该属性

  // ---------- 覆盖率（最小够用） ----------
  covergroup cg_tlp @(posedge clk);//定义一个叫 cg_tlp 的 covergroup，在每个时钟上升沿自动采样一次。
    coverpoint req_type { bins rd={TLP_MRd}; bins wr={TLP_MWr}; bins cfg_rd={TLP_CfgRd}; bins cfg_wr={TLP_CfgWr}; }//coverpoint 就是要统计的“观察点”。这里统计 req_type 的四种取值各被命中过几次。
    coverpoint req_len  { bins len_small={[1:4]}; bins len_mid={[5:16]}; bins len_large={[17:64]}; }// 统计 req_len 的长度分布：小于等于4的为 small，5到16的为 mid，17到64的为 large。
    cross req_type, req_len;// 交叉统计 req_type 和 req_len 的组合情况。
  endgroup
  cg_tlp cov = new();// 创建一个 cg_tlp 的实例 cov。

endinterface
