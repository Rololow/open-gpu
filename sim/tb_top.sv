`timescale 1ns/1ps
module tb_top();
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

    // Test sequence: program DMA registers and wait for done
    initial begin
        // local declarations must appear before statements for Questa/ModelSim
        int timeout;
        int i;
        logic [31:0] r;

        rst_n = 0;
        cfg_req_valid = 0;
        cfg_req_addr = 0;
        cfg_req_wdata = 0;
        #100;
        rst_n = 1;
        #100;

        // Program DMA registers (src/dst low/high, len)
        write_reg(32'h0000_0010, 32'h0000_1000); // src low
        write_reg(32'h0000_0014, 32'h0000_0000); // src high
        write_reg(32'h0000_0018, 32'h0000_2000); // dst low
        write_reg(32'h0000_001C, 32'h0000_0000); // dst high
        write_reg(32'h0000_0020, 32'd16);        // len (small transfer)

        // start DMA (pulse)
        write_reg(32'h0000_0024, 32'h1);

        // poll for done (addr 0x2C) with timeout
        timeout = 200; // cycles
        for (i = 0; i < timeout; i++) begin
            read_reg(32'h0000_002C, r);
            if (r[0]) begin
                $display("TEST PASS: DMA done seen at cycle %0d", i);
                $display("SIM DONE");
                $finish;
            end
            // wait a clock before next poll
            @(posedge clk);
        end

        $display("TEST FAIL: DMA did not complete within %0d cycles", timeout);
        $fatal;
    end

endmodule
