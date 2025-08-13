# pcie-uvm-lite

A minimal-yet-practical UVM verification environment for a PCIe-like transaction layer (MWr/MRd/CplD), focused on clarity and coverage growth. The project demonstrates a clean UVM stack (seq → driver → DUT → monitor → scoreboard) with tags, request/response correlation, and a ready-to-run make flow for Synopsys VCS (tested on VCSMX U-2023.03-SP2, UVM-1.2). Questa instructions included.

---

## ✨ What’s inside

* UVM testbench for PCIe-like TLPs: **MWr**, **MRd**, **CplD**
* **Tag**-based request/completion matching in **scoreboard**
* Clean **agent/env/test** layering
* Golden **logs** and example **waveform** checkpoints
* Ready-to-run **Makefile** for VCS；Questa 命令示例

> Current status (from your latest run): `pcie_base_test` passes with MWr→MRd→CplD loop and scoreboard match.

---

## 🗂️ Repository structure

```
pcie-uvm-lite/
├─ docs/
│  ├─ README_images/
│  │  └─ uvm_pass_log.png            # sample log screenshot
│  └─ design_notes.md                # notes / TODOs
├─ rtl/
│  └─ pcie_dut_stub.sv               # simple behavioral DUT (placeholder)
├─ tb/
│  ├─ if/                            # interfaces & assertions
│  │  └─ pcie_if.sv
│  ├─ pkg/                           # all classes packaged here
│  │  └─ pcie_pkg.sv                 # seq_item, seq, driver, monitor,
│  │                                  # sequencer, agent, scoreboard, env, test
│  ├─ top/
│  │  └─ tb_top.sv
│  └─ tests/
│     ├─ pcie_base_seq.sv            # optional split (also included via pkg)
│     └─ pcie_base_test.sv           # optional split (also included via pkg)
├─ sim/
│  ├─ Makefile                       # one-command build/run for VCS
│  ├─ questa.do                      # optional Questa script
│  ├─ .gitignore
│  └─ waves.sh                       # example EPWave/DVE/SimVision launcher
├─ .editorconfig
├─ LICENSE
└─ README.md
```

> **Note**: You can keep everything in `pcie_pkg.sv` during development and later split (
> `pcie_driver.sv`, `pcie_monitor.sv`, `pcie_scoreboard.sv`, …) if you prefer.

---

## 🧩 Key files (current minimal content)

### `tb/if/pcie_if.sv`

```systemverilog
interface pcie_if(input logic clk, input logic rst_n);
  // Simple DUT-side signals (abstracted TLP handshake)
  logic        tx_valid;   // driver → DUT
  logic [1:0]  tx_type;    // 0=MWr, 1=MRd, 2=CplD
  logic [5:0]  tx_tag;
  logic [31:0] tx_addr;
  logic [31:0] tx_data;
  logic        tx_ready;   // DUT → driver

  logic        rx_valid;   // DUT → monitor
  logic [1:0]  rx_type;    // 2=CplD
  logic [5:0]  rx_tag;
  logic [31:0] rx_addr;
  logic [31:0] rx_data;
  logic        rx_ready;   // monitor → DUT (consume)

  // Default drive
  task automatic drive_defaults();
    tx_valid <= 0; tx_type <= '0; tx_tag <= '0; tx_addr <= '0; tx_data <= '0;
    rx_ready <= 1'b1;
  endtask
endinterface
```

### `tb/pkg/pcie_pkg.sv`

> **One-file package** with all UVM components. This matches your working log. (Feel free to split later.)

