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
        bit all_ok;

        rst_n = 0;
        cfg_req_valid = 0;
        cfg_req_addr = 0;
        cfg_req_wdata = 0;
        #100;
        rst_n = 1;
        #100;

        pass_count = 0;
        fail_count = 0;

        // Focused debug: single basic 16-word transfer
        num_words = 16;
        src_idx = 32'h0000_1000 >> 2;
        dst_idx = 32'h0000_2000 >> 2;
        // initialize source/dest and print first words for debug
        for (i = 0; i < num_words; i++) begin
            dut.u_mem.mem[src_idx + i] = 32'h5A5A_0000 + i;
            dut.u_mem.mem[dst_idx + i] = 32'h0;
        end
        $display("PRE-START MEM SRC[0]=0x%08h SRC[1]=0x%08h DST[0]=0x%08h", dut.u_mem.mem[src_idx], dut.u_mem.mem[src_idx+1], dut.u_mem.mem[dst_idx]);

        run_case(32'h0000_1000, 32'h0000_2000, num_words, passed);
        if (passed) pass_count++; else fail_count++;

        // print result words
        for (j = 0; j < num_words; j++) begin
            $display("POST: dst[%0d]=0x%08h", j, dut.u_mem.mem[dst_idx + j]);
        end

        $display("TEST SUMMARY: passed=%0d failed=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("SIM DONE");
            $finish;
        end else begin
            $fatal;
        end
    end

endmodule