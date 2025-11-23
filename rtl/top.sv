// Top-level template for Open-GPU project
// Minimal skeleton: parameters, clocks, reset, and placeholder interfaces

module top #(
    parameter ADDR_WIDTH = 48,
    parameter DATA_WIDTH = 64
) (
    input  logic clk,
    input  logic rst_n,

    // Simple MMIO / configuration interface (AXI-lite like simplified)
    input  logic cfg_req_valid,
    input  logic [31:0] cfg_req_addr,
    input  logic [31:0] cfg_req_wdata,
    output logic cfg_resp_valid,
    output logic [31:0] cfg_resp_rdata
);

    // import package config for DEBUG and other globals
    import config_pkg::*;
    // Simple DMA/MMU registers (MMIO-mapped)
    logic [63:0] dma_src_reg;
    logic [63:0] dma_dst_reg;
    logic [31:0] dma_len_reg;
    logic        dma_start_reg;
    // Descriptor-mode registers
    logic [31:0] dma_desc_ptr_reg; // byte address of descriptor table
    logic        dma_desc_mode_reg; // 1 = descriptor mode
    // IRQ status from DMA (sticky)
    logic        dma_irq;
    logic        irq_status_reg;

    // cfg register write handling (very small MMIO model)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_src_reg  <= 64'd0;
            dma_dst_reg  <= 64'd0;
            dma_len_reg  <= 32'd0;
            dma_start_reg<= 1'b0;
        end else begin
            if (cfg_req_valid) begin
                unique case (cfg_req_addr)
                    32'h00000010: begin
                        dma_src_reg[31:0] <= cfg_req_wdata;
                        $display("TOP: cfg write SRC_LO=0x%08h at %0t", cfg_req_wdata, $time);
                    end
                    32'h00000014: begin
                        dma_src_reg[63:32] <= cfg_req_wdata;
                        $display("TOP: cfg write SRC_HI=0x%08h at %0t", cfg_req_wdata, $time);
                    end
                    32'h00000018: begin
                        dma_dst_reg[31:0] <= cfg_req_wdata;
                        $display("TOP: cfg write DST_LO=0x%08h at %0t", cfg_req_wdata, $time);
                    end
                    32'h0000001C: begin
                        dma_dst_reg[63:32] <= cfg_req_wdata;
                        $display("TOP: cfg write DST_HI=0x%08h at %0t", cfg_req_wdata, $time);
                    end
                    32'h00000020: begin
                        dma_len_reg <= cfg_req_wdata;
                        $display("TOP: cfg write LEN=0x%08h at %0t", cfg_req_wdata, $time);
                    end
                    32'h00000024: begin
                        dma_start_reg <= cfg_req_wdata[0];
                        if (cfg_req_wdata[0]) $display("TOP: cfg write START=1 at %0t", $time);
                        else $display("TOP: cfg write START=0 at %0t", $time);
                    end
                    32'h00000028: begin
                        dma_desc_ptr_reg <= cfg_req_wdata;
                        $display("TOP: cfg write DESC_PTR=0x%08h at %0t", cfg_req_wdata, $time);
                    end
                    32'h00000030: begin
                        dma_desc_mode_reg <= cfg_req_wdata[0];
                        $display("TOP: cfg write DESC_MODE=%0d at %0t", cfg_req_wdata[0], $time);
                    end
                    32'h00000034: begin
                        // write to clear or set IRQ status (bit0)
                        irq_status_reg <= cfg_req_wdata[0];
                        $display("TOP: cfg write IRQ_STATUS=%0d at %0t", cfg_req_wdata[0], $time);
                    end
                    default: ;
                endcase
            end
            // clear start after one cycle (edge-triggered start)
            if (dma_start_reg)
                dma_start_reg <= 1'b0;
        end
    end

    // Instantiate MMU
    logic mmu_src_resident;
    logic mmu_dst_resident;
    mmu u_mmu_src (.clk(clk), .rst_n(rst_n), .addr(dma_src_reg[47:0]), .resident(mmu_src_resident));
    mmu u_mmu_dst (.clk(clk), .rst_n(rst_n), .addr(dma_dst_reg[47:0]), .resident(mmu_dst_resident));

    // Instantiate DMA
    logic dma_done;
    // Memory model instance signals (top-side)
    logic mem_read_en;
    logic [31:0] mem_read_addr;
    logic [31:0] mem_read_data;
    logic mem_read_valid;
    logic mem_write_en;
    logic [31:0] mem_write_addr;
    logic [31:0] mem_write_data;
    // DMA-driven memory request wires (from DMA)
    logic dma_mem_read_en;
    logic [31:0] dma_mem_read_addr;

    // Descriptor-read handshake wires between DMA and top
    logic dma_desc_read_req;
    logic [31:0] dma_desc_read_addr;
    logic dma_desc_read_ack;
    logic [31:0] dma_desc_read_data;

    // Instantiate memory and DMA; use package defaults for DEBUG and pipeline depth
    mem_model u_mem (.clk(clk), .rst_n(rst_n), .read_en(mem_read_en), .read_addr(mem_read_addr), .read_data(mem_read_data), .read_valid(mem_read_valid), .write_en(mem_write_en), .write_addr(mem_write_addr), .write_data(mem_write_data));

    dma u_dma (.clk(clk), .rst_n(rst_n), .start(dma_start_reg), .src_addr(dma_src_reg), .dst_addr(dma_dst_reg), .len(dma_len_reg), .desc_mode(dma_desc_mode_reg), .desc_ptr(dma_desc_ptr_reg), .src_resident(mmu_src_resident), .dst_resident(mmu_dst_resident), .done(dma_done), .irq(dma_irq), .mem_read_en(dma_mem_read_en), .mem_read_addr(dma_mem_read_addr), .mem_read_data(mem_read_data), .mem_read_valid(mem_read_valid), .mem_write_en(mem_write_en), .mem_write_addr(mem_write_addr), .mem_write_data(mem_write_data), .desc_read_req(dma_desc_read_req), .desc_read_addr(dma_desc_read_addr), .desc_read_ack(dma_desc_read_ack), .desc_read_data(dma_desc_read_data));

    // CFG response: reflect DMA status for simple interaction
    assign cfg_resp_valid = cfg_req_valid; // simple echo
    assign cfg_resp_rdata = (cfg_req_addr == 32'h0000002C) ? {31'b0, dma_done} : ((cfg_req_addr == 32'h00000034) ? {31'b0, irq_status_reg} : 32'b0);

    // latch IRQ status sticky from DMA
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_status_reg <= 1'b0;
        end else begin
            // once DMA asserts irq, latch it until cleared via MMIO write
            if (dma_irq) begin
                irq_status_reg <= 1'b1;
                $display("%0t: TOP: IRQ latched from DMA (dma_irq=%0b)", $time, dma_irq);
            end
        end
    end

    // Bridge descriptor-read requests into the mem_model (single-port)
    // We sample the combinational `dma_desc_read_req` and latch the address
    // to present a stable read to the mem_model. When mem_model returns
    // `mem_read_valid`, we route the data back to DMA as an ack/data pair.
    logic desc_req_latched;
    logic [31:0] desc_addr_latched;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            desc_req_latched <= 1'b0;
            desc_addr_latched <= 32'd0;
            dma_desc_read_ack <= 1'b0;
            dma_desc_read_data <= 32'd0;
        end else begin
            // default: no ack unless mem_model produced valid data this cycle
            dma_desc_read_ack <= 1'b0;

            // if DMA asserted a request combinationally, latch it so mem_model
            // sees a stable read_en/read_addr on the following posedge
            if (dma_desc_read_req)
            begin
                desc_req_latched <= 1'b1;
                desc_addr_latched <= dma_desc_read_addr;
            end

            // when mem_model returns valid data and we were servicing a
            // descriptor request, forward it back to DMA and clear the latch
            if (mem_read_valid && desc_req_latched) begin
                dma_desc_read_ack  <= 1'b1;
                dma_desc_read_data <= mem_read_data;
                desc_req_latched <= 1'b0;
            end
        end
    end

    // Multiplex mem_model read port between descriptor-reads and normal DMA reads
    always_comb begin
        mem_read_en = desc_req_latched ? 1'b1 : dma_mem_read_en;
        mem_read_addr = desc_req_latched ? desc_addr_latched : dma_mem_read_addr;
    end

    // Simple monitor to trace memory read handshakes for debug
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end else begin
            if (cfg_req_valid && DEBUG) ; // keep quiet when cfg accesses are being printed elsewhere
            // print mem read interface each cycle for correlation
            $display("%0t: TOP MON mem_read_en=%b mem_read_addr=%0d mem_read_valid=%b", $time, mem_read_en, mem_read_addr, mem_read_valid);
            // debug descriptor-read handshake signals
            if (dma_desc_read_req) $display("%0t: TOP MON dma_desc_read_req=1 addr=%0d", $time, dma_desc_read_addr);
            if (desc_req_latched)    $display("%0t: TOP MON desc_req_latched=1 latched_addr=%0d", $time, desc_addr_latched);
            if (dma_desc_read_ack)   $display("%0t: TOP MON dma_desc_read_ack data=0x%08h", $time, dma_desc_read_data);
        end
    end


endmodule
