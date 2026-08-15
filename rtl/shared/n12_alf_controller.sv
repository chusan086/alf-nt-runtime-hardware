`timescale 1ns/1ps
`default_nettype none

// Operation-level dispatcher.  After validation it transfers one immutable
// key/tweak ticket, waits only for local completion, then runs the unchanged
// data core and response-finalization sequence.
module n12_alf_controller (
    input  logic       clk_i,
    input  logic       rst_ni,

    input  logic       start_valid_i,
    output logic       start_ready_o,
    input  logic       dispatch_valid_i,
    input  logic       dispatch_identity_i,
    input  logic       expected_valid_i,
    input  logic       expected_identity_i,
    input  logic       execution_permit_i,
    input  logic       syntax_valid_i,
    input  logic       domain_valid_i,
    input  logic [4:0] rounds_i,

    output logic       kt_start_valid_o,
    input  logic       kt_start_ready_i,
    input  logic       kt_done_valid_i,
    output logic       kt_done_ready_o,

    // The round core asserts this during DATA on the last required data cycle.
    input  logic       data_done_i,

    output logic       done_valid_o,
    input  logic       done_ready_i,
    output logic       error_o,

    output logic [3:0] phase_o,
    output logic       validate_active_o,
    output logic       data_active_o,
    output logic       finalize_active_o,
    output logic       local_identity_match_o
);
    localparam logic [3:0] PH_IDLE     = 4'd0;
    localparam logic [3:0] PH_VALIDATE = 4'd1;
    localparam logic [3:0] PH_WAIT_KT  = 4'd2;
    localparam logic [3:0] PH_DATA     = 4'd6;
    localparam logic [3:0] PH_FINALIZE = 4'd7;
    localparam logic [3:0] PH_DONE     = 4'd8;

    logic [3:0] state_q;
    logic error_q;
    logic local_validated;
    logic local_descriptor_valid_q;
    logic local_descriptor_identity_q;
    logic local_syntax_valid_q;
    logic local_domain_valid_q;
    logic [4:0] local_rounds_q;

    assign local_validated = local_syntax_valid_q && local_domain_valid_q &&
                             (local_rounds_q != 5'd0);
    assign local_identity_match_o = local_descriptor_valid_q &&
                                    expected_valid_i &&
                                    (local_descriptor_identity_q ==
                                     expected_identity_i);
    assign start_ready_o = (state_q == PH_IDLE);
    assign kt_start_valid_o = (state_q == PH_VALIDATE) &&
                              local_identity_match_o && local_validated &&
                              execution_permit_i;
    assign kt_done_ready_o = (state_q == PH_WAIT_KT) && execution_permit_i;
    assign done_valid_o = (state_q == PH_DONE) &&
                          (error_q || execution_permit_i);
    assign error_o = error_q;
    assign phase_o = state_q;
    assign validate_active_o = (state_q == PH_VALIDATE);
    assign data_active_o = (state_q == PH_DATA) && execution_permit_i;
    assign finalize_active_o = (state_q == PH_FINALIZE) &&
                               (error_q || execution_permit_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= PH_IDLE;
            error_q <= 1'b0;
            local_descriptor_valid_q <= 1'b0;
            local_descriptor_identity_q <= 1'b0;
            local_syntax_valid_q <= 1'b0;
            local_domain_valid_q <= 1'b0;
            local_rounds_q <= 5'd0;
        end else begin
            case (state_q)
                PH_IDLE: begin
                    if (start_valid_i && start_ready_o) begin
                        error_q <= 1'b0;
                        state_q <= PH_VALIDATE;
                    end
                end

                PH_VALIDATE: begin
                    if (dispatch_valid_i) begin
                        local_descriptor_valid_q <= 1'b1;
                        local_descriptor_identity_q <= dispatch_identity_i;
                        local_syntax_valid_q <= syntax_valid_i;
                        local_domain_valid_q <= domain_valid_i;
                        local_rounds_q <= rounds_i;
                    end else if (local_identity_match_o) begin
                        if (!local_validated) begin
                            error_q <= 1'b1;
                            state_q <= PH_FINALIZE;
                        end else if (kt_start_valid_o && kt_start_ready_i) begin
                            state_q <= PH_WAIT_KT;
                        end
                    end
                end

                PH_WAIT_KT: begin
                    if (kt_done_valid_i && kt_done_ready_o)
                        state_q <= PH_DATA;
                end

                PH_DATA: begin
                    if (data_done_i)
                        state_q <= PH_FINALIZE;
                end

                PH_FINALIZE: begin
                    if (error_q || execution_permit_i)
                        state_q <= PH_DONE;
                end

                PH_DONE: begin
                    if (done_valid_o && done_ready_i) begin
                        state_q <= PH_IDLE;
                        local_descriptor_valid_q <= 1'b0;
                        local_descriptor_identity_q <= 1'b0;
                        local_syntax_valid_q <= 1'b0;
                        local_domain_valid_q <= 1'b0;
                        local_rounds_q <= 5'd0;
                    end
                end

                default: begin
                    state_q <= PH_IDLE;
                    error_q <= 1'b1;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
