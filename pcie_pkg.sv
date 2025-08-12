`ifndef PCIE_PKG_SV// 防止重复包含
`define PCIE_PKG_SV// 包含保护宏
`include "uvm_macros.svh"// 引入 UVM 宏定义

package pcie_pkg;
  import uvm_pkg::*;// 引入 UVM 包宏定义
  typedef enum bit [1:0] {
    TLP_MRd   = 2'd0,
    TLP_MWr   = 2'd1,
    TLP_CfgRd = 2'd2,
    TLP_CfgWr = 2'd3
  } tlp_type_e;

  // -------- 分析端口声明 --------
  `uvm_analysis_imp_decl(_req)// 分析端口声明：用于接收请求 TLP
  `uvm_analysis_imp_decl(_cpl)// 分析端口声明：用于接收完成 TLP
  // -------- seq_item（一个TLP） --------
  class pcie_seq_item extends uvm_sequence_item;
    rand tlp_type_e     tlp_type;// 一个可随机化的枚举字段，表示 TLP 的事务类型
    rand bit [63:0]     addr;// 64位地址
    rand bit [9:0]      len_dw;// 传输长度，以 DW（双字）计
    rand bit [7:0]      tag;// 8位标签，用于标识请求和完成
    rand bit [31:0]     data;   // 32位数据，仅 MWr 有效
    `uvm_object_utils_begin(pcie_seq_item)// 注册 pcie_seq_item 类
      `uvm_field_enum(tlp_type_e, tlp_type, UVM_ALL_ON)// 注册 type 字段为枚举类型
      `uvm_field_int(addr,  UVM_ALL_ON)// 注册 addr 字段为 64 位整数
      `uvm_field_int(len_dw,UVM_ALL_ON)// 注册 len_dw 字段为 10 位整数
      `uvm_field_int(tag,   UVM_ALL_ON)// 注册 tag 字段为 8 位整数
      `uvm_field_int(data,  UVM_ALL_ON)// 注册 data 字段为 32 位整数
    `uvm_object_utils_end// 完成注册
    function new(string name="pcie_seq_item"); // 构造函数，调用父类构造函数
      super.new(name); // 调用父类构造函数
    endfunction// 构造函数结束
    constraint c_len { len_dw inside {[1:4]}; } // 限制 len_dw 的取值范围为 1 到 4
  endclass

  // -------- sequencer --------
  class pcie_sequencer extends uvm_sequencer #(pcie_seq_item);
    `uvm_component_utils(pcie_sequencer)
    function new(string n, uvm_component p); 
      super.new(n,p); 
    endfunction
  endclass

  // -------- driver：把 item 映射到 pcie_if --------
  class pcie_driver extends uvm_driver #(pcie_seq_item);
    `uvm_component_utils(pcie_driver)// 注册 pcie_driver 类
    virtual pcie_if vif;// 声明一个虚拟接口 vif，用于驱动 pcie_if 接口

    function new(string n, uvm_component p); 
      super.new(n,p); 
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))// 从配置数据库获取虚拟接口 vif
        `uvm_fatal("NOVIF","pcie_if not set")// 如果没有设置 vif，则报错
    endfunction

    task drive_req(pcie_seq_item tr);// 任务：将 seq_item 映射到 pcie_if 接口
      // 映射：REQ_*（valid/ready握手）
      @(posedge vif.clk);
      vif.req_type  <= tlp_type_e'(tr.tlp_type);// 把事务类型送到接口。tlp_type_e'(...) 是强制类型转换
      vif.req_addr  <= tr.addr[31:0];// 只取低32位地址
      vif.req_len   <= tr.len_dw;// 传输长度
      vif.req_tag   <= tr.tag;// 标签
      vif.req_data  <= tr.data;// 数据，仅 MWr 有效
      vif.req_valid <= 1;// 设置 req_valid 为 1，表示有请求
      // 等待 ready
      do @(posedge vif.clk); //
      while(!vif.req_ready);// 等待 req_ready 为 1，表示 DUT 准备好处理请求
      // 一个拍结束
      @(posedge vif.clk);
      vif.req_valid <= 0;
    endtask

    task run_phase(uvm_phase phase);
      vif.drive_defaults();// 调用接口的默认驱动任务，初始化信号
      forever begin
        pcie_seq_item tr;// 创建一个 pcie_seq_item 对象
        seq_item_port.get_next_item(tr);// 从 seq_item_port 获取下一个事务
        drive_req(tr);// 调用 drive_req 任务，将 seq_item 映射到 pcie_if 接口
        seq_item_port.item_done();// 通知 sequencer 事务已完成
      end
    endtask
  endclass

  // -------- monitor：采 REQ/CPL 两个方向 --------
  class pcie_monitor extends uvm_monitor;
    `uvm_component_utils(pcie_monitor)// 注册 pcie_monitor 类
    virtual pcie_if vif;// 声明一个虚拟接口 vif，用于监控 pcie_if 接口
    uvm_analysis_port #(pcie_seq_item) ap_req; // 请求端口
    uvm_analysis_port #(pcie_seq_item) ap_cpl; // 回来的完成
    function new(string n, uvm_component p); 
      super.new(n,p);// 调用父类构造函数
      ap_req = new("ap_req", this); // 创建请求分析端口
      ap_cpl = new("ap_cpl", this);// 创建完成分析端口
    endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))// 从配置数据库获取虚拟接口 vif
        `uvm_fatal("NOVIF","pcie_if not set")// 如果没有设置 vif，则报错
    endfunction
    task run_phase(uvm_phase phase);//在每个时钟上升沿看握手，一旦发现某个方向 valid&&ready，就把那一拍的字段采下来、拼成一个 pcie_seq_item，然后通过 analysis_port（ap_req/ap_cpl）广播给 scoreboard、coverage 等订阅者。
      bit req_hs, cpl_hs;      // ★ 变量提前声明
      bit req_hs_d, cpl_hs_d;  // 上一拍握手状态

      forever begin
        @(posedge vif.clk);
        req_hs = (vif.req_valid && vif.req_ready);
        if (req_hs && !req_hs_d) begin//
          pcie_seq_item tr = pcie_seq_item::type_id::create("req_tr");// 创建一个新的 pcie_seq_item 对象
          tr.tlp_type  = tlp_type_e'(vif.req_type);// 把事务类型转换为枚举类型
          tr.addr  = vif.req_addr;//
          tr.len_dw= vif.req_len;
          tr.tag   = vif.req_tag;
          tr.data  = vif.req_data;
          `uvm_info("MON", $sformatf("CAP %s addr=0x%0h tag=%0d data=0x%08h",
             (tr.tlp_type==TLP_MWr)?"MWr":"MRd",
             tr.addr, tr.tag, tr.data), UVM_MEDIUM)
          ap_req.write(tr);
        end
        req_hs_d = req_hs;

        // --- 完成方向（CplD：同样只在握手沿采一次） ---
        cpl_hs = (vif.cpl_valid && vif.cpl_ready);
        if (cpl_hs && !cpl_hs_d) begin//
          pcie_seq_item c = pcie_seq_item::type_id::create("cpl_tr");
          c.tlp_type = TLP_MRd; // 用于比对；读的CplD
          c.tag  = vif.cpl_tag;
          c.data = vif.cpl_data;
          `uvm_info("MON", $sformatf("CAP CplD tag=%0d data=0x%08h",
                c.tag, c.data), UVM_MEDIUM)
          ap_cpl.write(c);
        end
        cpl_hs_d = cpl_hs;
      end
    endtask
  endclass

  // -------- agent --------
  class pcie_agent extends uvm_agent;
    `uvm_component_utils(pcie_agent)
    pcie_sequencer sqr; // 声明一个 pcie_sequencer 对象 sqr，用于发送事务
    pcie_driver drv; // 声明一个 pcie_driver 对象 drv，用于驱动 pcie_if 接口
    pcie_monitor mon;// 声明一个 pcie_monitor 对象 mon，用于监控 pcie_if 接口
    function new(string n, uvm_component p); 
      super.new(n,p); 
    endfunction
    function void build_phase(uvm_phase phase);
      sqr = pcie_sequencer::type_id::create("sqr", this);// 创建一个 pcie_sequencer 实例 sqr
      drv = pcie_driver   ::type_id::create("drv", this);// 创建一个 pcie_driver 实例 drv
      mon = pcie_monitor  ::type_id::create("mon", this);// 创建一个 pcie_monitor 实例 mon
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);// 连接驱动的 seq_item_port 到 sequencer 的 seq_item_export
    endfunction
  endclass

  // -------- scoreboard（最小版：按 tag 匹配 MRd 的CPLD） --------
  class pcie_scoreboard extends uvm_component;
    `uvm_component_utils(pcie_scoreboard)// 注册 pcie_scoreboard 类
    uvm_analysis_imp_req #(pcie_seq_item, pcie_scoreboard) imp_req;// 分析端口实现：用于接收请求 TLP
    uvm_analysis_imp_cpl #(pcie_seq_item, pcie_scoreboard) imp_cpl;// 分析端口实现：用于接收完成 TLP
    // 记录 outstanding 读：tag -> addr
    bit [63:0] tag2addr [byte]; // 声明一个关联数组，用于存储 tag 到 addr 的映射关系
    function new(string n, uvm_component p); 
      super.new(n,p);
      imp_req = new("imp_req", this);// 创建请求分析端口实现
      imp_cpl = new("imp_cpl", this);// 创建完成分析端口实现
    endfunction
    // 接口：analysis_imp 需要 write()
    function void write_req(input pcie_seq_item tr); //
      if (tr.tlp_type==TLP_MRd)
      tag2addr[tr.tag] = tr.addr;
    endfunction
    function void write_cpl(pcie_seq_item c);
      if (tag2addr.exists(c.tag)) begin
        `uvm_info("SB", $sformatf("CPL matched tag=%0d addr=0x%0h data=0x%08h",
                 c.tag, tag2addr[c.tag], c.data), UVM_MEDIUM)
        tag2addr.delete(c.tag);
      end
      else begin
        `uvm_error("SB", $sformatf("Unexpected CPL tag=%0d data=0x%08h",
                 c.tag, c.data))
      end

  endfunction

  endclass

  // -------- env --------
  class pcie_env extends uvm_env;
    `uvm_component_utils(pcie_env)// 注册 pcie_env 类
    pcie_agent agt;// 声明一个 pcie_agent 对象 agt，用于处理 PCIe 事务
    pcie_scoreboard sb;// 声明一个 pcie_scoreboard 对象 sb，用于验证事务
    function new(string n, uvm_component p);
       super.new(n,p);
    endfunction
    function void build_phase(uvm_phase phase);// 构建阶段：创建 agent 和 scoreboard
      agt = pcie_agent     ::type_id::create("agt", this);// 创建一个 pcie_agent 实例 agt
      sb  = pcie_scoreboard::type_id::create("sb",  this);// 创建一个 pcie_scoreboard 实例 sb
    endfunction
    function void connect_phase(uvm_phase phase);// 连接阶段：将 agent 的分析端口连接到 scoreboard
      agt.mon.ap_req.connect(sb.imp_req);// 将 agent 的请求分析端口连接到 scoreboard 的请求端口实现
      agt.mon.ap_cpl.connect(sb.imp_cpl);// 将 agent 的完成分析端口连接到 scoreboard 的完成端口实现
    endfunction
  endclass

  // -------- sequence（冒烟：先写后读） --------
  class pcie_smoke_seq extends uvm_sequence #(pcie_seq_item);// 冒烟测试序列：先写后读
    `uvm_object_utils(pcie_smoke_seq)// 注册 pcie_smoke_seq 类
    function new(string n="pcie_smoke_seq"); 
      super.new(n); 
    endfunction
    task body();// 序列主体：发送一组事务
      pcie_seq_item tr;// 声明一个 pcie_seq_item 对象
      // 写：MWr addr=0x10 data=0xA5A50001
      tr = pcie_seq_item::type_id::create("wr");// 创建一个新的 pcie_seq_item 对象
      start_item(tr);// 开始事务
        tr.tlp_type   = TLP_MWr; // 设置事务类型为 MWr
        tr.addr = 'h10; // 设置地址为 0x10
        tr.len_dw=1; // 设置传输长度为 1 DW
        tr.data='hA5A5_0001; // 设置数据为 0xA5A50001
        tr.tag=8'h00;// 设置标签为 0
      finish_item(tr);// 完成事务
      `uvm_info("SEQ", $sformatf("SEND MWr addr=0x%0h data=0x%08h tag=%0d",
             tr.addr, tr.data, tr.tag), UVM_MEDIUM) 
      // 读：MRd addr=0x10 tag=7
      tr = pcie_seq_item::type_id::create("rd");// 创建一个新的 pcie_seq_item 对象
      start_item(tr);// 开始事务
        tr.tlp_type   = TLP_MRd; // 设置事务类型为 MRd
        tr.addr = 'h10;// 设置地址为 0x10
        tr.len_dw=1; // 设置传输长度为 1 DW
        tr.tag=8'h07;// 设置标签为 7
      finish_item(tr);
      `uvm_info("SEQ", $sformatf("SEND MRd addr=0x%0h tag=%0d",
             tr.addr, tr.tag), UVM_MEDIUM) 
    endtask
  endclass

  // -------- test --------
  class pcie_base_test extends uvm_test;
    `uvm_component_utils(pcie_base_test)
    pcie_env env; // 声明一个 pcie_env 对象 env，用于环境配置
    function new(string n, uvm_component p); 
      super.new(n,p); 
    endfunction
    function void build_phase(uvm_phase phase);
      env = pcie_env::type_id::create("env", this);// 创建一个 pcie_env 实例 env
    endfunction
    task run_phase(uvm_phase phase);
      pcie_smoke_seq seq_h;
      phase.raise_objection(this);
      
      seq_h = pcie_smoke_seq::type_id::create("seq_h");
      seq_h.start(env.agt.sqr);// 启动序列 seq，发送事务到 sequencer
      #200ns;
      phase.drop_objection(this);// 结束测试，撤销异议
    endtask
  endclass

endpackage
`endif
