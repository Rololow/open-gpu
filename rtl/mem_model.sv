// Simple behavioral memory model (word-addressable 32-bit words)
module mem_model #(
    parameter int MEM_WORDS = 65536
) (
    input  logic          clk,
    input  logic          rst_n,

    // Read port
    input  logic          read_en,
    input  logic [31:0]   read_addr, // word index
    output logic [31:0]   read_data,

    // Write port
    input  logic          write_en,
    input  logic [31:0]   write_addr, // word index
    input  logic [31:0]   write_data
);

    // Memory storage (accessible hierarchically for testbench initialization)
    logic [31:0] mem [0:MEM_WORDS-1];

    logic [31:0] read_data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data_reg <= 32'd0;
        end else begin
            // synchronous write
            if (write_en) begin
                if (write_addr < MEM_WORDS)
                    mem[write_addr] <= write_data;
                $display("%0t: MEM_MODEL write addr=%0d data=0x%08h", $time, write_addr, write_data);
            end
            // synchronous read: output available next cycle
            if (read_en) begin
                if (read_addr < MEM_WORDS)
                    read_data_reg <= mem[read_addr];
                else
                    read_data_reg <= 32'd0;
                $display("%0t: MEM_MODEL read_en addr=%0d -> sampled=0x%08h", $time, read_addr, mem[read_addr]);
            end
        end
    end

    assign read_data = read_data_reg;

endmodule
