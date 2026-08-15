`timescale 1ns/1ps
`default_nettype none

// Single combinational AES primitive shared by key/tweak setup and data rounds.
// Scheduling and ownership stay in the top level; this module has no state.
// 单个组合 AES 原语由密钥/调整量初始化与数据轮共享；调度和所有权由顶层管理，本模块不保存状态。
module n12_aes_round_lane (
    input  logic [2:0]   mode_i,
    input  logic [127:0] state_i,
    input  logic [127:0] round_key_i,
    output logic [127:0] state_o
);
    import n12_alf_v0_tables_pkg::*;

    localparam logic [2:0] MODE_ENC_ROUND    = 3'd0;
    localparam logic [2:0] MODE_DEC_ROUND    = 3'd1;
    localparam logic [2:0] MODE_ENC_LAST     = 3'd2;
    localparam logic [2:0] MODE_DEC_LAST     = 3'd3;
    localparam logic [2:0] MODE_INV_MIX_ONLY = 3'd4;

    function automatic logic [7:0] gf_mul(
        input logic [7:0] left, input logic [7:0] right);
        logic [7:0] product;
        logic [7:0] multiplicand;
        logic [7:0] multiplier;
        integer index;
        begin
            product = 8'h00;
            multiplicand = left;
            multiplier = right;
            for (index = 0; index < 8; index = index + 1) begin
                if (multiplier[0])
                    product = product ^ multiplicand;
                multiplicand = {multiplicand[6:0], 1'b0} ^
                               (8'h1b & {8{multiplicand[7]}});
                multiplier = multiplier >> 1;
            end
            gf_mul = product;
        end
    endfunction

    function automatic logic [127:0] sub_bytes(
        input logic [127:0] value, input logic inverse);
        logic [127:0] result;
        integer byte_index;
        begin
            result = 128'h0;
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
                result[8*byte_index +: 8] = inverse
                    ? aes_inv_sbox(value[8*byte_index +: 8])
                    : aes_sbox(value[8*byte_index +: 8]);
            sub_bytes = result;
        end
    endfunction

    function automatic logic [127:0] shift_rows(
        input logic [127:0] value, input logic inverse);
        logic [127:0] result;
        integer row;
        integer column;
        integer source_column;
        begin
            result = 128'h0;
            for (row = 0; row < 4; row = row + 1) begin
                for (column = 0; column < 4; column = column + 1) begin
                    if (inverse)
                        source_column = (column - row + 4) % 4;
                    else
                        source_column = (column + row) % 4;
                    result[8*(4*column + row) +: 8] =
                        value[8*(4*source_column + row) +: 8];
                end
            end
            shift_rows = result;
        end
    endfunction

    function automatic logic [127:0] mix_columns(
        input logic [127:0] value, input logic inverse);
        logic [127:0] result;
        logic [7:0] a0;
        logic [7:0] a1;
        logic [7:0] a2;
        logic [7:0] a3;
        integer column;
        begin
            result = 128'h0;
            for (column = 0; column < 4; column = column + 1) begin
                a0 = value[8*(4*column + 0) +: 8];
                a1 = value[8*(4*column + 1) +: 8];
                a2 = value[8*(4*column + 2) +: 8];
                a3 = value[8*(4*column + 3) +: 8];
                if (inverse) begin
                    result[8*(4*column + 0) +: 8] = gf_mul(8'h0e,a0) ^ gf_mul(8'h0b,a1) ^ gf_mul(8'h0d,a2) ^ gf_mul(8'h09,a3);
                    result[8*(4*column + 1) +: 8] = gf_mul(8'h09,a0) ^ gf_mul(8'h0e,a1) ^ gf_mul(8'h0b,a2) ^ gf_mul(8'h0d,a3);
                    result[8*(4*column + 2) +: 8] = gf_mul(8'h0d,a0) ^ gf_mul(8'h09,a1) ^ gf_mul(8'h0e,a2) ^ gf_mul(8'h0b,a3);
                    result[8*(4*column + 3) +: 8] = gf_mul(8'h0b,a0) ^ gf_mul(8'h0d,a1) ^ gf_mul(8'h09,a2) ^ gf_mul(8'h0e,a3);
                end else begin
                    result[8*(4*column + 0) +: 8] = gf_mul(8'h02,a0) ^ gf_mul(8'h03,a1) ^ a2 ^ a3;
                    result[8*(4*column + 1) +: 8] = a0 ^ gf_mul(8'h02,a1) ^ gf_mul(8'h03,a2) ^ a3;
                    result[8*(4*column + 2) +: 8] = a0 ^ a1 ^ gf_mul(8'h02,a2) ^ gf_mul(8'h03,a3);
                    result[8*(4*column + 3) +: 8] = gf_mul(8'h03,a0) ^ a1 ^ a2 ^ gf_mul(8'h02,a3);
                end
            end
            mix_columns = result;
        end
    endfunction

    logic [127:0] substituted;
    logic [127:0] shifted;
    logic [127:0] mixed;

    always_comb begin
        substituted = 128'h0;
        shifted = 128'h0;
        mixed = 128'h0;
        state_o = 128'h0;
        case (mode_i)
            MODE_ENC_ROUND: begin
                substituted = sub_bytes(state_i, 1'b0);
                shifted = shift_rows(substituted, 1'b0);
                mixed = mix_columns(shifted, 1'b0);
                state_o = mixed ^ round_key_i;
            end
            MODE_DEC_ROUND: begin
                shifted = shift_rows(state_i, 1'b1);
                substituted = sub_bytes(shifted, 1'b1);
                mixed = mix_columns(substituted, 1'b1);
                state_o = mixed ^ round_key_i;
            end
            MODE_ENC_LAST: begin
                substituted = sub_bytes(state_i, 1'b0);
                shifted = shift_rows(substituted, 1'b0);
                mixed = shifted;
                state_o = shifted ^ round_key_i;
            end
            MODE_DEC_LAST: begin
                // Match clean-room aes_dec_last_round exactly.
                shifted = shift_rows(state_i ^ round_key_i, 1'b1);
                substituted = sub_bytes(shifted, 1'b1);
                mixed = substituted;
                state_o = substituted;
            end
            MODE_INV_MIX_ONLY: begin
                mixed = mix_columns(state_i, 1'b1);
                state_o = mixed;
            end
            default: begin
                state_o = 128'h0;
            end
        endcase
    end
endmodule

`default_nettype wire
