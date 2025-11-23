// Simple behavioral memory model (word-addressable 32-bit words)
module mem_model #(
    parameter int MEM_WORDS = config_pkg::MEM_WORDS,
    parameter bit DEBUG = config_pkg::DEBUG
) (
    input  logic          clk,
    input  logic          rst_n,

    // Read port
    input  logic          read_en,
    input  logic [31:0]   read_addr, // word index
    output logic [31:0]   read_data,
    output logic          read_valid,

    // Write port
    input  logic          write_en,
    input  logic [31:0]   write_addr, // word index
    input  logic [31:0]   write_data
);

    import config_pkg::*;

    // Memory storage (accessible hierarchically for testbench initialization)
    logic [31:0] mem [0:MEM_WORDS-1];

    logic [31:0] read_data_reg;
    logic read_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data_reg <= 32'd0;
            read_valid_reg <= 1'b0;
        end else begin
            // synchronous write
            if (write_en) begin
                if (write_addr < MEM_WORDS)
                    mem[write_addr] <= write_data;
                if (DEBUG) $display("%0t: MEM_MODEL write addr=%0d data=0x%08h", $time, write_addr, write_data);
            end
            // synchronous read: output available next cycle
            if (read_en) begin
                // sample address and data into the registered outputs
                if (read_addr < MEM_WORDS)
                    read_data_reg <= mem[read_addr];
                else
                    read_data_reg <= 32'd0;
                // indicate read_data will be valid next cycle
                read_valid_reg <= 1'b1;
                // extra debug: always-print when a read is sampled so it's visible even if other prints are noisy
                $display("%0t: MEM_MODEL sampled read_en addr=%0d -> queued_data=0x%08h read_valid_reg(next)=1", $time, read_addr, mem[read_addr]);
            end else begin
                // indicate no valid data next cycle
                if (read_valid_reg && DEBUG) $display("%0t: MEM_MODEL clearing read_valid (no new read_en)", $time);
                read_valid_reg <= 1'b0;
            end
        end
    end

    assign read_data = read_data_reg;
    assign read_valid = read_valid_reg;

endmodule
