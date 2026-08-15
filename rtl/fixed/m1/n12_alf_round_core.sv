`timescale 1ns/1ps
`default_nettype none

`ifndef FORMAL_TICKET_PREDICATE_ONLY
// Executes ALF data rounds and rejection retries for both cycle-sliding and
// cycle-walking.  candidate_q is committed only after the runtime Q test;
// attempt outputs expose that decision without duplicating the AES lane.
// 执行 cycle-sliding/cycle-walking 数据轮及拒绝重试。candidate_q 只有通过运行时 Q
// 判定后才提交；attempt 接口导出该判定，同时不复制 AES 通路。
module n12_alf_round_core (
    input  logic         clk_i,
    input  logic         rst_ni,
    input  logic         step_i,
    input  logic         active_i,
    input  logic         request_accept_i,
    input  logic         validate_active_i,
    input  logic         start_i,
    input  logic         decrypt_i,
    input  logic         cycle_walking_i,
    input  logic [127:0] input_i,

    output logic         key_prefetch_valid_o,
    output logic         key_prefetch_bank_o,
    output logic [4:0]   key_prefetch_index_o,
    input  logic [127:0] current_key_i,
    input  logic         current_key_valid_i,
    input  logic         current_key_bank_i,
    input  logic [4:0]   current_key_index_i,

    output logic         aes_active_o,
    output logic         aes_decrypt_o,
    output logic         aes_last_o,
    output logic [127:0] aes_state_o,
    output logic [127:0] aes_key_o,
    input  logic [127:0] aes_result_i,

    output logic         attempt_done_o,
    output logic         attempt_accepted_o,
    output logic [4:0]   attempt_segment_o,
    output logic [15:0]  attempt_index_o,
    output logic [4:0]   attempt_first_round_o,
    output logic         data_done_o,
    output logic [127:0] result_o
);
    import n12_alf_v0_tables_pkg::*;

    localparam logic [3:0] FIXED_N = 4'd2;
    localparam logic [2:0] FIXED_T = 3'd0;
    localparam logic [4:0] FIXED_ROUNDS = 5'd20;
    localparam logic [127:0] FIXED_Q =
        128'h00000000000000000000000000010000;
    localparam logic [127:0] FIXED_Q_MINUS_ONE =
        128'h0000000000000000000000000000ffff;

    localparam logic [1:0] ST_ENC_ROUND = 2'd0;
    localparam logic [1:0] ST_DEC_AUX   = 2'd1;
    localparam logic [1:0] ST_DEC_ROUND = 2'd2;
    localparam logic [1:0] ST_DEC_FINAL = 2'd3;

    logic [1:0] state_q;
    logic decrypt_q;
    logic cycle_walking_q;
    logic [4:0] k_q;
    logic [4:0] segment_count_q;
    logic [4:0] segment_q;
    logic [15:0] attempt_q;
    logic [4:0] first_round_q;
    logic [4:0] round_offset_q;
    logic [127:0] x_q;
    logic [6:0] e_q;

    logic [3:0] use_n;
    logic [2:0] use_t;
    logic [127:0] base_x;
    logic [6:0] base_e;
    logic [127:0] enc_next_x;
    logic [6:0] enc_next_e;
    logic [127:0] dec_next_x;
    logic [6:0] dec_next_e;
    logic [127:0] candidate_value;
    logic [127:0] candidate_q;
    logic candidate_pending_q;
    logic candidate_accepted;
    logic key_required;
    logic expected_key_bank;
    logic [4:0] expected_key_index;
    assign candidate_accepted = candidate_q < FIXED_Q;

    function automatic logic [127:0] shuffle_profile(
        input logic [127:0] block,
        input logic [3:0] n,
        input logic [2:0] family
    );
        logic [4:0] source;
        integer lane;
        begin
            shuffle_profile = 128'h0;
            for (lane = 0; lane < 16; lane = lane + 1) begin
                source = profile_shuffle(n, family, lane[3:0]);
                if (source < 16)
                    shuffle_profile[8*lane +: 8] = block[8*source +: 8];
            end
        end
    endfunction

    function automatic logic [127:0] split_x(
        input logic [127:0] value,
        input logic [3:0] n
    );
        integer lane;
        begin
            split_x = 128'h0;
            for (lane = 0; lane < 16; lane = lane + 1)
                if (lane < n) split_x[8*lane +: 8] = value[8*lane +: 8];
        end
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [6:0] split_e(
        input logic [127:0] value,
        input logic [3:0] n,
        input logic [2:0] t
    );
        logic [6:0] shifted_low;
        logic [6:0] mask;
        begin
            case (n)
                4'd2: shifted_low = value[22:16];
                4'd3: shifted_low = value[30:24];
                4'd4: shifted_low = value[38:32];
                4'd5: shifted_low = value[46:40];
                4'd6: shifted_low = value[54:48];
                4'd7: shifted_low = value[62:56];
                4'd8: shifted_low = value[70:64];
                4'd9: shifted_low = value[78:72];
                4'd10: shifted_low = value[86:80];
                4'd11: shifted_low = value[94:88];
                4'd12: shifted_low = value[102:96];
                4'd13: shifted_low = value[110:104];
                4'd14: shifted_low = value[118:112];
                4'd15: shifted_low = value[126:120];
                default: shifted_low = 7'h0;
            endcase
            mask = (t == 0) ? 7'h00 : ((7'h01 << t) - 1'b1);
            split_e = shifted_low & mask;
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [127:0] join_value(
        input logic [127:0] x,
        input logic [6:0] e,
        input logic [3:0] n
    );
        logic [127:0] e_extended;
        integer lane;
        begin
            join_value = 128'h0;
            for (lane = 0; lane < 16; lane = lane + 1)
                if (lane < n) join_value[8*lane +: 8] = x[8*lane +: 8];
            e_extended = {121'd0, e};
            join_value = join_value | (e_extended << (8*n));
        end
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [6:0] update_e(
        input logic [6:0] e,
        input logic [127:0] block,
        input logic [7:0] compensation,
        input logic [2:0] t
    );
        logic [7:0] parity;
        logic [6:0] mask;
        logic [7:0] updated;
        begin
            parity = block[7:0] ^ block[15:8] ^ block[23:16] ^ block[31:24];
            mask = (t == 0) ? 7'h00 : ((7'h01 << t) - 1'b1);
            updated = {1'b0,e} ^ compensation ^ parity;
            update_e = updated[6:0] & mask;
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [127:0] e_block(input logic [6:0] e);
        begin
            e_block = {120'd0, 1'b0, e};
        end
    endfunction

    always_comb begin
        use_n = FIXED_N;
        use_t = FIXED_T;
        base_x = start_i ? split_x(input_i, FIXED_N) : x_q;
        base_e = start_i ? split_e(input_i, FIXED_N, FIXED_T) : e_q;

        key_required = 1'b0;
        expected_key_bank = 1'b0;
        expected_key_index = 5'd0;
        aes_active_o = active_i && !candidate_pending_q;
        aes_decrypt_o = 1'b0;
        aes_last_o = 1'b0;
        aes_state_o = 128'h0;
        aes_key_o = 128'h0;

        if (start_i) begin
            if (decrypt_q) begin
                aes_state_o = shuffle_profile(base_x, use_n, 3'd3);
                aes_last_o = 1'b1;
            end else begin
                key_required = 1'b1;
                expected_key_index = 5'd0;
                aes_state_o = shuffle_profile(base_x, use_n, 3'd3);
                aes_key_o = current_key_i;
            end
        end else begin
            case (state_q)
                ST_ENC_ROUND: begin
                    key_required = 1'b1;
                    expected_key_index = first_round_q + round_offset_q;
                    aes_state_o = shuffle_profile(x_q, FIXED_N, 3'd3);
                    aes_key_o = current_key_i;
                end
                ST_DEC_AUX: begin
                    aes_state_o = shuffle_profile(x_q, FIXED_N, 3'd3);
                    aes_last_o = 1'b1;
                end
                ST_DEC_ROUND: begin
                    key_required = 1'b1;
                    expected_key_bank = 1'b1;
                    expected_key_index = first_round_q + round_offset_q;
                    aes_state_o = shuffle_profile(x_q, FIXED_N, 3'd6);
                    aes_key_o = current_key_i;
                    aes_decrypt_o = 1'b1;
                end
                default: begin
                    aes_state_o = shuffle_profile(x_q, FIXED_N, 3'd7);
                    aes_decrypt_o = 1'b1;
                    aes_last_o = 1'b1;
                end
            endcase
        end

        enc_next_x = aes_result_i ^
                     shuffle_profile(aes_result_i, use_n, 3'd1) ^
                     shuffle_profile(e_block(base_e), use_n, 3'd2);
        enc_next_e = update_e(base_e, aes_result_i, 8'h00, use_t);

        dec_next_e = update_e(
            e_q, aes_result_i ^ current_key_i,
            (FIXED_N == 3 || FIXED_N == 7 || FIXED_N == 11 || FIXED_N == 15) ? 8'h52 : 8'h00,
            FIXED_T
        );
        dec_next_x = aes_result_i ^
                     shuffle_profile(aes_result_i, FIXED_N, 3'd5) ^
                     shuffle_profile(e_block(dec_next_e), FIXED_N, 3'd2);

        candidate_value = 128'h0;
        if (!start_i && state_q == ST_ENC_ROUND && round_offset_q + 1'b1 == k_q) begin
            candidate_value = join_value(enc_next_x, enc_next_e, FIXED_N);
        end else if (!start_i && state_q == ST_DEC_FINAL) begin
            candidate_value = join_value(aes_result_i, e_q, FIXED_N);
        end
        attempt_done_o = active_i && candidate_pending_q;
        attempt_accepted_o = attempt_done_o && candidate_accepted;
        attempt_segment_o = segment_q;
        attempt_index_o = attempt_q;
        attempt_first_round_o = first_round_q;
        data_done_o = attempt_done_o && candidate_accepted &&
                      (segment_q + 1'b1 == segment_count_q);
        result_o = data_done_o ? candidate_q : 128'h0;
    end

    always_comb begin
        key_prefetch_valid_o = 1'b0;
        key_prefetch_bank_o = 1'b0;
        key_prefetch_index_o = 5'd0;
        if (active_i) begin
            if (candidate_pending_q && state_q == ST_ENC_ROUND &&
                !data_done_o) begin
                key_prefetch_valid_o = 1'b1;
                key_prefetch_index_o = candidate_accepted ?
                    first_round_q + k_q : first_round_q;
            end else if (step_i && !candidate_pending_q) begin
                if (start_i) begin
                    if (decrypt_q) begin
                        key_prefetch_valid_o = 1'b1;
                        key_prefetch_bank_o = 1'b1;
                        key_prefetch_index_o = FIXED_ROUNDS - 1'b1;
                    end else if ((cycle_walking_q ? FIXED_ROUNDS : 5'd2) > 1) begin
                        key_prefetch_valid_o = 1'b1;
                        key_prefetch_index_o = 5'd1;
                    end
                end else begin
                    case (state_q)
                    ST_ENC_ROUND: begin
                        if (round_offset_q + 1'b1 < k_q) begin
                            key_prefetch_valid_o = 1'b1;
                            key_prefetch_index_o = first_round_q +
                                                   round_offset_q + 1'b1;
                        end
                    end
                    ST_DEC_AUX: begin
                        key_prefetch_valid_o = 1'b1;
                        key_prefetch_bank_o = 1'b1;
                        key_prefetch_index_o = first_round_q + k_q - 1'b1;
                    end
                    ST_DEC_ROUND: begin
                        if (round_offset_q != 0) begin
                            key_prefetch_valid_o = 1'b1;
                            key_prefetch_bank_o = 1'b1;
                            key_prefetch_index_o = first_round_q +
                                                   round_offset_q - 1'b1;
                        end
                    end
                    default: begin end
                    endcase
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        if (aes_active_o && key_required) begin
            assert (current_key_valid_i &&
                    current_key_bank_i == expected_key_bank &&
                    current_key_index_i == expected_key_index)
                else $fatal(1, "key prefetch tag does not match AES request");
        end
    end
`endif

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_ENC_ROUND;
            decrypt_q <= 1'b0;
            cycle_walking_q <= 1'b0;
            k_q <= 5'd0;
            segment_count_q <= 5'd0;
            segment_q <= 5'd0;
            attempt_q <= 16'd0;
            first_round_q <= 5'd0;
            round_offset_q <= 5'd0;
            x_q <= 128'h0;
            e_q <= 7'd0;
            candidate_q <= 128'h0;
            candidate_pending_q <= 1'b0;
        end else if (step_i) begin
            if (request_accept_i && !candidate_pending_q) begin
                decrypt_q <= decrypt_i;
                cycle_walking_q <= cycle_walking_i;
            end
            if (validate_active_i) begin
            end
            if (active_i) begin
                if (candidate_pending_q) begin
                    candidate_pending_q <= 1'b0;
                    if (state_q == ST_ENC_ROUND) begin
                        if (!data_done_o) begin
                            if (candidate_accepted) begin
                                segment_q <= segment_q + 1'b1;
                                attempt_q <= 16'd0;
                                first_round_q <= first_round_q + k_q;
                            end else begin
                                attempt_q <= attempt_q + 1'b1;
                            end
                        end
                    end else begin
                        x_q <= split_x(candidate_q, FIXED_N);
                        e_q <= split_e(candidate_q, FIXED_N, FIXED_T);
                        state_q <= ST_DEC_AUX;
                        if (!data_done_o) begin
                            if (candidate_accepted) begin
                                segment_q <= segment_q + 1'b1;
                                attempt_q <= 16'd0;
                                first_round_q <= first_round_q - k_q;
                            end else begin
                                attempt_q <= attempt_q + 1'b1;
                            end
                        end
                    end
                end else if (start_i) begin
                    k_q <= cycle_walking_q ? FIXED_ROUNDS : 5'd2;
                    segment_count_q <= cycle_walking_q ? 5'd1 : (FIXED_ROUNDS >> 1);
                    segment_q <= 5'd0;
                    attempt_q <= 16'd0;
                    first_round_q <= decrypt_q ?
                        (FIXED_ROUNDS - (cycle_walking_q ? FIXED_ROUNDS : 5'd2)) : 5'd0;
                    if (decrypt_q) begin
                        x_q <= aes_result_i;
                        e_q <= split_e(input_i, FIXED_N, FIXED_T);
                        round_offset_q <= (cycle_walking_q ? FIXED_ROUNDS : 5'd2) - 1'b1;
                        state_q <= ST_DEC_ROUND;
                    end else begin
                        x_q <= enc_next_x;
                        e_q <= enc_next_e;
                        round_offset_q <= 5'd1;
                        state_q <= ST_ENC_ROUND;
                    end
                end else begin
                    case (state_q)
                    ST_ENC_ROUND: begin
                        if (round_offset_q + 1'b1 == k_q) begin
                            candidate_q <= candidate_value;
                            candidate_pending_q <= 1'b1;
                            x_q <= enc_next_x;
                            e_q <= enc_next_e;
                            round_offset_q <= 5'd0;
                        end else begin
                            x_q <= enc_next_x;
                            e_q <= enc_next_e;
                            round_offset_q <= round_offset_q + 1'b1;
                        end
                    end
                    ST_DEC_AUX: begin
                        x_q <= aes_result_i;
                        round_offset_q <= k_q - 1'b1;
                        state_q <= ST_DEC_ROUND;
                    end
                    ST_DEC_ROUND: begin
                        x_q <= dec_next_x;
                        e_q <= dec_next_e;
                        if (round_offset_q == 0) begin
                            state_q <= ST_DEC_FINAL;
                        end else begin
                            round_offset_q <= round_offset_q - 1'b1;
                        end
                    end
                    default: begin
                        candidate_q <= candidate_value;
                        candidate_pending_q <= 1'b1;
                    end
                    endcase
                end
            end
        end
    end
endmodule
`endif

`default_nettype wire
