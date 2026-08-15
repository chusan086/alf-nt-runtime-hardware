`timescale 1ns/1ps
`default_nettype none

// ALF key expansion, tweak initialization and decrypt preparation.  One
// immutable ticket starts a locally sequenced operation; AES requests remain
// stable until accepted and local state advances only on the matching result.
module n12_alf_key_tweak (
    input  logic         clk_i,
    input  logic         rst_ni,

    input  logic         kt_start_valid_i,
    output logic         kt_start_ready_o,
    input  logic         ticket_cold_i,
    input  logic         ticket_decrypt_i,
    input  logic [127:0] ticket_key_i,
    input  logic [63:0]  ticket_app_id_i,
    input  logic [127:0] ticket_tweak_i,
    input  logic         transaction_retire_i,

    output logic         kt_done_valid_o,
    input  logic         kt_done_ready_i,

    output logic         engine_init_active_o,
    output logic         key_init_active_o,
    output logic         tweak_init_active_o,
    output logic         prepare_active_o,
    output logic [15:0]  local_cycle_o,

    output logic         aes_active_o,
    input  logic         aes_ready_i,
    output logic [2:0]   aes_mode_o,
    output logic [127:0] aes_state_o,
    output logic [127:0] aes_key_o,
    input  logic         aes_result_valid_i,
    input  logic [127:0] aes_result_i,

    input  logic         key_prefetch_valid_i,
    input  logic         key_prefetch_bank_i,
    input  logic [4:0]   key_prefetch_index_i,
    output logic [127:0] current_key_o,
    output logic         current_key_valid_o,
    output logic         current_key_bank_o,
    output logic [4:0]   current_key_index_o
);
    import n12_alf_v0_tables_pkg::*;

    localparam logic [3:0] FIXED_N = 4'd6;
    localparam logic [2:0] FIXED_T = 3'd6;
    localparam logic [4:0] FIXED_ROUNDS = 5'd16;
    localparam logic [127:0] FIXED_Q =
        128'h0000000000000000002386f26fc10000;
    localparam logic [127:0] FIXED_Q_MINUS_ONE =
        128'h0000000000000000002386f26fc0ffff;

    localparam logic [2:0] ST_IDLE        = 3'd0;
    localparam logic [2:0] ST_ENGINE_INIT = 3'd1;
    localparam logic [2:0] ST_KEY_INIT    = 3'd2;
    localparam logic [2:0] ST_TWEAK_INIT  = 3'd3;
    localparam logic [2:0] ST_PREPARE     = 3'd4;
    localparam logic [2:0] ST_DONE        = 3'd5;

    logic [2:0] state_q;
    logic [15:0] phase_cycle_q;
    logic aes_outstanding_q;

    (* keep = "true", alf_role = "smac_work" *)
    logic [127:0] work_a1_q, work_a2_q, work_a3_q;
    logic [127:0] key_origin_a1_q, key_origin_a2_q, key_origin_a3_q;
    logic [127:0] key_state_a1_q, key_state_a2_q, key_state_a3_q;
    (* keep = "true", alf_role = "smac_base" *)
    logic [127:0] post_a1_q, post_a2_q, post_a3_q;
    logic [127:0] half_result_q;
    (* keep = "true", alf_role = "key_spill" *)
    logic [127:0] key_spill_q;
    logic [3:0] spill_valid_q;
    logic [2:0] branch_index_q;
    logic [4:0] smac_subcycle_q;
    logic       emit_active_q;
    logic [4:0] emit_index_q;
    logic [4:0] emit_total_q;
    logic [5:0] branch_source_q;
    logic [4:0] key_write_index_q;
    logic         key_bank_write_enable;
    logic         key_bank_write_bank;
    logic [4:0]   key_bank_write_index;
    logic [127:0] key_bank_write_data;
    logic         key_bank_read_enable;
    logic         key_bank_read_bank;
    logic [4:0]   key_bank_read_index;

    // Ticket registers are written only by a start handshake and remain
    // immutable until the local operation has completed.
    logic         ticket_decrypt_q;
    logic [127:0] ticket_key_q;
    logic [63:0]  ticket_app_id_q;
    logic [127:0] ticket_tweak_q;

    logic [15:0] branch_count;
    logic [31:0] branch_counter;
    logic [4:0] prepare_index;
    logic [8:0] total_key_bytes;
    logic [8:0] branch_byte_base;
    logic [8:0] branch_remaining_bytes;
    logic [6:0] branch_valid_bytes;
    logic [6:0] branch_emit_count;
    logic [6:0] branch_emit_numerator;
    logic [6:0] emit_spill_count;
    logic [6:0] emit_source_next;
    logic [6:0] emit_leftover;
    logic branch_final;
    logic emit_last;
    logic tweak_complete_now;
    logic prepare_complete_now;
    logic [127:0] smac_message;
    logic [127:0] smac_next_a1;
    logic [127:0] smac_next_a2;
    logic [127:0] smac_next_a3;
    logic [383:0] branch_result;
    logic [127:0] extracted_key;
    logic [127:0] prepare_pre_mix;

    integer comb_lane;

    n12_alf_key_bank key_bank (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .invalidate_i(transaction_retire_i),
        .read_enable_i(key_bank_read_enable),
        .read_bank_i(key_bank_read_bank),
        .read_index_i(key_bank_read_index),
        .current_key_o(current_key_o),
        .current_valid_o(current_key_valid_o),
        .current_bank_o(current_key_bank_o),
        .current_index_o(current_key_index_o),
        .write_enable_i(key_bank_write_enable),
        .write_bank_i(key_bank_write_bank),
        .write_index_i(key_bank_write_index),
        .write_data_i(key_bank_write_data)
    );

    function automatic logic [127:0] sigma42(input logic [127:0] block);
        logic [4:0] source;
        integer output_lane;
        begin
            sigma42 = 128'h0;
            for (output_lane = 0; output_lane < 16; output_lane = output_lane + 1) begin
                case (output_lane)
                    0: source = 5'd7;   1: source = 5'd14;
                    2: source = 5'd15;  3: source = 5'd10;
                    4: source = 5'd12;  5: source = 5'd13;
                    6: source = 5'd3;   7: source = 5'd0;
                    8: source = 5'd4;   9: source = 5'd6;
                    10: source = 5'd1;  11: source = 5'd5;
                    12: source = 5'd8;  13: source = 5'd11;
                    14: source = 5'd2;  default: source = 5'd9;
                endcase
                sigma42[8*output_lane +: 8] = block[8*source +: 8];
            end
        end
    endfunction

    function automatic logic [127:0] shuffle_profile(
        input logic [127:0] block,
        input logic [3:0] n,
        input logic [2:0] family
    );
        logic [4:0] source;
        integer output_lane;
        begin
            shuffle_profile = 128'h0;
            for (output_lane = 0; output_lane < 16; output_lane = output_lane + 1) begin
                source = profile_shuffle(n, family, output_lane[3:0]);
                if (source < 16)
                    shuffle_profile[8*output_lane +: 8] = block[8*source +: 8];
            end
        end
    endfunction

    function automatic logic [127:0] prepare_input(
        input logic [127:0] key,
        input logic [3:0] n
    );
        logic [127:0] const_a;
        logic [127:0] inside_block;
        integer output_lane;
        begin
            const_a = 128'h0;
            for (output_lane = 0; output_lane < 16; output_lane = output_lane + 1)
                const_a[8*output_lane +: 8] = profile_const_a(n, output_lane[3:0]);
            inside_block = shuffle_profile(shuffle_profile(key, n, 3'd1), n, 3'd4) ^
                           shuffle_profile(key, n, 3'd4) ^ const_a;
            prepare_input = inside_block;
        end
    endfunction

    function automatic logic [7:0] branch_byte(
        input logic [383:0] block,
        input integer byte_index
    );
        begin
            branch_byte = block[8*byte_index +: 8];
        end
    endfunction

    always_comb begin
        branch_count = (({12'd0, FIXED_N} * {11'd0, FIXED_ROUNDS}) + 16'd47) / 16'd48;
        total_key_bytes = {4'd0, FIXED_ROUNDS} * {5'd0, FIXED_N};
        branch_byte_base = {6'd0, branch_index_q} * 9'd48;
        branch_remaining_bytes = total_key_bytes - branch_byte_base;
        if (branch_remaining_bytes >= 9'd48)
            branch_valid_bytes = 7'd48;
        else
            branch_valid_bytes = branch_remaining_bytes[6:0];
        branch_emit_numerator = {3'd0, spill_valid_q} + branch_valid_bytes;
        branch_emit_count = 7'd0;
        if (FIXED_N != 4'd0)
            branch_emit_count = branch_emit_numerator / {3'd0, FIXED_N};
        if (branch_emit_count > ({1'b0, FIXED_ROUNDS} - {1'b0, key_write_index_q}))
            branch_emit_count = {1'b0, FIXED_ROUNDS} - {1'b0, key_write_index_q};
        branch_final = ({13'd0, branch_index_q} + 16'd1 >= branch_count);
        branch_counter = {29'd0, branch_index_q} + 32'd1;
        emit_spill_count = (emit_index_q == 5'd0) ?
                           {3'd0, spill_valid_q} : 7'd0;
        emit_source_next = {1'b0, branch_source_q} + {3'd0, FIXED_N} -
                           emit_spill_count;
        if (branch_valid_bytes >= emit_source_next)
            emit_leftover = branch_valid_bytes - emit_source_next;
        else
            emit_leftover = 7'd0;
        prepare_index = phase_cycle_q[4:0];

        branch_result = {
            post_a3_q ^ work_a3_q,
            post_a2_q ^ work_a2_q,
            post_a1_q ^ work_a1_q
        };
        extracted_key = 128'h0;
        if (emit_active_q) begin
            for (comb_lane = 0; comb_lane < 16; comb_lane = comb_lane + 1) begin
                if (comb_lane < FIXED_N) begin
                    if (emit_index_q == 5'd0 && comb_lane < spill_valid_q)
                        extracted_key[8*comb_lane +: 8] =
                            key_spill_q[8*comb_lane +: 8];
                    else
                        extracted_key[8*comb_lane +: 8] = branch_byte(
                            branch_result,
                            integer'(branch_source_q) + comb_lane -
                            integer'(emit_spill_count));
                end
            end
        end

        prepare_pre_mix = prepare_input(current_key_o, FIXED_N);

        smac_message = 128'h0;
        aes_active_o = 1'b0;
        aes_mode_o = 3'd0;
        aes_state_o = 128'h0;
        aes_key_o = 128'h0;
        if (state_q == ST_KEY_INIT) begin
            smac_message = 128'h00000000000000000000000000000001;
            aes_active_o = 1'b1;
            aes_state_o = phase_cycle_q[0] ? work_a2_q : work_a1_q;
            aes_key_o = smac_message;
        end else if (state_q == ST_TWEAK_INIT && !emit_active_q) begin
            if (phase_cycle_q < 16'd2)
                smac_message = ticket_tweak_q;
            else
                smac_message = {96'd0, branch_counter};
            aes_active_o = 1'b1;
            aes_state_o = (phase_cycle_q < 16'd2 ? phase_cycle_q[0] :
                           smac_subcycle_q[0]) ? work_a2_q : work_a1_q;
            aes_key_o = smac_message;
        end else if (state_q == ST_PREPARE) begin
            aes_active_o = 1'b1;
            aes_mode_o = 3'd4;
            aes_state_o = prepare_pre_mix;
        end

        smac_next_a1 = sigma42(work_a2_q ^ work_a3_q ^ smac_message);
        smac_next_a2 = half_result_q;
        smac_next_a3 = aes_result_i;
    end

    always_comb begin
        key_bank_write_enable = 1'b0;
        key_bank_write_bank = 1'b0;
        key_bank_write_index = 5'd0;
        key_bank_write_data = 128'h0;
        if (state_q == ST_TWEAK_INIT && emit_active_q) begin
            key_bank_write_enable = 1'b1;
            key_bank_write_bank = 1'b0;
            key_bank_write_index = key_write_index_q;
            key_bank_write_data = extracted_key;
        end else if (state_q == ST_PREPARE && aes_outstanding_q &&
                     aes_result_valid_i) begin
            key_bank_write_enable = 1'b1;
            key_bank_write_bank = 1'b1;
            key_bank_write_index = prepare_index;
            key_bank_write_data = aes_result_i;
        end

        key_bank_read_enable = key_prefetch_valid_i;
        key_bank_read_bank = key_prefetch_bank_i;
        key_bank_read_index = key_prefetch_index_i;
        if (state_q == ST_PREPARE && aes_outstanding_q &&
            aes_result_valid_i && phase_cycle_q + 1'b1 < FIXED_ROUNDS) begin
            key_bank_read_enable = 1'b1;
            key_bank_read_bank = 1'b0;
            key_bank_read_index = prepare_index + 1'b1;
        end else if (state_q == ST_TWEAK_INIT && emit_active_q && emit_last &&
                     (branch_final ||
                      key_write_index_q + 1'b1 >= FIXED_ROUNDS)) begin
            key_bank_read_enable = 1'b1;
            key_bank_read_bank = 1'b0;
            key_bank_read_index = 5'd0;
        end
    end

    assign kt_start_ready_o = (state_q == ST_IDLE);
    assign engine_init_active_o = (state_q == ST_ENGINE_INIT);
    assign key_init_active_o = (state_q == ST_KEY_INIT);
    assign tweak_init_active_o = (state_q == ST_TWEAK_INIT);
    assign prepare_active_o = (state_q == ST_PREPARE);
    assign local_cycle_o = phase_cycle_q;

    assign emit_last = emit_active_q &&
                       (emit_index_q + 1'b1 >= emit_total_q);
    assign tweak_complete_now = (state_q == ST_TWEAK_INIT) &&
                                !ticket_decrypt_q && emit_last &&
                                (branch_final ||
                                 key_write_index_q + 1'b1 >= FIXED_ROUNDS);
    assign prepare_complete_now = (state_q == ST_PREPARE) &&
                                  aes_outstanding_q && aes_result_valid_i &&
                                  (phase_cycle_q + 1'b1 >= FIXED_ROUNDS);
    assign kt_done_valid_o = (state_q == ST_DONE) ||
                             tweak_complete_now || prepare_complete_now;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE;
            phase_cycle_q <= 16'd0;
            aes_outstanding_q <= 1'b0;
            ticket_decrypt_q <= 1'b0;
            ticket_key_q <= 128'h0;
            ticket_app_id_q <= 64'h0;
            ticket_tweak_q <= 128'h0;
            work_a1_q <= 128'h0;
            work_a2_q <= 128'h0;
            work_a3_q <= 128'h0;
            key_origin_a1_q <= 128'h0;
            key_origin_a2_q <= 128'h0;
            key_origin_a3_q <= 128'h0;
            key_state_a1_q <= 128'h0;
            key_state_a2_q <= 128'h0;
            key_state_a3_q <= 128'h0;
            post_a1_q <= 128'h0;
            post_a2_q <= 128'h0;
            post_a3_q <= 128'h0;
            half_result_q <= 128'h0;
            key_spill_q <= 128'h0;
            spill_valid_q <= 4'd0;
            branch_index_q <= 3'd0;
            smac_subcycle_q <= 5'd0;
            emit_active_q <= 1'b0;
            emit_index_q <= 5'd0;
            emit_total_q <= 5'd0;
            branch_source_q <= 6'd0;
            key_write_index_q <= 5'd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    phase_cycle_q <= 16'd0;
                    aes_outstanding_q <= 1'b0;
                    if (kt_start_valid_i && kt_start_ready_o) begin
                        ticket_decrypt_q <= ticket_decrypt_i;
                        ticket_key_q <= ticket_key_i;
                        ticket_app_id_q <= ticket_app_id_i;
                        ticket_tweak_q <= ticket_tweak_i;
                        work_a1_q <= key_state_a1_q;
                        work_a2_q <= key_state_a2_q;
                        work_a3_q <= key_state_a3_q;
                        state_q <= ticket_cold_i ? ST_ENGINE_INIT : ST_TWEAK_INIT;
                    end
                end

                ST_ENGINE_INIT: begin
                    if (phase_cycle_q == 16'd0) begin
                        work_a1_q <= {63'd0, 1'b1, ticket_app_id_q};
                        work_a2_q <= ticket_key_q;
                        work_a3_q <= FIXED_Q_MINUS_ONE;
                        key_origin_a1_q <= {63'd0, 1'b1, ticket_app_id_q};
                        key_origin_a2_q <= ticket_key_q;
                        key_origin_a3_q <= FIXED_Q_MINUS_ONE;
                    end
                    if (phase_cycle_q + 1'b1 >= 16'd2) begin
                        phase_cycle_q <= 16'd0;
                        state_q <= ST_KEY_INIT;
                    end else begin
                        phase_cycle_q <= phase_cycle_q + 1'b1;
                    end
                end

                ST_KEY_INIT: begin
                    if (aes_active_o && aes_ready_i)
                        aes_outstanding_q <= 1'b1;
                    if (aes_outstanding_q && aes_result_valid_i) begin
                        aes_outstanding_q <= 1'b0;
                        if (!phase_cycle_q[0]) begin
                            half_result_q <= aes_result_i;
                        end else if (phase_cycle_q == 16'd17) begin
                            key_state_a1_q <= key_origin_a1_q ^ smac_next_a1;
                            key_state_a2_q <= key_origin_a2_q ^ smac_next_a2;
                            key_state_a3_q <= key_origin_a3_q ^ smac_next_a3;
                            work_a1_q <= key_origin_a1_q ^ smac_next_a1;
                            work_a2_q <= key_origin_a2_q ^ smac_next_a2;
                            work_a3_q <= key_origin_a3_q ^ smac_next_a3;
                        end else begin
                            work_a1_q <= smac_next_a1;
                            work_a2_q <= smac_next_a2;
                            work_a3_q <= smac_next_a3;
                        end
                        if (phase_cycle_q + 1'b1 >= 16'd18) begin
                            phase_cycle_q <= 16'd0;
                            state_q <= ST_TWEAK_INIT;
                        end else begin
                            phase_cycle_q <= phase_cycle_q + 1'b1;
                        end
                    end
                end

                ST_TWEAK_INIT: begin
                    if (!emit_active_q) begin
                        if (aes_active_o && aes_ready_i)
                            aes_outstanding_q <= 1'b1;
                        if (aes_outstanding_q && aes_result_valid_i) begin
                            aes_outstanding_q <= 1'b0;
                            phase_cycle_q <= phase_cycle_q + 1'b1;
                            if (phase_cycle_q < 16'd2) begin
                                if (!phase_cycle_q[0]) begin
                                    half_result_q <= aes_result_i;
                                end else begin
                                    work_a1_q <= smac_next_a1;
                                    work_a2_q <= smac_next_a2;
                                    work_a3_q <= smac_next_a3;
                                    post_a1_q <= smac_next_a1;
                                    post_a2_q <= smac_next_a2;
                                    post_a3_q <= smac_next_a3;
                                    key_spill_q <= 128'h0;
                                    spill_valid_q <= 4'd0;
                                    branch_index_q <= 3'd0;
                                    smac_subcycle_q <= 5'd0;
                                    emit_active_q <= 1'b0;
                                    emit_index_q <= 5'd0;
                                    emit_total_q <= 5'd0;
                                    branch_source_q <= 6'd0;
                                    key_write_index_q <= 5'd0;
                                end
                            end else if (!smac_subcycle_q[0]) begin
                                half_result_q <= aes_result_i;
                                smac_subcycle_q <= smac_subcycle_q + 1'b1;
                            end else if (smac_subcycle_q == 5'd17) begin
                                work_a1_q <= smac_next_a1;
                                work_a2_q <= smac_next_a2;
                                work_a3_q <= smac_next_a3;
                                smac_subcycle_q <= 5'd0;
                                emit_active_q <= 1'b1;
                                emit_index_q <= 5'd0;
                                emit_total_q <= branch_emit_count[4:0];
                                branch_source_q <= 6'd0;
                            end else begin
                                work_a1_q <= smac_next_a1;
                                work_a2_q <= smac_next_a2;
                                work_a3_q <= smac_next_a3;
                                smac_subcycle_q <= smac_subcycle_q + 1'b1;
                            end
                        end
                    end else begin
                        key_write_index_q <= key_write_index_q + 1'b1;
                        phase_cycle_q <= phase_cycle_q + 1'b1;
                        if (emit_last) begin
                            emit_active_q <= 1'b0;
                            emit_index_q <= 5'd0;
                            emit_total_q <= 5'd0;
                            branch_source_q <= 6'd0;
                            smac_subcycle_q <= 5'd0;
                            work_a1_q <= post_a1_q;
                            work_a2_q <= post_a2_q;
                            work_a3_q <= post_a3_q;
                            if (branch_final ||
                                key_write_index_q + 1'b1 >= FIXED_ROUNDS) begin
                                key_spill_q <= 128'h0;
                                spill_valid_q <= 4'd0;
                                phase_cycle_q <= 16'd0;
                                if (ticket_decrypt_q) begin
                                    state_q <= ST_PREPARE;
                                end else begin
                                    state_q <= kt_done_ready_i ? ST_IDLE : ST_DONE;
                                end
                            end else begin
                                key_spill_q <= 128'h0;
                                for (integer lane = 0; lane < 16; lane = lane + 1) begin
                                    if (lane < emit_leftover)
                                        key_spill_q[8*lane +: 8] <= branch_byte(
                                            branch_result,
                                            integer'(emit_source_next) + lane);
                                end
                                spill_valid_q <= emit_leftover[3:0];
                                branch_index_q <= branch_index_q + 1'b1;
                            end
                        end else begin
                            branch_source_q <= emit_source_next[5:0];
                            emit_index_q <= emit_index_q + 1'b1;
                            if (emit_index_q == 5'd0) begin
                                key_spill_q <= 128'h0;
                                spill_valid_q <= 4'd0;
                            end
                        end
                    end
                end

                ST_PREPARE: begin
                    if (aes_active_o && aes_ready_i)
                        aes_outstanding_q <= 1'b1;
                    if (aes_outstanding_q && aes_result_valid_i) begin
                        aes_outstanding_q <= 1'b0;
                        if (phase_cycle_q + 1'b1 >= FIXED_ROUNDS) begin
                            phase_cycle_q <= 16'd0;
                            state_q <= kt_done_ready_i ? ST_IDLE : ST_DONE;
                        end else begin
                            phase_cycle_q <= phase_cycle_q + 1'b1;
                        end
                    end
                end

                ST_DONE: begin
                    if (kt_done_valid_o && kt_done_ready_i)
                        state_q <= ST_IDLE;
                end

                default: begin
                    state_q <= ST_IDLE;
                    phase_cycle_q <= 16'd0;
                    aes_outstanding_q <= 1'b0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
