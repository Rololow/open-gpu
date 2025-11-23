module dma #(
    parameter bit DEBUG = config_pkg::DEBUG
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [63:0] src_addr,
    input  logic [63:0] dst_addr,
    input  logic [31:0] len,
    // Descriptor mode: when set, DMA will fetch descriptors from memory
    input  logic        desc_mode,
    input  logic [31:0] desc_ptr, // byte address of first descriptor
    input  logic        src_resident,
    input  logic        dst_resident,
    output logic        done,
    // IRQ output: pulses when descriptor requests IRQ on completion
    output logic        irq,

    // Memory interface (single-port behavioral mem_model instance in top)
    output logic         mem_read_en,
    output logic [31:0]  mem_read_addr,
    input  logic [31:0]  mem_read_data,
    input  logic         mem_read_valid,
    output logic         mem_write_en,
    output logic [31:0]  mem_write_addr,
    output logic [31:0]  mem_write_data,

    // Descriptor fetch request/ack handshake (race-free)
    // dma asserts `desc_read_req` combinationally with `desc_read_addr`.
    // top samples that into the memory model; when the memory returns data
    // top asserts `desc_read_ack` and provides `desc_read_data` next cycle.
    output logic         desc_read_req,
    output logic [31:0]  desc_read_addr,
    input  logic         desc_read_ack,
    input  logic [31:0]  desc_read_data
);

    typedef enum logic [1:0] {IDLE = 2'b00, FETCH_DESC = 2'b01, BUSY = 2'b10, DONE = 2'b11} state_t;
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
    // extend irq for a couple cycles so the top-level can sample it reliably
    logic [1:0] irq_extend;
    // Descriptor fetch temporary storage (4 words per descriptor)
    logic [31:0] desc_word [0:3];
    logic [1:0]  desc_phase; // which word index (0..3) being fetched
    logic [31:0] cur_desc_ptr; // byte addr of current descriptor
    logic [31:0] next_desc_ptr;
    logic [63:0] cur_src_addr;
    logic [63:0] cur_dst_addr;
    logic [31:0] cur_len_words;
    // descriptor flags parsed from desc_word[3]
    // New layout: bit0=IRQ_ON_COMPLETE, bit1=IRQ_ON_EACH, bits[4:2]=PRIO (3 bits), bits[31:5]=ATTRS (27 bits)
    logic        desc_irq_on_complete;
    logic        desc_irq_on_each;
    logic [2:0]  desc_prio;
    logic [26:0] desc_attrs;
    // indicates current transfer originated from a descriptor fetch
    logic desc_active;

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
                            // default: decrement irq extension and drive irq from it
                                            if (irq_extend != 2'd0)
                                                irq_extend <= irq_extend - 2'd1;
                                            irq <= (irq_extend != 2'd0);
                            // default memory outputs (may be overridden below)
                            mem_read_en  <= 1'b0;
                            mem_write_en <= 1'b0;
              if (DEBUG && start) $display("%0t: DMA sampled start=%b state=%0d src_res=%b dst_res=%b", $time, start, state, src_resident, dst_resident);
            case (state)
                IDLE: begin
                    // clear transient done for new starts
                    // avoid reporting a stale 'done' in the same cycle as a new 'start' pulse
                    done <= done_sticky & ~start;
                    mem_read_en  <= 1'b0;
                    mem_write_en <= 1'b0;
                    // allow descriptor-mode starts even if src/dst residency isn't known
                    if (start && (desc_mode || (src_resident && dst_resident))) begin
                        if (DEBUG) $display("%0t: DMA IDLE saw start src_addr=0x%08h dst_addr=0x%08h len=%0d desc_mode=%0b", $time, src_addr, dst_addr, len, desc_mode);
                        // start a descriptor-driven transfer if requested
                        if (desc_mode) begin
                            // initialize descriptor fetch
                            cur_desc_ptr <= desc_ptr;
                            desc_active <= 1'b0;
                            desc_phase <= 2'd0;
                            // clear sticky done when starting a new transfer
                            done_sticky <= 1'b0;
                            // reset FIFO state for new transfer
                            fifo_head <= 0;
                            fifo_tail <= 0;
                            fifo_count <= 0;
                            state <= FETCH_DESC;
                        end else begin
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
                end
                FETCH_DESC: begin
                    // Descriptor format (word-addressed, 4 words):
                    // word0: src_addr (byte)
                    // word1: dst_addr (byte)
                    // word2: len (number of words)
                    // word3: next_desc_ptr (byte addr), 0==end
                    mem_read_en <= 1'b0;
                    mem_write_en <= 1'b0;
                    if (DEBUG) $display("%0t: DMA FETCH_DESC cur_desc_ptr=0x%08h desc_phase=%0d desc_mode=%b mem_read_en(old)=%b mem_read_valid=%b mem_read_addr=%0d desc_read_req=%b", $time, cur_desc_ptr, desc_phase, desc_mode, mem_read_en, mem_read_valid, mem_read_addr, desc_read_req);
                    // If descriptor mode has been disabled externally, abort descriptor fetch
                    if (!desc_mode) begin
                        // abort and return to IDLE
                        desc_phase <= 2'd0;
                        cur_desc_ptr <= 32'd0;
                        mem_read_en <= 1'b0;
                        state <= IDLE;
                    end
                    // descriptor read is performed via request/ack handshake with `top`.
                    $display("%0t: FETCH_DESC check: phase=%0d desc_read_req=%b", $time, desc_phase, desc_read_req);
                    // capture descriptor word when top/mem_model acknowledges it
                    if (desc_read_ack) begin
                        desc_word[desc_phase] <= desc_read_data;
                        if (DEBUG) $display("%0t: DMA desc read data[%0d]=0x%08h (via ack)", $time, desc_phase, desc_read_data);
                        // Advance to next phase for multi-word descriptor fetches.
                        // When we receive the ack for the 4th word (phase==3) we
                        // assemble the descriptor and transition to BUSY. For
                        // earlier phases simply increment the phase counter so
                        // subsequent combinational requests fetch the next word.
                        if (desc_phase != 2'd3) begin
                            desc_phase <= desc_phase + 2'd1;
                        end
                        // If this was the final (4th) word of the descriptor, assemble
                        // the descriptor using the three previously-captured words and
                        // the freshly-returned word (`desc_read_data`) for word3.
                        if (desc_phase == 2'd3) begin
                            cur_src_addr <= {32'd0, desc_word[0]};
                            cur_dst_addr <= {32'd0, desc_word[1]};
                            cur_len_words <= desc_word[2];
                                next_desc_ptr <= desc_read_data;
                                // parse flags from the freshly-read word3
                                desc_irq_on_complete <= desc_read_data[0];
                                desc_irq_on_each <= desc_read_data[1];
                                desc_prio <= desc_read_data[4:2];
                                desc_attrs <= desc_read_data[31:5];
                                    desc_active <= 1'b1;
                            if (DEBUG) $display("%0t: DMA assembled desc src=0x%08h dst=0x%08h len=%0d next=0x%08h irq_each=%b irq_comp=%b (using read_data)", $time, desc_word[0], desc_word[1], desc_word[2], desc_read_data, desc_read_data[1], desc_read_data[0]);
                            // setup transfer indices like normal start (word addressing)
                            remain <= desc_word[2];
                            src_base_idx <= desc_word[0][31:2];
                            dst_base_idx <= desc_word[1][31:2];
                            // choose direction (memmove semantics)
                            if ((desc_word[1][31:2] > desc_word[0][31:2]) && ((desc_word[0][31:2] + desc_word[2]) > desc_word[1][31:2])) begin
                                dir_forward <= 1'b0;
                                read_index <= desc_word[0][31:2] + desc_word[2] - 32'd1;
                                write_index <= desc_word[1][31:2] + desc_word[2] - 32'd1;
                            end else begin
                                dir_forward <= 1'b1;
                                read_index <= desc_word[0][31:2];
                                write_index <= desc_word[1][31:2];
                            end
                            // clear FIFO and go to BUSY to perform transfer
                            fifo_head <= 0;
                            fifo_tail <= 0;
                            fifo_count <= 0;
                            desc_phase <= 2'd0;
                            state <= BUSY;
                        end
                    end
                end
                BUSY: begin
                    // default: no read/write unless we set below
                        mem_read_en  <= 1'b0;
                        mem_write_en <= 1'b0;

                    if (DEBUG) $display("%0t: DMA BUSY state remain=%0d fifo_count=%0d read_index=%0d write_index=%0d fifo_head=%0d fifo_tail=%0d mem_read_valid=%0b mem_read_data=0x%08h cur_len_words=%0d desc_active=%b next_desc=0x%08h", $time, remain, fifo_count, read_index, write_index, fifo_head, fifo_tail, mem_read_valid, mem_read_data, cur_len_words, desc_active, next_desc_ptr);

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

                            // consume one completed word (we decremented `remain` at issue time)
                            // (no change to `remain` here)
                            // debug: when we consume the last word, print final FIFO/remaining status
                            if (DEBUG && remain <= 32'd1) begin
                                $display("%0t: DMA about to finish: remain(before consume)=%0d fifo_count(after pop)=%0d desc_active=%b next_desc_ptr=0x%08h", $time, remain, fifo_count-1, desc_active, next_desc_ptr);
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

                            // decrement remain at issue-time so we do not issue more
                            // reads than requested by the descriptor/value of `remain`.
                            // This prevents issuing addresses beyond the transfer.
                            remain <= remain - 32'd1;

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
                        else begin
                            if (DEBUG && (remain != 32'd0) && (fifo_count >= config_pkg::DMA_PIPELINE_DEPTH)) begin
                                $display("%0t: DMA stall - FIFO full: remain=%0d fifo_count=%0d", $time, remain, fifo_count);
                            end
                        end

                        // check for completion: no words remaining and no pending FIFO entries
                        if ((remain == 32'd0) && (fifo_count == 0)) begin
                            // completion-time diagnostics to help locate why IRQs aren't firing
                            $display("%0t: DMA COMPLETION check: desc_active=%b next_desc_ptr=0x%08h desc_irq_on_each=%b desc_irq_on_complete=%b desc_mode=%b remain=%0d fifo_count=%0d read_index=%0d write_index=%0d fifo_head=%0d fifo_tail=%0d", $time, desc_active, next_desc_ptr, desc_irq_on_each, desc_irq_on_complete, desc_mode, remain, fifo_count, read_index, write_index, fifo_head, fifo_tail);
                            if (DEBUG) $display("%0t: DMA completion (DEBUG) - traced keys: cur_src_addr=0x%016h cur_dst_addr=0x%016h cur_len_words=%0d", $time, cur_src_addr, cur_dst_addr, cur_len_words);
                            // if this transfer came from a descriptor, and there's a next descriptor, chain
                            if (desc_active) begin
                                if ((next_desc_ptr != 32'd0) && desc_mode) begin
                                    // start fetching next descriptor
                                    // if descriptor requested IRQ on each descriptor, pulse it now (one cycle)
                                    if (desc_irq_on_each) begin
                                            irq_extend <= 2'd2;
                                            $display("%0t: DMA IRQ ASSERT (EACH) — desc_prio=%0d attrs=0x%07h next_desc_ptr=0x%08h cur_desc_ptr=0x%08h", $time, desc_prio, desc_attrs, next_desc_ptr, cur_desc_ptr);
                                            if (DEBUG) $display("%0t: DMA descriptor completed (each) -> irq asserted (prio=%0d attrs=0x%07h)", $time, desc_prio, desc_attrs);
                                        end
                                    cur_desc_ptr <= next_desc_ptr;
                                    desc_phase <= 2'd0;
                                    desc_active <= 1'b0; // will be set again when next descriptor is assembled
                                    state <= FETCH_DESC;
                                end else begin
                                    // end of chain
                                    // pulse irq if requested by the descriptor (one-cycle)
                                    if (desc_irq_on_complete) begin
                                        irq_extend <= 2'd2;
                                        $display("%0t: DMA IRQ ASSERT (COMPLETE) — desc_prio=%0d attrs=0x%07h next_desc_ptr=0x%08h cur_desc_ptr=0x%08h", $time, desc_prio, desc_attrs, next_desc_ptr, cur_desc_ptr);
                                        if (DEBUG) $display("%0t: DMA descriptor completed -> irq asserted (prio=%0d attrs=0x%07h)", $time, desc_prio, desc_attrs);
                                    end
                                    done_sticky <= 1'b1;
                                    desc_active <= 1'b0;
                                    state <= IDLE;
                                end
                            end else begin
                                done_sticky <= 1'b1;
                                state <= IDLE;
                            end
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
    // Combinational request/addr for descriptor-read handshake
    always_comb begin
        // default: not requesting
        desc_read_req  = 1'b0;
        desc_read_addr = 32'd0;
        // when in FETCH_DESC and we still need words, request the current word
        if (state == FETCH_DESC) begin
            // desc_phase is 2 bits and ranges 0..3; compare against 3 (inclusive)
            // avoid re-issuing a new request in the same cycle the top may be
            // acking the previous request — don't request if `desc_read_ack`
            // is currently asserted. This prevents address/phase races.
            if ((desc_phase <= 2'd3) && !desc_read_ack) begin
                desc_read_req  = 1'b1;
                // present word-index (word-addressed) to memory: byte addr >> 2 + phase
                desc_read_addr = (cur_desc_ptr[31:2] + desc_phase);
            end
        end
    end

    // `done` is maintained inside the clocked process (driven from done_sticky)
endmodule
