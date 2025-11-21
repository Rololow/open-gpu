module dma (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [63:0] src_addr,
    input  logic [63:0] dst_addr,
    input  logic [31:0] len,
    input  logic        src_resident,
    input  logic        dst_resident,
    output logic        done,

    // Memory interface (single-port behavioral mem_model instance in top)
    output logic         mem_read_en,
    output logic [31:0]  mem_read_addr,
    input  logic [31:0]  mem_read_data,
    output logic         mem_write_en,
    output logic [31:0]  mem_write_addr,
    output logic [31:0]  mem_write_data
);

    typedef enum logic [1:0] {IDLE = 2'b00, BUSY = 2'b01, DONE = 2'b10} state_t;
    state_t state;
    logic [31:0] counter;

    // DMA state/indices
    logic [31:0] src_base_idx;
    logic [31:0] dst_base_idx;
    // running indices and counters
    logic [31:0] read_index;
    logic [31:0] write_index;
    logic [31:0] remain;

    // memory interface signals internal registers
    logic pending_read; // read issued, data not yet captured
    logic data_ready;   // read data captured and ready to write
    logic [31:0] saved_read_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            done    <= 1'b0;
            // reset memory interface flags and indices
            pending_read <= 1'b0;
            data_ready   <= 1'b0;
            saved_read_data <= 32'd0;
            mem_read_en <= 1'b0;
            mem_write_en <= 1'b0;
            remain <= 32'd0;
            read_index <= 32'd0;
            write_index <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    mem_read_en  <= 1'b0;
                    mem_write_en <= 1'b0;
                    pending_read <= 1'b0;
                    data_ready   <= 1'b0;
                    if (start && src_resident && dst_resident) begin
                        // capture length and start transfer simulation
                        remain <= len;
                        // capture base indices (word addressing)
                        src_base_idx <= src_addr[31:2];
                        dst_base_idx <= dst_addr[31:2];
                        read_index  <= src_addr[31:2];
                        write_index <= dst_addr[31:2];
                        if (len == 32'd0)
                            state <= DONE;
                        else
                            state <= BUSY;
                    end
                end
                BUSY: begin
                    // default: no read/write unless we set below
                    mem_read_en  <= 1'b0;
                    mem_write_en <= 1'b0;

                    // if no pending read and there are words remaining, issue a read
                    if (!pending_read && (remain != 32'd0)) begin
                        mem_read_en   <= 1'b1;
                        mem_read_addr <= read_index;
                        pending_read  <= 1'b1;
                        // debug
                        $display("%0t: DMA issue read addr=%0d remain=%0d", $time, read_index, remain);
                        // advance read_index for next issue
                        read_index    <= read_index + 32'd1;
                    end else if (pending_read && !data_ready) begin
                        // the read issued in previous cycle now has valid data
                        saved_read_data <= mem_read_data;
                        data_ready <= 1'b1;
                        mem_read_en <= 1'b0;
                    end else if (data_ready) begin
                        // write the captured data to destination
                        mem_write_en   <= 1'b1;
                        mem_write_addr <= write_index;
                        mem_write_data <= saved_read_data;
                        $display("%0t: DMA write addr=%0d data=0x%08h remain=%0d", $time, write_index, saved_read_data, remain);
                        // advance write pointer and consume one word
                        write_index <= write_index + 32'd1;
                        remain <= remain - 32'd1;
                        // clear pipeline flags
                        pending_read <= 1'b0;
                        data_ready   <= 1'b0;
                    end

                    // check for completion: no words remaining and no pending operations
                    if ((remain == 32'd0) && !pending_read && !data_ready) begin
                        state <= DONE;
                    end
                end
                DONE: begin
                    done <= 1'b1;
                    // signal done for one cycle then go to IDLE
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
