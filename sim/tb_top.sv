`timescale 1ns/1ps
module tb_top();
    // clocks and reset
    logic clk;
    logic rst_n;

    // simple cfg signals
    logic cfg_req_valid;
    logic [31:0] cfg_req_addr;
    logic [31:0] cfg_req_wdata;
    logic cfg_resp_valid;
    logic [31:0] cfg_resp_rdata;

    // Instantiate DUT
    top dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_req_valid(cfg_req_valid),
        .cfg_req_addr(cfg_req_addr),
        .cfg_req_wdata(cfg_req_wdata),
        .cfg_resp_valid(cfg_resp_valid),
        .cfg_resp_rdata(cfg_resp_rdata)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // helper: write a 32-bit cfg register (one clock cycle)
    task automatic write_reg(input logic [31:0] addr, input logic [31:0] data);
    begin
        @(posedge clk);
        cfg_req_addr  <= addr;
        cfg_req_wdata <= data;
        cfg_req_valid <= 1;
        // keep valid for one cycle
        @(posedge clk);
        cfg_req_valid <= 0;
        cfg_req_addr  <= 0;
        cfg_req_wdata <= 0;
    end
    endtask

    // helper: read cfg register by issuing a request and sampling response
    task automatic read_reg(input logic [31:0] addr, output logic [31:0] resp);
    begin
        @(posedge clk);
        cfg_req_addr  <= addr;
        cfg_req_wdata <= 32'd0;
        cfg_req_valid <= 1;
        // small delta to allow combinational response to settle
        #1;
        resp = cfg_resp_rdata;
        @(posedge clk);
        cfg_req_valid <= 0;
        cfg_req_addr  <= 0;
        cfg_req_wdata <= 0;
    end
    endtask

    // helper task to run a single transfer case (module-scope task)
    task automatic run_case(input logic [31:0] src_addr, input logic [31:0] dst_addr, input int words, output bit passed);
        int local_timeout;
        int k;
        int idx_s;
        int idx_d;
        logic [31:0] rr;
        int j_local;
        logic [31:0] expected_local;
        logic [31:0] got_local;
    begin
        passed = 1;
        // compute indices
        idx_s = src_addr >> 2;
        idx_d = dst_addr >> 2;
        // init patterns
        for (k = 0; k < words; k++) begin
            dut.u_mem.mem[idx_s + k] = 32'h5A5A_0000 + k;
            dut.u_mem.mem[idx_d + k] = 32'h0;
        end

        // program registers
        write_reg(32'h0000_0010, src_addr);
        write_reg(32'h0000_0014, 32'h0);
        write_reg(32'h0000_0018, dst_addr);
        write_reg(32'h0000_001C, 32'h0);
        write_reg(32'h0000_0020, words);
        $display("TB: program start src=0x%08h dst=0x%08h words=%0d", src_addr, dst_addr, words);
        // Pulse START twice to avoid a 1-cycle sampling race with the DMA
        write_reg(32'h0000_0024, 32'h1);
        write_reg(32'h0000_0024, 32'h1);

        // poll for done
        local_timeout = (words == 0) ? 50 : (words * 8 + 200); // generous
        for (k = 0; k < local_timeout; k++) begin
            read_reg(32'h0000_002C, rr);
            if (rr[0]) begin
                // verify
                for (j_local = 0; j_local < words; j_local++) begin
                    expected_local = 32'h5A5A_0000 + j_local;
                    got_local = dut.u_mem.mem[idx_d + j_local];
                    if (got_local !== expected_local) begin
                        $display("CASE FAIL: src=0x%08h dst=0x%08h words=%0d mismatch at %0d: got 0x%08h exp 0x%08h", src_addr, dst_addr, words, j_local, got_local, expected_local);
                        // Debug dump to help correlate DUT internals with the failure
                        $display("DEBUG DUMP @%0t: DUT DMA state=%0d remain=%0d fifo_count=%0d read_index=%0d write_index=%0d", $time, dut.u_dma.state, dut.u_dma.remain, dut.u_dma.fifo_count, dut.u_dma.read_index, dut.u_dma.write_index);
                        $display("DEBUG DUMP @%0t: DUT DMA mem_read_en=%b mem_read_addr=%0d mem_read_valid=%b mem_write_en=%b mem_write_addr=%0d", $time, dut.u_dma.mem_read_en, dut.u_dma.mem_read_addr, dut.u_dma.mem_read_valid, dut.u_dma.mem_write_en, dut.u_dma.mem_write_addr);
                        $display("DEBUG DUMP @%0t: TOP desc signals dma_desc_read_req=%b desc_addr_latched=%0d desc_req_latched=%b dma_desc_read_ack=%b dma_desc_read_data=0x%08h top_mem_read_en=%b top_mem_read_addr=%0d mem_read_valid=%b", $time, dut.dma_desc_read_req, dut.desc_addr_latched, dut.desc_req_latched, dut.dma_desc_read_ack, dut.dma_desc_read_data, dut.mem_read_en, dut.mem_read_addr, dut.mem_read_valid);
                        $display("DEBUG MEM SNAP @%0t: src[0..3]=%08h %08h %08h %08h dst[0..3]=%08h %08h %08h %08h", $time,
                                 dut.u_mem.mem[idx_s + 0], dut.u_mem.mem[idx_s + 1], dut.u_mem.mem[idx_s + 2], dut.u_mem.mem[idx_s + 3],
                                 dut.u_mem.mem[idx_d + 0], dut.u_mem.mem[idx_d + 1], dut.u_mem.mem[idx_d + 2], dut.u_mem.mem[idx_d + 3]);
                        passed = 0;
                        return;
                    end
                end
                $display("CASE PASS: src=0x%08h dst=0x%08h words=%0d", src_addr, dst_addr, words);
                return;
            end
            @(posedge clk);
        end
        // timeout
        $display("CASE TIMEOUT: src=0x%08h dst=0x%08h words=%0d", src_addr, dst_addr, words);
        passed = 0;
    end
    endtask

    // Test sequence: multiple deterministic tests + randomized tests
    initial begin
        // local declarations must appear before statements for Questa/ModelSim
        int timeout;
        int i;
        logic [31:0] r;
        int num_words;
        int k;
        int src_idx;
        int dst_idx;
        int j;
        logic [31:0] expected;
        logic [31:0] got;
        int pass_count;
        int fail_count;
        bit passed;
        int rnd_tests;
        int max_words;
        int base_src;
        int base_dst;
        // descriptor test locals
        int desc_base;
        int d0_src_idx;
        int d0_dst_idx;
        int d0_len;
        int d1_src_idx;
        int d1_dst_idx;
        int d1_len;
        bit all_ok;
        // IRQ-on-each test locals
        int desc2_base;
        int d_src_idx;
        int d_dst_idx;
        int d_len;
        int n_desc;
        int kpoll;
        bit got_irq;

        rst_n = 0;
        cfg_req_valid = 0;
        cfg_req_addr = 0;
        cfg_req_wdata = 0;
        #100;
        rst_n = 1;
        #100;

        pass_count = 0;
        fail_count = 0;

        // Deterministic cases
        run_case(32'h0000_1000, 32'h0000_2000, 16, passed); // basic
        if (passed) pass_count++; else fail_count++;
        run_case(32'h0000_1000, 32'h0000_2000, 0, passed);  // zero-length
        if (passed) pass_count++; else fail_count++;
        run_case(32'h0000_1004, 32'h0000_2008, 1, passed);  // small
        if (passed) pass_count++; else fail_count++;
        run_case(32'h0000_1103, 32'h0000_2107, 8, passed);  // misaligned addresses (low bits non-zero)
        if (passed) pass_count++; else fail_count++;

        // concurrent transfer test: attempt to start while busy
        // prepare a longer transfer and attempt start again immediately
        num_words = 32;
        // init
        src_idx = 32'h0000_3000 >> 2;
        dst_idx = 32'h0000_4000 >> 2;
        for (i = 0; i < num_words; i++) begin
            dut.u_mem.mem[src_idx + i] = 32'hC3C3_0000 + i;
            dut.u_mem.mem[dst_idx + i] = 32'h0;
        end
        write_reg(32'h0000_0010, 32'h0000_3000);
        write_reg(32'h0000_0018, 32'h0000_4000);
        write_reg(32'h0000_0020, num_words);
        write_reg(32'h0000_0024, 32'h1); // start
        // immediately try to start again (should be ignored)
        write_reg(32'h0000_0024, 32'h1);
        // poll and verify
        timeout = num_words * 8 + 200;
        concurrent_loop: for (i = 0; i < timeout; i++) begin
            read_reg(32'h0000_002C, r);
            if (r[0]) begin
                // verify
                all_ok = 1;
                for (j = 0; j < num_words; j++) begin
                    expected = 32'hC3C3_0000 + j;
                    got = dut.u_mem.mem[dst_idx + j];
                    if (got !== expected) begin
                        $display("CONCURRENT CASE FAIL: mismatch at %0d: got 0x%08h expected 0x%08h", j, got, expected);
                        all_ok = 0;
                        break;
                    end
                end
                if (all_ok) begin
                    $display("CONCURRENT CASE PASS: %0d words", num_words);
                    pass_count++;
                end else begin
                    fail_count++;
                end
                disable concurrent_loop;
            end
            @(posedge clk);
        end

                // Descriptor-mode test: create two descriptors in memory and chain them
                desc_base = 32'h0000_8000 >> 2; // word index for descriptor table
                // descriptor 0: copy 8 words from 0x5000 -> 0x6000
                d0_src_idx = 32'h0000_5000 >> 2;
                d0_dst_idx = 32'h0000_6000 >> 2;
                d0_len     = 8;
                // descriptor 1: copy 4 words from 0x5100 -> 0x6200
                d1_src_idx = 32'h0000_5100 >> 2;
                d1_dst_idx = 32'h0000_6200 >> 2;
                d1_len     = 4;
                // fill source data and clear destinations
                for (i = 0; i < d0_len; i++) begin
                    dut.u_mem.mem[d0_src_idx + i] = 32'hA5A5_0000 + i;
                    dut.u_mem.mem[d0_dst_idx + i] = 32'h0;
                end
                for (i = 0; i < d1_len; i++) begin
                    dut.u_mem.mem[d1_src_idx + i] = 32'hB6B6_0000 + i;
                    dut.u_mem.mem[d1_dst_idx + i] = 32'h0;
                end
                // write descriptor 0
                dut.u_mem.mem[desc_base + 0] = 32'h0000_5000; // src addr (byte)
                dut.u_mem.mem[desc_base + 1] = 32'h0000_6000; // dst addr (byte)
                dut.u_mem.mem[desc_base + 2] = d0_len;        // len (words)
                dut.u_mem.mem[desc_base + 3] = (32'h0000_8000 + 4*4); // next_desc_ptr -> next descriptor (byte addr)
                // write descriptor 1 (chained)
                dut.u_mem.mem[desc_base + 4] = 32'h0000_5100; // src
                dut.u_mem.mem[desc_base + 5] = 32'h0000_6200; // dst
                dut.u_mem.mem[desc_base + 6] = d1_len;        // len
                // set flags in word3: bit0=IRQ on completion, bits[3:1]=priority (choose 3)
                dut.u_mem.mem[desc_base + 7] = 32'h0000_0007;  // next = 0 (end) + flags (irq=1, prio=3)

                // program descriptor pointer and enable descriptor mode
                write_reg(32'h0000_0028, 32'h0000_8000); // desc_ptr (byte addr)
                write_reg(32'h0000_0030, 32'h1);         // desc_mode = 1
                // start DMA
                write_reg(32'h0000_0024, 32'h1);
                // poll for done
                timeout = (d0_len + d1_len) * 8 + 200;
                descriptor_poll: for (i = 0; i < timeout; i++) begin
                    read_reg(32'h0000_002C, r);
                    if (r[0]) begin
                        // verify descriptor 0
                        all_ok = 1;
                        for (j = 0; j < d0_len; j++) begin
                            expected = 32'hA5A5_0000 + j;
                            got = dut.u_mem.mem[d0_dst_idx + j];
                            if (got !== expected) begin
                                $display("DESC CASE FAIL: d0 mismatch at %0d: got 0x%08h expected 0x%08h", j, got, expected);
                                all_ok = 0;
                                break;
                            end
                        end
                        // verify descriptor 1
                        for (j = 0; all_ok && j < d1_len; j++) begin
                            expected = 32'hB6B6_0000 + j;
                            got = dut.u_mem.mem[d1_dst_idx + j];
                            if (got !== expected) begin
                                $display("DESC CASE FAIL: d1 mismatch at %0d: got 0x%08h expected 0x%08h", j, got, expected);
                                all_ok = 0;
                                break;
                            end
                        end
                        if (all_ok) begin
                            $display("DESC CASE PASS: chained descriptors executed");
                            pass_count++;
                            // verify IRQ status was set by the second descriptor
                            read_reg(32'h0000_0034, r);
                            if (!r[0]) begin
                                $display("DESC CASE FAIL: expected IRQ status set but got 0x%08h", r);
                                fail_count++;
                            end
                        end else begin
                            fail_count++;
                        end
                        disable descriptor_poll;
                    end
                    @(posedge clk);
                end

            // disable descriptor mode to return to direct DMA operation
            // IRQ-on-each descriptor test: create a 3-descriptor chain where each descriptor requests IRQ_ON_EACH
            desc2_base = 32'h0000_9000 >> 2;
            n_desc = 3;
            d_len = 2;
            // setup per-descriptor source/dst regions and fill data
            for (i = 0; i < n_desc; i++) begin
                d_src_idx = (32'h0000_7000 + i*32) >> 2; // spaced regions
                d_dst_idx = (32'h0000_8000 + i*64) >> 2;
                for (j = 0; j < d_len; j++) begin
                    dut.u_mem.mem[d_src_idx + j] = 32'hDEAD_0000 + i*16 + j;
                    dut.u_mem.mem[d_dst_idx + j] = 32'h0;
                end
                // write descriptor word0..2
                dut.u_mem.mem[desc2_base + i*4 + 0] = (32'h0000_7000 + i*32); // src byte addr
                dut.u_mem.mem[desc2_base + i*4 + 1] = (32'h0000_8000 + i*64); // dst byte addr
                dut.u_mem.mem[desc2_base + i*4 + 2] = d_len;
                // word3 = next_ptr | flags; set IRQ_ON_EACH (bit1) for all descriptors; last descriptor also set IRQ_ON_COMPLETE (bit0)
                if (i < n_desc-1) begin
                    dut.u_mem.mem[desc2_base + i*4 + 3] = (32'h0000_9000 + (i+1)*16) | (1<<1);
                end else begin
                    dut.u_mem.mem[desc2_base + i*4 + 3] = 32'h0 | (1<<1) | (1<<0);
                end
            end
            // clear IRQ sticky before starting
            write_reg(32'h0000_0034, 32'h0);
            // program new descriptor pointer and enable descriptor mode (re-using descriptor registers)
            write_reg(32'h0000_0028, 32'h0000_9000);
            write_reg(32'h0000_0030, 32'h1);
            // start DMA
            write_reg(32'h0000_0024, 32'h1);
            // for each descriptor, wait for IRQ and verify that destination data is written, then clear IRQ
            all_ok = 1;
            for (i = 0; i < n_desc; i++) begin
                // poll for irq status
                kpoll = d_len * 8 + 200;
                got_irq = 0;
                for (k = 0; k < kpoll; k++) begin
                    read_reg(32'h0000_0034, r);
                    $display("%0t: TB poll IRQ read=0x%08h (attempt %0d/%0d)", $time, r, k, kpoll);
                    if (r[0]) begin
                        got_irq = 1;
                        // clear irq sticky
                        write_reg(32'h0000_0034, 32'h0);
                        break;
                    end
                    @(posedge clk);
                end
                if (!got_irq) begin
                    $display("DESC-EACH CASE FAIL: did not observe IRQ for descriptor %0d", i);
                    all_ok = 0;
                    break;
                end
                // verify descriptor i destination
                d_dst_idx = (32'h0000_8000 + i*64) >> 2;
                for (j = 0; j < d_len; j++) begin
                    expected = 32'hDEAD_0000 + i*16 + j;
                    got = dut.u_mem.mem[d_dst_idx + j];
                    if (got !== expected) begin
                        $display("DESC-EACH CASE FAIL: mismatch at desc %0d word %0d: got 0x%08h expected 0x%08h", i, j, got, expected);
                        all_ok = 0;
                        break;
                    end
                end
                if (!all_ok) break;
            end
            if (all_ok) begin
                $display("DESC-EACH CASE PASS: per-descriptor IRQs observed and data verified (%0d descriptors)", n_desc);
                pass_count++;
            end else begin
                fail_count++;
            end

            // disable descriptor mode to return to direct DMA operation
            write_reg(32'h0000_0030, 32'h0);
            write_reg(32'h0000_0028, 32'h0);

            // Single-case reproducer for a failing randomized case
            // src=0x000002f4 dst=0x00002c70 words=29
            run_case(32'h0000_02f4, 32'h0000_2c70, 29, passed);
            if (passed) pass_count++; else fail_count++;
            $display("REPRODUCER: single-case done, passed=%0d failed=%0d", pass_count, fail_count);

        $display("TEST SUMMARY: passed=%0d failed=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("SIM DONE");
            $finish;
        end else begin
            $fatal;
        end
    end

endmodule