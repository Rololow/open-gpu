module dma #(
    parameter bit DEBUG = config_pkg::DEBUG
) (
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
    input  logic         mem_read_valid,
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
    // copy direction: 1 = forward (increasing indices), 0 = backward (decreasing)
    logic dir_forward;

    import config_pkg::*;

    // memory interface signals internal registers
    // Use a small FIFO to pair each issued read with its destination write
    // This avoids races when multiple outstanding reads are in-flight.
    int fifo_head;
    int fifo_tail;
    int fifo_count;
    logic [31:0] pending_write_fifo [config_pkg::DMA_PIPELINE_DEPTH-1:0];

    logic done_sticky;

    always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            state   <= IDLE;
            done    <= 1'b0;
            done_sticky <= 1'b0;
            // reset FIFO and memory interface flags and indices
            fifo_head <= 0;
            fifo_tail <= 0;
            fifo_count <= 0;
            mem_read_en <= 1'b0;
            mem_write_en <= 1'b0;
            remain <= 32'd0;
            read_index <= 32'd0;
            write_index <= 32'd0;
            dir_forward <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    // clear transient done for new starts
                    // avoid reporting a stale 'done' in the same cycle as a new 'start' pulse
                    done <= done_sticky & ~start;
                    mem_read_en  <= 1'b0;
                    mem_write_en <= 1'b0;
                    if (start && src_resident && dst_resident) begin
                        // capture length and start transfer simulation
                        remain <= len;
                        // capture base indices (word addressing)
                        src_base_idx <= src_addr[31:2];
                        dst_base_idx <= dst_addr[31:2];
                        // determine overlap and direction (memmove semantics)
                        if ((dst_addr[31:2] > src_addr[31:2]) && ((src_addr[31:2] + len) > dst_addr[31:2])) begin
                            // overlapping and dest higher -> copy backwards
                            dir_forward <= 1'b0;
                            read_index <= src_addr[31:2] + len - 32'd1;
                            write_index <= dst_addr[31:2] + len - 32'd1;
                        end else begin
                            dir_forward <= 1'b1;
                            read_index <= src_addr[31:2];
                            write_index <= dst_addr[31:2];
                        end
                        // clear sticky done when starting a new transfer
                        done_sticky <= 1'b0;
                        // reset FIFO state for new transfer
                        fifo_head <= 0;
                        fifo_tail <= 0;
                        fifo_count <= 0;
                        if (len == 32'd0)
                            begin
                                // zero-length: signal done immediately (sticky)
                                done_sticky <= 1'b1;
                                state <= IDLE;
                            end
                        else
                            state <= BUSY;
                    end
                end
                BUSY: begin
                        // default: no read/write unless we set below
                        mem_read_en  <= 1'b0;
                        mem_write_en <= 1'b0;

                        // First, if the memory produced a read result this cycle, consume it
                        if (mem_read_valid && (fifo_count > 0)) begin
                            // pop the oldest pending write address and write data to it immediately
                            fifo_head <= (fifo_head + 1) % config_pkg::DMA_PIPELINE_DEPTH;
                            fifo_count <= fifo_count - 1;

                            mem_write_en   <= 1'b1;
                            mem_write_addr <= pending_write_fifo[fifo_head];
                            mem_write_data <= mem_read_data;
                            if (DEBUG) $display("%0t: DMA capture data=0x%08h for pending_write_addr=%0d (mem_read_valid)", $time, mem_read_data, pending_write_fifo[fifo_head]);
                            if (DEBUG) $display("%0t: DMA write addr=%0d data=0x%08h remain=%0d (using pending_write_fifo)", $time, pending_write_fifo[fifo_head], mem_read_data, remain);

                            // consume one word
                            remain <= remain - 32'd1;
                            // if this was the last word, move to DONE state so we can wait one cycle
                            if (remain == 32'd1) begin
                                state <= DONE;
                            end
                        end

                        // Next, if we have room in the FIFO and words remaining, issue another read
                        if ((fifo_count < config_pkg::DMA_PIPELINE_DEPTH) && (remain != 32'd0)) begin
                            mem_read_en   <= 1'b1;
                            mem_read_addr <= read_index;
                            // push this read's corresponding write address into FIFO
                            pending_write_fifo[fifo_tail] <= write_index;
                            fifo_tail <= (fifo_tail + 1) % config_pkg::DMA_PIPELINE_DEPTH;
                            fifo_count <= fifo_count + 1;

                            // advance indices for next issue according to direction
                            if (dir_forward) begin
                                read_index    <= read_index + 32'd1;
                                write_index   <= write_index + 32'd1;
                            end else begin
                                read_index    <= read_index - 32'd1;
                                write_index   <= write_index - 32'd1;
                            end
                            if (DEBUG) $display("%0t: DMA issue read addr=%0d pending_fifo_tail=%0d remain=%0d", $time, read_index, fifo_tail, remain);
                        end

                        // check for completion: no words remaining and no pending FIFO entries
                        if ((remain == 32'd0) && (fifo_count == 0)) begin
                            done_sticky <= 1'b1;
                            state <= IDLE;
                        end
                end
                    DONE: begin
                        // one-cycle completion state so the last write can commit in mem_model
                        mem_read_en  <= 1'b0;
                        mem_write_en <= 1'b0;
                        done_sticky <= 1'b1;
                        done <= 1'b1;
                        state <= IDLE;
                    end
                // DONE state removed; completion handled via done_sticky
                default: state <= IDLE;
            endcase
        end
    end
    // `done` is maintained inside the clocked process (driven from done_sticky)
endmodule
