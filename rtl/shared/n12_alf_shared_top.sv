`timescale 1ns/1ps
`default_nettype none

// Runtime-parameterized ALF core.  One frontend, controller and AES round lane
// serve every legal (n,t,Q) domain; only one operation may own the datapath.
// 运行时参数化 ALF 核：一套前端、控制器和 AES 轮通路覆盖全部合法 (n,t,Q)，任一时刻仅一个操作占用数据通路。
module n12_alf_shared_top (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        req_valid_i,
    output logic        req_ready_o,
    input  logic [31:0] req_data_i,
    output logic        rsp_valid_o,
    input  logic        rsp_ready_i,
    output logic [31:0] rsp_data_o
);
    logic request_valid, request_ready, request_accept;
    logic [127:0] request_key, request_tweak, request_q, request_q_minus_one;
    logic [127:0] request_input;
    logic [63:0] request_app;
    logic [31:0] request_config, request_command;
    logic result_valid, result_ready;
    logic [127:0] result_value_q;
    logic [127:0] response_value;
    logic [31:0] result_status;

    logic [3:0] request_n;
    logic [2:0] request_t;
    logic request_decrypt, request_cw, request_reuse;
    logic request_syntax_valid;

    // This bank is the sole raw-request/profile boundary.  All downstream
    // execution consumes only the immutable registered descriptor.
    logic descriptor_valid_q, descriptor_payload_valid_q;
    logic descriptor_identity_q;
    logic descriptor_syntax_valid_q, descriptor_domain_valid_q;
    logic [127:0] descriptor_q_q;
    logic [127:0] descriptor_key_q, descriptor_tweak_q;
    logic [127:0] descriptor_q_minus_one_q, descriptor_input_q;
    logic [63:0] descriptor_app_q;
    logic [3:0] descriptor_n_q;
    logic [2:0] descriptor_t_q;
    logic descriptor_decrypt_q, descriptor_cw_q, descriptor_cold_q;
    logic [4:0] descriptor_rounds_q;
    logic [4:0] descriptor_rounds_per_segment_q;
    logic [4:0] descriptor_segment_count_q;
    logic [8:0] descriptor_total_key_bytes_q;
    logic [2:0] descriptor_branch_count_q;
    logic [44:0] descriptor_branch_remaining_q;
    logic [34:0] descriptor_branch_valid_q;
    logic [24:0] descriptor_branch_emit_q;
    logic [19:0] descriptor_branch_spill_q;
    logic [34:0] descriptor_branch_source_limit_q;
    logic descriptor_dispatch, descriptor_dispatch_ready;
    logic executable_descriptor_dispatch, execution_dispatch;
    logic descriptor_retire;
    logic expected_dispatch_valid_q, expected_dispatch_identity_q;
    logic controller_identity_match, kt_identity_match, core_identity_match;
    logic identity_execution_permit;

    // Parent testbench compatibility aliases.  These are descriptor outputs,
    // not a second bank and not live request/profile signals.
    logic profile_valid;
    logic [4:0] profile_rounds;
    logic [127:0] active_q_q;
    logic [127:0] active_key_q, active_tweak_q, active_q_minus_one_q;
    logic [63:0] active_app_q;
    logic [3:0] active_n_q;
    logic [2:0] active_t_q;
    logic active_decrypt_q, active_cw_q, active_cold_q;
    logic active_syntax_valid_q;

    // Resident context is reusable only on an exact key/application/domain
    // match.  A mismatch forces a cold start; it never silently retags state.
    // 仅当密钥、应用标识和参数域完全匹配时才能复用驻留上下文；不匹配必须冷启动，不能直接重标记旧状态。
    logic resident_valid_q;
    logic [127:0] resident_key_q, resident_q_q;
    logic [63:0] resident_app_q;
    logic [3:0] resident_n_q;
    logic [2:0] resident_t_q;
    logic resident_match, cold_start;
    logic pending_context_valid_q, pending_context_identity_q;
    logic pending_context_identity_match;
    logic [127:0] pending_context_key_q, pending_context_q_q;
    logic [63:0] pending_context_app_q;
    logic [3:0] pending_context_n_q;
    logic [2:0] pending_context_t_q;

    logic controller_done, controller_error;
    logic [3:0] controller_phase;
    logic [15:0] phase_cycle, kt_local_cycle;
    logic validate_active, engine_active, key_active, tweak_active;
    logic prepare_active, data_active, finalize_active;
    logic kt_start_valid, kt_start_ready;
    logic kt_descriptor_ready;
    logic kt_done_valid, kt_done_ready;

    logic kt_aes_active;
    logic [2:0] kt_aes_mode;
    logic [127:0] kt_aes_state, kt_aes_key, kt_aes_result;
    logic kt_aes_ready, kt_aes_result_valid;
    logic key_prefetch_valid, key_prefetch_bank;
    logic [4:0] key_prefetch_index;
    logic [127:0] current_key;
    logic current_key_valid, current_key_bank;
    logic [4:0] current_key_index;
    logic core_aes_active, core_aes_decrypt, core_aes_last;
    logic [127:0] core_aes_state, core_aes_key, core_aes_result;
    logic core_data_done;
    logic [127:0] core_result;
    logic core_attempt_done, core_attempt_accepted;
    logic [4:0] core_attempt_segment, core_attempt_first;
    logic [15:0] core_attempt_index;

    logic [2:0] lane_mode;
    logic [127:0] lane_state, lane_key, lane_result;
    // One registered boundary carries exactly one owner-tagged request.  The
    // key/tweak owner receives explicit ready/result-valid events; producer_step
    // remains only for the frozen round-core request protocol.
    localparam logic AES_OWNER_KEY_TWEAK = 1'b0;
    localparam logic AES_OWNER_ROUND_CORE = 1'b1;
    logic aes_pending_q, aes_owner_q;
    logic [2:0] aes_mode_q;
    logic [127:0] aes_state_q, aes_key_q;
    logic aes_request_valid, aes_request_owner;
    logic [2:0] aes_request_mode;
    logic [127:0] aes_request_state, aes_request_key;
    logic aes_capture, producer_step;
    logic core_start, round_started_q;

    assign request_n = request_config[3:0];
    assign request_t = request_config[6:4];
    assign request_decrypt = request_config[7];
    assign request_cw = request_config[8];
    assign request_reuse = request_config[9];
    assign request_accept = request_valid && request_ready;
    assign request_syntax_valid = (request_config[31:10] == 22'd0) &&
                                  (request_command == 32'd1) &&
                                  (request_input < request_q);
    assign resident_match = resident_valid_q &&
                            resident_key_q == request_key &&
                            resident_app_q == request_app &&
                            resident_q_q == request_q &&
                            resident_n_q == request_n &&
                            resident_t_q == request_t;
    assign cold_start = !(request_reuse && resident_match);
    assign descriptor_retire = controller_done && result_ready;
    assign descriptor_dispatch_ready =
        !(descriptor_syntax_valid_q && descriptor_domain_valid_q &&
          (descriptor_rounds_q != 5'd0)) || kt_descriptor_ready;
    assign descriptor_dispatch = validate_active && descriptor_payload_valid_q &&
                                 descriptor_dispatch_ready;
    assign executable_descriptor_dispatch = descriptor_dispatch &&
        descriptor_syntax_valid_q && descriptor_domain_valid_q &&
        (descriptor_rounds_q != 5'd0);
    assign identity_execution_permit = expected_dispatch_valid_q &&
        controller_identity_match && kt_identity_match && core_identity_match;
    assign execution_dispatch = kt_start_valid && kt_start_ready;
    assign pending_context_identity_match = pending_context_valid_q &&
        expected_dispatch_valid_q &&
        (pending_context_identity_q == expected_dispatch_identity_q);

    assign profile_valid = descriptor_domain_valid_q;
    assign profile_rounds = descriptor_rounds_q;
    assign active_q_q = descriptor_q_q;
    assign active_key_q = descriptor_key_q;
    assign active_app_q = descriptor_app_q;
    assign active_tweak_q = descriptor_tweak_q;
    assign active_q_minus_one_q = descriptor_q_minus_one_q;
    assign active_n_q = descriptor_n_q;
    assign active_t_q = descriptor_t_q;
    assign active_decrypt_q = descriptor_decrypt_q;
    assign active_cw_q = descriptor_cw_q;
    assign active_cold_q = descriptor_cold_q;
    assign active_syntax_valid_q = descriptor_syntax_valid_q;

    n12_alf_stream_frontend frontend (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .req_valid_i(req_valid_i), .req_ready_o(req_ready_o),
        .req_data_i(req_data_i),
        .request_valid_o(request_valid), .request_ready_i(request_ready),
        .key_o(request_key), .app_id_o(request_app), .tweak_o(request_tweak),
        .q_o(request_q), .q_minus_one_o(request_q_minus_one),
        .config_o(request_config), .input_o(request_input),
        .command_o(request_command),
        .result_valid_i(result_valid), .result_ready_o(result_ready),
        .result_i(response_value), .status_i(result_status),
        .rsp_valid_o(rsp_valid_o), .rsp_ready_i(rsp_ready_i),
        .rsp_data_o(rsp_data_o)
    );

    n12_alf_operation_descriptor operation_descriptor (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .capture_i(request_accept), .dispatch_i(descriptor_dispatch),
        .retire_i(descriptor_retire),
        .syntax_valid_i(request_syntax_valid),
        .key_i(request_key), .app_id_i(request_app),
        .tweak_i(request_tweak), .q_i(request_q),
        .q_minus_one_i(request_q_minus_one),
        .n_i(request_n), .t_i(request_t),
        .decrypt_i(request_decrypt), .cycle_walking_i(request_cw),
        .cold_i(cold_start), .input_i(request_input),
        .valid_o(descriptor_valid_q),
        .payload_valid_o(descriptor_payload_valid_q),
        .identity_o(descriptor_identity_q),
        .syntax_valid_o(descriptor_syntax_valid_q),
        .domain_valid_o(descriptor_domain_valid_q),
        .key_o(descriptor_key_q), .app_id_o(descriptor_app_q),
        .tweak_o(descriptor_tweak_q), .q_o(descriptor_q_q),
        .q_minus_one_o(descriptor_q_minus_one_q),
        .n_o(descriptor_n_q), .t_o(descriptor_t_q),
        .decrypt_o(descriptor_decrypt_q),
        .cycle_walking_o(descriptor_cw_q), .cold_o(descriptor_cold_q),
        .input_o(descriptor_input_q), .rounds_o(descriptor_rounds_q),
        .rounds_per_segment_o(descriptor_rounds_per_segment_q),
        .segment_count_o(descriptor_segment_count_q),
        .total_key_bytes_o(descriptor_total_key_bytes_q),
        .branch_count_o(descriptor_branch_count_q),
        .branch_remaining_bytes_o(descriptor_branch_remaining_q),
        .branch_valid_bytes_o(descriptor_branch_valid_q),
        .branch_emit_count_o(descriptor_branch_emit_q),
        .branch_spill_after_o(descriptor_branch_spill_q),
        .branch_source_limit_o(descriptor_branch_source_limit_q)
    );

    n12_alf_controller controller (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .start_valid_i(request_valid), .start_ready_o(request_ready),
        .dispatch_valid_i(descriptor_dispatch),
        .dispatch_identity_i(descriptor_identity_q),
        .expected_valid_i(expected_dispatch_valid_q),
        .expected_identity_i(expected_dispatch_identity_q),
        .execution_permit_i(identity_execution_permit),
        .syntax_valid_i(descriptor_valid_q && descriptor_syntax_valid_q),
        .domain_valid_i(descriptor_domain_valid_q),
        .rounds_i(descriptor_rounds_q),
        .kt_start_valid_o(kt_start_valid),
        .kt_start_ready_i(kt_start_ready),
        .kt_done_valid_i(kt_done_valid), .kt_done_ready_o(kt_done_ready),
        .data_done_i(core_data_done),
        .done_valid_o(controller_done), .done_ready_i(result_ready),
        .error_o(controller_error), .phase_o(controller_phase),
        .validate_active_o(validate_active),
        .data_active_o(data_active), .finalize_active_o(finalize_active),
        .local_identity_match_o(controller_identity_match)
    );

    n12_alf_key_tweak key_tweak (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .kt_start_valid_i(kt_start_valid),
        .kt_start_ready_o(kt_start_ready),
        .descriptor_capture_i(executable_descriptor_dispatch),
        .descriptor_ready_o(kt_descriptor_ready),
        .expected_valid_i(expected_dispatch_valid_q),
        .expected_identity_i(expected_dispatch_identity_q),
        .execution_permit_i(identity_execution_permit),
        .ticket_cold_i(descriptor_cold_q),
        .ticket_decrypt_i(descriptor_decrypt_q),
        .ticket_key_i(descriptor_key_q), .ticket_app_id_i(descriptor_app_q),
        .ticket_tweak_i(descriptor_tweak_q),
        .ticket_q_minus_one_i(descriptor_q_minus_one_q),
        .ticket_n_i(descriptor_n_q), .ticket_rounds_i(descriptor_rounds_q),
        .ticket_identity_i(descriptor_identity_q),
        .ticket_branch_count_i(descriptor_branch_count_q),
        .ticket_branch_valid_i(descriptor_branch_valid_q),
        .ticket_branch_emit_i(descriptor_branch_emit_q),
        .ticket_branch_spill_i(descriptor_branch_spill_q),
        .ticket_branch_source_limit_i(descriptor_branch_source_limit_q),
        .transaction_retire_i(descriptor_retire),
        .kt_done_valid_o(kt_done_valid), .kt_done_ready_i(kt_done_ready),
        .engine_init_active_o(engine_active),
        .key_init_active_o(key_active),
        .tweak_init_active_o(tweak_active),
        .prepare_active_o(prepare_active), .local_cycle_o(kt_local_cycle),
        .aes_active_o(kt_aes_active), .aes_mode_o(kt_aes_mode),
        .aes_ready_i(kt_aes_ready), .aes_state_o(kt_aes_state),
        .aes_key_o(kt_aes_key), .aes_result_valid_i(kt_aes_result_valid),
        .aes_result_i(kt_aes_result),
        .key_prefetch_valid_i(key_prefetch_valid),
        .key_prefetch_bank_i(key_prefetch_bank),
        .key_prefetch_index_i(key_prefetch_index),
        .current_key_o(current_key),
        .current_key_valid_o(current_key_valid),
        .current_key_bank_o(current_key_bank),
        .current_key_index_o(current_key_index),
        .local_identity_match_o(kt_identity_match)
    );

    n12_alf_round_core round_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .active_i(data_active),
        .step_i(producer_step),
        .descriptor_load_i(executable_descriptor_dispatch),
        .descriptor_identity_i(descriptor_identity_q),
        .expected_valid_i(expected_dispatch_valid_q),
        .expected_identity_i(expected_dispatch_identity_q),
        .transaction_retire_i(descriptor_retire),
        .start_i(core_start), .descriptor_decrypt_i(descriptor_decrypt_q),
        .descriptor_q_i(descriptor_q_q),
        .descriptor_n_i(descriptor_n_q), .descriptor_t_i(descriptor_t_q),
        .descriptor_rounds_i(descriptor_rounds_q),
        .descriptor_rounds_per_segment_i(descriptor_rounds_per_segment_q),
        .descriptor_segment_count_i(descriptor_segment_count_q),
        .descriptor_input_i(descriptor_input_q),
        .key_prefetch_valid_o(key_prefetch_valid),
        .key_prefetch_bank_o(key_prefetch_bank),
        .key_prefetch_index_o(key_prefetch_index),
        .current_key_i(current_key),
        .current_key_valid_i(current_key_valid),
        .current_key_bank_i(current_key_bank),
        .current_key_index_i(current_key_index),
        .aes_active_o(core_aes_active), .aes_decrypt_o(core_aes_decrypt),
        .aes_last_o(core_aes_last), .aes_state_o(core_aes_state),
        .aes_key_o(core_aes_key), .aes_result_i(core_aes_result),
        .attempt_done_o(core_attempt_done),
        .attempt_accepted_o(core_attempt_accepted),
        .attempt_segment_o(core_attempt_segment),
        .attempt_index_o(core_attempt_index),
        .attempt_first_round_o(core_attempt_first),
        .data_done_o(core_data_done), .result_o(core_result),
        .local_identity_match_o(core_identity_match)
    );

    always_comb begin
        aes_request_valid = 1'b0;
        aes_request_owner = AES_OWNER_KEY_TWEAK;
        aes_request_mode = 3'd0;
        aes_request_state = 128'h0;
        aes_request_key = 128'h0;
        if (kt_aes_active && !core_aes_active) begin
            aes_request_valid = 1'b1;
            aes_request_owner = AES_OWNER_KEY_TWEAK;
            aes_request_mode = kt_aes_mode;
            aes_request_state = kt_aes_state;
            aes_request_key = kt_aes_key;
        end else if (core_aes_active && !kt_aes_active) begin
            aes_request_valid = 1'b1;
            aes_request_owner = AES_OWNER_ROUND_CORE;
            if (core_aes_decrypt)
                aes_request_mode = core_aes_last ? 3'd3 : 3'd1;
            else
                aes_request_mode = core_aes_last ? 3'd2 : 3'd0;
            aes_request_state = core_aes_state;
            aes_request_key = core_aes_key;
        end
    end
    assign aes_capture = !aes_pending_q && aes_request_valid;
    assign producer_step = !aes_capture;
    assign phase_cycle = kt_local_cycle;
    assign kt_aes_ready = !aes_pending_q && !core_aes_active;
    // The key/tweak engine owns its outstanding bit and the shared lane has a
    // fixed one-cycle registered-request latency.  Do not re-qualify this
    // return with the top-level owner slot: that redundant decode otherwise
    // becomes a central CE broadcast over the decrypt key bank.
    // key/tweak 以本地 outstanding 位确认固定一周期 AES 返回；顶层 owner 不再二次门控密钥阵列写使能。
    assign kt_aes_result_valid = 1'b1;
    // The request fields are already registered at the AES service boundary.
    // Driving them continuously removes a wide idle-zero mux; consumers still
    // qualify the combinational result with their local outstanding/owner state.
    // AES 服务边界已寄存请求字段，持续驱动可消除宽空闲清零多路器；结果仍由本地 outstanding/owner 状态限定消费。
    assign lane_mode = aes_mode_q;
    assign lane_state = aes_state_q;
    assign lane_key = aes_key_q;
    assign kt_aes_result = lane_result;
    assign core_aes_result = (aes_pending_q &&
                              aes_owner_q == AES_OWNER_ROUND_CORE) ?
                             lane_result : 128'h0;
    assign core_start = data_active && !round_started_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aes_pending_q <= 1'b0;
            aes_owner_q <= AES_OWNER_KEY_TWEAK;
            aes_mode_q <= 3'd0;
            aes_state_q <= 128'h0;
            aes_key_q <= 128'h0;
        end else if (aes_pending_q && identity_execution_permit) begin
            aes_pending_q <= 1'b0;
        end else if (aes_capture) begin
            aes_pending_q <= 1'b1;
            aes_owner_q <= aes_request_owner;
            aes_mode_q <= aes_request_mode;
            aes_state_q <= aes_request_state;
            aes_key_q <= aes_request_key;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            round_started_q <= 1'b0;
        end else if (!data_active) begin
            round_started_q <= 1'b0;
        end else if (core_start && producer_step) begin
            round_started_q <= 1'b1;
        end
    end

`ifdef VERILATOR
    always_comb begin
        assert (!(kt_aes_active && core_aes_active))
            else $fatal(1, "shared AES lane has two active owners");
        assert (!(aes_pending_q && aes_capture))
            else $fatal(1, "shared AES lane accepted overlapping events");
    end
`endif

    n12_aes_round_lane shared_aes_lane (
        .mode_i(lane_mode), .state_i(lane_state),
        .round_key_i(lane_key), .state_o(lane_result)
    );

    assign result_valid = controller_done;
    assign result_status = controller_error ? 32'd1 : 32'd0;
    assign response_value = controller_error ? 128'h0 : result_value_q;

    // The expected epoch is the only shared transaction identity.  It is
    // captured on the same dispatch edge as each consumer's trimmed local
    // descriptor and remains valid until the complete operation retires.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            expected_dispatch_valid_q <= 1'b0;
            expected_dispatch_identity_q <= 1'b0;
        end else begin
            if (descriptor_dispatch) begin
                expected_dispatch_valid_q <= 1'b1;
                expected_dispatch_identity_q <= descriptor_identity_q;
            end
            if (descriptor_retire) begin
                expected_dispatch_valid_q <= 1'b0;
                expected_dispatch_identity_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            result_value_q <= 128'h0;
            resident_valid_q <= 1'b0;
            resident_key_q <= 128'h0;
            resident_app_q <= 64'h0;
            resident_q_q <= 128'h0;
            resident_n_q <= 4'd0;
            resident_t_q <= 3'd0;
            pending_context_valid_q <= 1'b0;
            pending_context_identity_q <= 1'b0;
            pending_context_key_q <= 128'h0;
            pending_context_app_q <= 64'h0;
            pending_context_q_q <= 128'h0;
            pending_context_n_q <= 4'd0;
            pending_context_t_q <= 3'd0;
        end else begin
            if (executable_descriptor_dispatch) begin
                pending_context_valid_q <= 1'b1;
                pending_context_identity_q <= descriptor_identity_q;
                pending_context_key_q <= descriptor_key_q;
                pending_context_app_q <= descriptor_app_q;
                pending_context_q_q <= descriptor_q_q;
                pending_context_n_q <= descriptor_n_q;
                pending_context_t_q <= descriptor_t_q;
            end
            if (core_data_done)
                result_value_q <= core_result;
            if (controller_done && result_ready && !controller_error &&
                pending_context_identity_match) begin
                resident_valid_q <= 1'b1;
                resident_key_q <= pending_context_key_q;
                resident_app_q <= pending_context_app_q;
                resident_q_q <= pending_context_q_q;
                resident_n_q <= pending_context_n_q;
                resident_t_q <= pending_context_t_q;
            end
            if (descriptor_retire) begin
                pending_context_valid_q <= 1'b0;
                pending_context_identity_q <= 1'b0;
                pending_context_key_q <= 128'h0;
                pending_context_app_q <= 64'h0;
                pending_context_q_q <= 128'h0;
                pending_context_n_q <= 4'd0;
                pending_context_t_q <= 3'd0;
            end
        end
    end
endmodule

`default_nettype wire
