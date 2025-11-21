module mmu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [47:0] addr,
    output logic        resident
);

    // Minimal MMU model for tests: treat all addresses as resident.
    // This can be extended later with page tables / residency maps.
    assign resident = 1'b1;

endmodule
