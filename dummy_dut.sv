module dummy_dut #(parameter ADDR_W=32, DATA_W=32, LEN_W=10) (pcie_if ifc);//这里的 ifc 就是接口实例的句柄
  import pcie_pkg::*;
  // 简易内存：地址低12位做索引
  // 参数化内存地址位宽，统一索引位
  localparam int MEM_AW = 12;         // 2^12 = 4096
  logic [DATA_W-1:0] mem [0:(1<<MEM_AW)-1];
  // 恒 ready，返回有两拍延迟
  assign ifc.req_ready = 1'b1;
  assign ifc.cpl_ready = 1'b1; // TB侧monitor消费

  // pipeline for MRd
  logic        r_mrd_vld_d1, r_mrd_vld_d2;// MRd 有效标志
  logic [7:0]  r_mrd_tag_d1, r_mrd_tag_d2;// MRd 的 tag
  logic [ADDR_W-1:0] r_mrd_addr_d1, r_mrd_addr_d2;// MRd 的地址

  always_ff @(posedge ifc.clk or negedge ifc.rst_n) begin
    if(!ifc.rst_n) begin// 如果复位信号为低
      // 复位所有信号
      ifc.cpl_valid   <= 1'b0;
      ifc.cpl_status  <= 3'd0;
      ifc.cpl_tag     <= '0;
      ifc.cpl_data    <= '0;

      r_mrd_vld_d1    <= 1'b0;
      r_mrd_vld_d2    <= 1'b0;
      r_mrd_tag_d1    <= '0;
      r_mrd_tag_d2    <= '0;
      r_mrd_addr_d1   <= '0;
      r_mrd_addr_d2   <= '0;
    end else begin// 如果复位信号为高
      // 捕获 MRd
      r_mrd_vld_d1  <= (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_MRd);// 如果请求有效且准备就绪，且类型为 MRd，则设置 r_mrd_vld_d1 为 1
      if (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_MRd) begin
        r_mrd_tag_d1  <= ifc.req_tag;// 捕获 MRd 的 tag
        r_mrd_addr_d1 <= ifc.req_addr;// 捕获 MRd 的地址
      end
      //流水推进到第 2 级
      r_mrd_vld_d2  <= r_mrd_vld_d1;// 将 r_mrd_vld_d1 的值传递到 r_mrd_vld_d2
      r_mrd_tag_d2  <= r_mrd_tag_d1;// 将 r_mrd_tag_d1 的值传递到 r_mrd_tag_d2
      r_mrd_addr_d2 <= r_mrd_addr_d1;// 将 r_mrd_addr_d1 的值传递到 r_mrd_addr_d2

      // MWr 直接写
      if (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_MWr)
        mem[ifc.req_addr[MEM_AW+1:2]] <= ifc.req_data;
      end

      // 两拍后产生 Completion with Data
      ifc.cpl_valid <= r_mrd_vld_d2;// 如果 r_mrd_vld_d2 为 1，则表示有 MRd 请求完成
      ifc.cpl_status<= 3'd0;// 完成状态为 0，表示 OK
      ifc.cpl_tag   <= r_mrd_tag_d2;// 设置完成的 tag 为 r_mrd_tag_d2
      ifc.cpl_data  <= r_mrd_vld_d2// 如果 r_mrd_vld_d2 为 1，则表示有 MRd 请求完成
                       ? (mem[r_mrd_addr_d2[13:2]] ^ 32'hDEAD_BEEF) // 计算返回数据
                       : '0;// 如果没有 MRd 请求，则返回 0
    end
endmodule

