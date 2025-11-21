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

    // Simple DMA/MMU registers (MMIO-mapped)
    logic [63:0] dma_src_reg;
    logic [63:0] dma_dst_reg;
    logic [31:0] dma_len_reg;
    logic        dma_start_reg;

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
                    32'h00000010: dma_src_reg[31:0] <= cfg_req_wdata;
                    32'h00000014: dma_src_reg[63:32] <= cfg_req_wdata;
                    32'h00000018: dma_dst_reg[31:0] <= cfg_req_wdata;
                    32'h0000001C: dma_dst_reg[63:32] <= cfg_req_wdata;
                    32'h00000020: dma_len_reg <= cfg_req_wdata;
                    32'h00000024: dma_start_reg <= cfg_req_wdata[0];
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
    // Memory model instance
    logic mem_read_en;
    logic [31:0] mem_read_addr;
    logic [31:0] mem_read_data;
    logic mem_read_valid;
    logic mem_write_en;
    logic [31:0] mem_write_addr;
    logic [31:0] mem_write_data;
    // Instantiate with DEBUG enabled temporarily for tracing
    mem_model #(.DEBUG(1)) u_mem (.clk(clk), .rst_n(rst_n), .read_en(mem_read_en), .read_addr(mem_read_addr), .read_data(mem_read_data), .read_valid(mem_read_valid), .write_en(mem_write_en), .write_addr(mem_write_addr), .write_data(mem_write_data));

    dma #(.DEBUG(1)) u_dma (.clk(clk), .rst_n(rst_n), .start(dma_start_reg), .src_addr(dma_src_reg), .dst_addr(dma_dst_reg), .len(dma_len_reg), .src_resident(mmu_src_resident), .dst_resident(mmu_dst_resident), .done(dma_done), .mem_read_en(mem_read_en), .mem_read_addr(mem_read_addr), .mem_read_data(mem_read_data), .mem_read_valid(mem_read_valid), .mem_write_en(mem_write_en), .mem_write_addr(mem_write_addr), .mem_write_data(mem_write_data));

    // CFG response: reflect DMA status for simple interaction
    assign cfg_resp_valid = cfg_req_valid; // simple echo
    assign cfg_resp_rdata = (cfg_req_addr == 32'h0000002C) ? {31'b0, dma_done} : 32'b0;


endmodule