```systemverilog
`ifndef PCIE_PKG_SV
`define PCIE_PKG_SV
`include "uvm_macros.svh"
package pcie_pkg; import uvm_pkg::*;

  typedef enum bit [1:0] { TLP_MRd=2'd0, TLP_MWr=2'd1, TLP_CplD=2'd2 } tlp_type_e;

  // ---------------- seq_item ----------------
  class pcie_seq_item extends uvm_sequence_item;
    rand tlp_type_e   tlp_type;
    rand bit [5:0]    tag;
    rand bit [31:0]   addr;
    rand bit [31:0]   data;
    `uvm_object_utils_begin(pcie_seq_item)
      `uvm_field_enum(tlp_type_e, tlp_type, UVM_ALL_ON)
      `uvm_field_int(tag,  UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end
    function new(string name="pcie_seq_item"); super.new(name); endfunction
  endclass

  // ---------------- sequence ----------------
  class pcie_base_seq extends uvm_sequence #(pcie_seq_item);
    `uvm_object_utils(pcie_base_seq)
    function new(string name="pcie_base_seq"); super.new(name); endfunction
    task body(); pcie_seq_item tr;
      // 1) MWr
      tr = pcie_seq_item::type_id::create("mw");
      start_item(tr); tr.tlp_type=TLP_MWr; tr.tag=0; tr.addr='h10; tr.data='hA5A5_0001; finish_item(tr);
      // 2) MRd
      tr = pcie_seq_item::type_id::create("mr");
      start_item(tr); tr.tlp_type=TLP_MRd; tr.tag=7; tr.addr='h10; tr.data='0;          finish_item(tr);
    endtask
  endclass

  // ---------------- driver ----------------
  class pcie_driver extends uvm_driver #(pcie_seq_item);
    `uvm_component_utils(pcie_driver)
    virtual pcie_if vif;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF","pcie_if not set")
    endfunction
    task run_phase(uvm_phase phase); pcie_seq_item tr; vif.drive_defaults();
      forever begin
        seq_item_port.get_next_item(tr);
        // simple 1-cycle valid handshake
        @(posedge vif.clk); vif.tx_valid<=1; vif.tx_type<=tr.tlp_type; vif.tx_tag<=tr.tag; vif.tx_addr<=tr.addr; vif.tx_data<=tr.data;
        @(posedge vif.clk); vif.tx_valid<=0;
        `uvm_info(get_type_name(), $sformatf("SEND %s addr=%0h data=%0h tag=%0d", tr.tlp_type.name(), tr.addr, tr.data, tr.tag), UVM_MEDIUM)
        seq_item_port.item_done();
      end
    endtask
  endclass

  // ---------------- monitor ----------------
  `uvm_analysis_imp_decl(_req)
  `uvm_analysis_imp_decl(_cpl)

  class pcie_monitor extends uvm_component;
    `uvm_component_utils(pcie_monitor)
    uvm_analysis_port #(pcie_seq_item) ap_req; // for MWr/MRd
    uvm_analysis_port #(pcie_seq_item) ap_cpl; // for CplD
    virtual pcie_if vif;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      ap_req = new("ap_req", this); ap_cpl = new("ap_cpl", this);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF","pcie_if not set")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin @(posedge vif.clk);
        if (vif.tx_valid) begin pcie_seq_item tr = new();
          tr.tlp_type = tlp_type_e'(vif.tx_type); tr.tag = vif.tx_tag; tr.addr = vif.tx_addr; tr.data = vif.tx_data;
          `uvm_info(get_type_name(), $sformatf("CAP %s addr=%0h tag=%0d data=%0h", tr.tlp_type.name(), tr.addr, tr.tag, tr.data), UVM_MEDIUM)
          if (tr.tlp_type==TLP_MWr || tr.tlp_type==TLP_MRd) ap_req.write(tr);
        end
        if (vif.rx_valid) begin pcie_seq_item tr2 = new();
          tr2.tlp_type = TLP_CplD; tr2.tag = vif.rx_tag; tr2.addr = vif.rx_addr; tr2.data = vif.rx_data;
          `uvm_info(get_type_name(), $sformatf("CAP CplD tag=%0d data=%0h", tr2.tag, tr2.data), UVM_MEDIUM)
          ap_cpl.write(tr2);
        end
      end
    endtask
  endclass

  // ---------------- sequencer ----------------
  class pcie_sequencer extends uvm_sequencer #(pcie_seq_item);
    `uvm_component_utils(pcie_sequencer)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
  endclass

  // ---------------- scoreboard ----------------
  class pcie_scoreboard extends uvm_component;
    `uvm_component_utils(pcie_scoreboard)
    uvm_analysis_imp_req #(pcie_seq_item, pcie_scoreboard) req_exp; // from requests
    uvm_analysis_imp_cpl #(pcie_seq_item, pcie_scoreboard) cpl_got; // from completions

    // tag → addr/data expectations
    typedef struct packed { bit [31:0] addr; bit [31:0] data; bit valid; } exp_t;
    exp_t exp_by_tag [bit[5:0]];

    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      req_exp = new("req_exp", this); cpl_got = new("cpl_got", this);
    endfunction

    // capture expectations on requests (for MRd: expect CplD later)
    function void write_req(pcie_seq_item tr);
      if (tr.tlp_type==TLP_MRd) begin
        exp_t e; e.addr=tr.addr; e.data='0; e.valid=1; exp_by_tag[tr.tag]=e;
      end
    endfunction

    // match completions
    function void write_cpl(pcie_seq_item tr);
      if (exp_by_tag.exists(tr.tag) && exp_by_tag[tr.tag].valid) begin
        `uvm_info("SB", $sformatf("CPL matched tag=%0d addr=%0h data=%0h", tr.tag, exp_by_tag[tr.tag].addr, tr.data), UVM_LOW)
        exp_by_tag[tr.tag].valid=0;
      end else begin
        `uvm_error("SB", $sformatf("Unexpected CplD tag=%0d data=%0h", tr.tag, tr.data))
      end
    endfunction
  endclass

  // ---------------- agent ----------------
  class pcie_agent extends uvm_agent;
    `uvm_component_utils(pcie_agent)
    pcie_sequencer  sqr; pcie_driver drv; pcie_monitor mon;
    virtual pcie_if vif;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      sqr = pcie_sequencer::type_id::create("sqr", this);
      drv = pcie_driver   ::type_id::create("drv", this);
      mon = pcie_monitor  ::type_id::create("mon", this);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF","pcie_if not set")
      uvm_config_db#(virtual pcie_if)::set(this, "drv", "vif", vif);
      uvm_config_db#(virtual pcie_if)::set(this, "mon", "vif", vif);
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ---------------- env ----------------
  class pcie_env extends uvm_env;
    `uvm_component_utils(pcie_env)
    pcie_agent agt; pcie_scoreboard sb;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      agt = pcie_agent     ::type_id::create("agt", this);
      sb  = pcie_scoreboard::type_id::create("sb",  this);
    endfunction
    function void connect_phase(uvm_phase phase);
      agt.mon.ap_req.connect(sb.req_exp);
      agt.mon.ap_cpl.connect(sb.cpl_got);
    endfunction
  endclass

  // ---------------- test ----------------
  class pcie_base_test extends uvm_test;
    `uvm_component_utils(pcie_base_test)
    pcie_env env; function new(string name, uvm_component parent); s
```
# PCIe-UVM-lite
<img width="1283" height="598" alt="image" src="https://github.com/user-attachments/assets/792d02bc-e52f-448f-aad5-a0d7d8254ea8" />
<img width="1845" height="501" alt="image" src="https://github.com/user-attachments/assets/5f158711-064b-40fd-a9a0-7738751d1e55" />
