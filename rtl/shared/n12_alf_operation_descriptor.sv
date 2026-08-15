`timescale 1ns/1ps
`default_nettype none

// Captures one complete request as an immutable operation descriptor.  Raw
// request fields and combinational profile decode terminate at this bank.
module n12_alf_operation_descriptor (
    input  logic         clk_i,
    input  logic         rst_ni,
    input  logic         capture_i,
    input  logic         dispatch_i,
    input  logic         retire_i,
    input  logic         syntax_valid_i,
    input  logic [127:0] key_i,
    input  logic [63:0]  app_id_i,
    input  logic [127:0] tweak_i,
    input  logic [127:0] q_i,
    input  logic [127:0] q_minus_one_i,
    input  logic [3:0]   n_i,
    input  logic [2:0]   t_i,
    input  logic         decrypt_i,
    input  logic         cycle_walking_i,
    input  logic         cold_i,
    input  logic [127:0] input_i,

    output logic         valid_o,
    output logic         payload_valid_o,
    output logic         identity_o,
    output logic         syntax_valid_o,
    output logic         domain_valid_o,
    output logic [127:0] key_o,
    output logic [63:0]  app_id_o,
    output logic [127:0] tweak_o,
    output logic [127:0] q_o,
    output logic [127:0] q_minus_one_o,
    output logic [3:0]   n_o,
    output logic [2:0]   t_o,
    output logic         decrypt_o,
    output logic         cycle_walking_o,
    output logic         cold_o,
    output logic [127:0] input_o,
    output logic [4:0]   rounds_o,
    output logic [4:0]   rounds_per_segment_o,
    output logic [4:0]   segment_count_o,
    output logic [8:0]   total_key_bytes_o,
    output logic [2:0]   branch_count_o,
    output logic [44:0]  branch_remaining_bytes_o,
    output logic [34:0]  branch_valid_bytes_o,
    output logic [24:0]  branch_emit_count_o,
    output logic [19:0]  branch_spill_after_o,
    output logic [34:0]  branch_source_limit_o
);
    logic request_domain_valid;
    logic [4:0] request_rounds_unused;
    logic schedule_pending_q;
    logic [6:0] schedule_address_d;
    logic [176:0] profile_schedule_q;

    n12_alf_profile_decode request_profile_decode (
        .q_i(q_i), .n_i(n_i), .t_i(t_i),
        .valid_o(request_domain_valid), .rounds_o(request_rounds_unused)
    );

    // Q terminates in domain validation.  The synchronous ROM address depends
    // only on the finite legal profile key {n,t}; one read/prepare cycle then
    // transfers the selected constant row into the descriptor bank.
    assign schedule_address_d = {(n_i - 4'd2), t_i};

    n12_alf_descriptor_schedule_rom schedule_rom (
        .clk_i(clk_i), .address_i(schedule_address_d),
        .data_o(profile_schedule_q)
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_o <= 1'b0;
            payload_valid_o <= 1'b0;
            schedule_pending_q <= 1'b0;
            identity_o <= 1'b0;
            syntax_valid_o <= 1'b0;
            domain_valid_o <= 1'b0;
            key_o <= 128'h0;
            app_id_o <= 64'h0;
            tweak_o <= 128'h0;
            q_o <= 128'h0;
            q_minus_one_o <= 128'h0;
            n_o <= 4'd0;
            t_o <= 3'd0;
            decrypt_o <= 1'b0;
            cycle_walking_o <= 1'b0;
            cold_o <= 1'b1;
            input_o <= 128'h0;
            rounds_o <= 5'd0;
            rounds_per_segment_o <= 5'd0;
            segment_count_o <= 5'd0;
            total_key_bytes_o <= 9'd0;
            branch_count_o <= 3'd0;
            branch_remaining_bytes_o <= 45'd0;
            branch_valid_bytes_o <= 35'd0;
            branch_emit_count_o <= 25'd0;
            branch_spill_after_o <= 20'd0;
            branch_source_limit_o <= 35'd0;
        end else if (capture_i) begin
            valid_o <= 1'b1;
            payload_valid_o <= 1'b0;
            schedule_pending_q <= 1'b1;
            identity_o <= ~identity_o;
            syntax_valid_o <= syntax_valid_i;
            domain_valid_o <= request_domain_valid;
            key_o <= key_i;
            app_id_o <= app_id_i;
            tweak_o <= tweak_i;
            q_o <= q_i;
            q_minus_one_o <= q_minus_one_i;
            n_o <= n_i;
            t_o <= t_i;
            decrypt_o <= decrypt_i;
            cycle_walking_o <= cycle_walking_i;
            cold_o <= cold_i;
            input_o <= input_i;
            rounds_o <= 5'd0;
            rounds_per_segment_o <= 5'd0;
            segment_count_o <= 5'd0;
            total_key_bytes_o <= 9'd0;
            branch_count_o <= 3'd0;
            branch_remaining_bytes_o <= 45'd0;
            branch_valid_bytes_o <= 35'd0;
            branch_emit_count_o <= 25'd0;
            branch_spill_after_o <= 20'd0;
            branch_source_limit_o <= 35'd0;
        end else if (schedule_pending_q) begin
            payload_valid_o <= 1'b1;
            schedule_pending_q <= 1'b0;
            if (domain_valid_o) begin
                rounds_o <= profile_schedule_q[176:172];
                rounds_per_segment_o <= cycle_walking_o ?
                    profile_schedule_q[176:172] : 5'd2;
                segment_count_o <= cycle_walking_o ?
                    5'd1 : (profile_schedule_q[176:172] >> 1);
                total_key_bytes_o <= profile_schedule_q[171:163];
                branch_count_o <= profile_schedule_q[162:160];
                branch_remaining_bytes_o <= profile_schedule_q[159:115];
                branch_valid_bytes_o <= profile_schedule_q[114:80];
                branch_emit_count_o <= profile_schedule_q[79:55];
                branch_spill_after_o <= profile_schedule_q[54:35];
                branch_source_limit_o <= profile_schedule_q[34:0];
            end
        end else if (dispatch_i) begin
            payload_valid_o <= 1'b0;
            schedule_pending_q <= 1'b0;
            syntax_valid_o <= 1'b0;
            domain_valid_o <= 1'b0;
            key_o <= 128'h0;
            app_id_o <= 64'h0;
            tweak_o <= 128'h0;
            q_o <= 128'h0;
            q_minus_one_o <= 128'h0;
            n_o <= 4'd0;
            t_o <= 3'd0;
            decrypt_o <= 1'b0;
            cycle_walking_o <= 1'b0;
            cold_o <= 1'b1;
            input_o <= 128'h0;
            rounds_o <= 5'd0;
            rounds_per_segment_o <= 5'd0;
            segment_count_o <= 5'd0;
            total_key_bytes_o <= 9'd0;
            branch_count_o <= 3'd0;
            branch_remaining_bytes_o <= 45'd0;
            branch_valid_bytes_o <= 35'd0;
            branch_emit_count_o <= 25'd0;
            branch_spill_after_o <= 20'd0;
            branch_source_limit_o <= 35'd0;
        end else if (retire_i) begin
            valid_o <= 1'b0;
            payload_valid_o <= 1'b0;
            schedule_pending_q <= 1'b0;
            syntax_valid_o <= 1'b0;
            domain_valid_o <= 1'b0;
            key_o <= 128'h0;
            app_id_o <= 64'h0;
            tweak_o <= 128'h0;
            q_o <= 128'h0;
            q_minus_one_o <= 128'h0;
            n_o <= 4'd0;
            t_o <= 3'd0;
            decrypt_o <= 1'b0;
            cycle_walking_o <= 1'b0;
            cold_o <= 1'b1;
            input_o <= 128'h0;
            rounds_o <= 5'd0;
            rounds_per_segment_o <= 5'd0;
            segment_count_o <= 5'd0;
            total_key_bytes_o <= 9'd0;
            branch_count_o <= 3'd0;
            branch_remaining_bytes_o <= 45'd0;
            branch_valid_bytes_o <= 35'd0;
            branch_emit_count_o <= 25'd0;
            branch_spill_after_o <= 20'd0;
            branch_source_limit_o <= 35'd0;
        end
    end
endmodule

`default_nettype wire
