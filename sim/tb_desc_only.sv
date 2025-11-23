`timescale 1ns/1ps
module tb_desc_only();
    logic clk; logic rst_n;
    logic cfg_req_valid; logic [31:0] cfg_req_addr; logic [31:0] cfg_req_wdata;
    logic cfg_resp_valid; logic [31:0] cfg_resp_rdata;

    top dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_req_valid(cfg_req_valid), .cfg_req_addr(cfg_req_addr), .cfg_req_wdata(cfg_req_wdata), .cfg_resp_valid(cfg_resp_valid), .cfg_resp_rdata(cfg_resp_rdata)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task automatic write_reg(input logic [31:0] addr, input logic [31:0] data);
    begin
        @(posedge clk);
        cfg_req_addr <= addr; cfg_req_wdata <= data; cfg_req_valid <= 1;
        @(posedge clk);
        cfg_req_valid <= 0; cfg_req_addr <= 0; cfg_req_wdata <= 0;
    end endtask

    task automatic read_reg(input logic [31:0] addr, output logic [31:0] resp);
    begin
        @(posedge clk);
        cfg_req_addr <= addr; cfg_req_wdata <= 32'd0; cfg_req_valid <= 1; #1;
        resp = cfg_resp_rdata;
        @(posedge clk);
        cfg_req_valid <= 0; cfg_req_addr <= 0; cfg_req_wdata <= 0;
    end endtask

    initial begin
        // locals (declare before any statements to satisfy Questa/ModelSim)
        int i; int j; int k;
        logic [31:0] r;
        bit got_irq;
        int desc2_base; int n_desc; int d_len;

        // locals used in loops (declare before any statements)
        int d_src_idx; int d_dst_idx;
        int kpoll;
        bit all_ok;
        logic [31:0] expected; logic [31:0] got;

        rst_n = 0; cfg_req_valid = 0; cfg_req_addr = 0; cfg_req_wdata = 0;
        // initialize constants
        desc2_base = 32'h0000_9000 >> 2;
        n_desc = 3;
        d_len = 2;
        #100; rst_n = 1; #100;

        // create descriptors and data (same layout as main TB)
        for (i = 0; i < n_desc; i++) begin
            d_src_idx = (32'h0000_7000 + i*32) >> 2;
            d_dst_idx = (32'h0000_8000 + i*64) >> 2;
            for (j = 0; j < d_len; j++) begin
                dut.u_mem.mem[d_src_idx + j] = 32'hDEAD_0000 + i*16 + j;
                dut.u_mem.mem[d_dst_idx + j] = 32'h0;
            end
            dut.u_mem.mem[desc2_base + i*4 + 0] = (32'h0000_7000 + i*32);
            dut.u_mem.mem[desc2_base + i*4 + 1] = (32'h0000_8000 + i*64);
            dut.u_mem.mem[desc2_base + i*4 + 2] = d_len;
            if (i < n_desc-1)
                dut.u_mem.mem[desc2_base + i*4 + 3] = (32'h0000_9000 + (i+1)*16) | (1<<1);
            else
                dut.u_mem.mem[desc2_base + i*4 + 3] = 32'h0 | (1<<1) | (1<<0);
        end

        // clear sticky IRQ and program descriptor pointer + enable descriptor mode
        write_reg(32'h0000_0034, 32'h0);
        write_reg(32'h0000_0028, 32'h0000_9000);
        write_reg(32'h0000_0030, 32'h1);
        // start DMA
        write_reg(32'h0000_0024, 32'h1);

        // for each descriptor wait for irq and verify data
        all_ok = 1;
        for (i = 0; i < n_desc; i++) begin
            // increase poll window substantially so the simulation can complete
            // for longer descriptor chains or slow memory timing in this model
            kpoll = d_len * 128 + 2000;
            got_irq = 0;
            for (k = 0; k < kpoll; k++) begin
                // fast poll: perform one MMIO read per iteration and print value
                read_reg(32'h0000_0034, r);
                $display("%0t: TB poll attempt %0d -> IRQ_REG=0x%08h", $time, k, r);
                if (r[0]) begin
                    got_irq = 1; write_reg(32'h0000_0034, 32'h0); break;
                end
                // no extra @posedge here: read_reg already uses a cycle
            end
            if (!got_irq) begin
                $display("DESC-ONLY FAIL: no IRQ for desc %0d", i);
                all_ok = 0; break;
            end
            d_dst_idx = (32'h0000_8000 + i*64) >> 2;
            for (j = 0; j < d_len; j++) begin
                expected = 32'hDEAD_0000 + i*16 + j;
                got = dut.u_mem.mem[d_dst_idx + j];
                if (got !== expected) begin
                    $display("DESC-ONLY FAIL: mismatch desc %0d word %0d: got 0x%08h exp 0x%08h", i, j, got, expected);
                    all_ok = 0; break;
                end
            end
            if (!all_ok) break;
        end
        if (all_ok) $display("DESC-ONLY PASS"); else $display("DESC-ONLY FAIL");
        $finish;
    end
endmodule
