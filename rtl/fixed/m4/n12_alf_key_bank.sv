`timescale 1ns/1ps
`default_nettype none

// One logical 1R1W key service.  The bank bit is the high address bit, leaving
// four unused rows between the 28 ENC and 28 DEC entries.  Address formation
// is therefore only a concatenation, never a configuration-dependent cone.
module n12_alf_key_bank (
    input  logic         clk_i,
    input  logic         rst_ni,
    input  logic         invalidate_i,
    input  logic         read_enable_i,
    input  logic         read_bank_i,
    input  logic [4:0]   read_index_i,
    output logic [127:0] current_key_o,
    output logic         current_valid_o,
    output logic         current_bank_o,
    output logic [4:0]   current_index_o,
    input  logic         write_enable_i,
    input  logic         write_bank_i,
    input  logic [4:0]   write_index_i,
    input  logic [127:0] write_data_i
);
    (* ram_style = "block" *) logic [127:0] storage [0:63];
    logic [5:0] read_address;
    logic [5:0] write_address;

    assign read_address = {read_bank_i, read_index_i};
    assign write_address = {write_bank_i, write_index_i};

    // The memory process has no reset.  Resetting either the array or its data
    // output prevents portable BRAM/SRAM inference; validity is reset below.
    always_ff @(posedge clk_i) begin
        if (write_enable_i)
            storage[write_address] <= write_data_i;
        if (read_enable_i)
            current_key_o <= storage[read_address];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            current_valid_o <= 1'b0;
            current_bank_o <= 1'b0;
            current_index_o <= 5'd0;
        end else begin
            if (invalidate_i)
                current_valid_o <= 1'b0;
            if (read_enable_i) begin
                current_valid_o <= 1'b1;
                current_bank_o <= read_bank_i;
                current_index_o <= read_index_i;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk_i) begin
        if (read_enable_i && write_enable_i &&
            read_bank_i == write_bank_i && read_index_i == write_index_i)
            $fatal(1, "key-bank same-address read/write is outside the portable contract");
    end
`endif
endmodule

`default_nettype wire
