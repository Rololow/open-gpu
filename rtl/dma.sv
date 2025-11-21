module dma (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [63:0] src_addr,
    input  logic [63:0] dst_addr,
    input  logic [31:0] len,
    input  logic        src_resident,
    input  logic        dst_resident,
    output logic        done
);

    typedef enum logic [1:0] {IDLE = 2'b00, BUSY = 2'b01, DONE = 2'b10} state_t;
    state_t state;
    logic [31:0] counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            done    <= 1'b0;
            counter <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start && src_resident && dst_resident) begin
                        // capture length and start transfer simulation
                        counter <= len;
                        if (len == 32'd0)
                            state <= DONE;
                        else
                            state <= BUSY;
                    end
                end
                BUSY: begin
                    if (counter == 32'd0) begin
                        state <= DONE;
                    end else begin
                        counter <= counter - 32'd1;
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
