`timescale 1ns/1ps
`default_nettype none

// Serial 32-bit shell for one complete operation: collect 20 request words,
// issue once, wait for the engine, then hold five response words under
// backpressure.  Payload registers remain stable until the response retires.
// 32 位串行操作外壳：收集 20 个请求字后发起一次操作，等待内核完成，并在反压下保持 5 个响应字；
// 响应全部取走前，请求载荷寄存器保持不变。
module n12_alf_stream_frontend (
    input  logic         clk_i,
    input  logic         rst_ni,

    input  logic         req_valid_i,
    output logic         req_ready_o,
    input  logic [31:0]  req_data_i,

    output logic         request_valid_o,
    input  logic         request_ready_i,
    output logic [127:0] key_o,
    output logic [63:0]  app_id_o,
    output logic [127:0] tweak_o,
    output logic [127:0] q_o,
    output logic [127:0] q_minus_one_o,
    output logic [31:0]  config_o,
    output logic [127:0] input_o,
    output logic [31:0]  command_o,

    input  logic         result_valid_i,
    output logic         result_ready_o,
    input  logic [127:0] result_i,
    input  logic [31:0]  status_i,

    output logic         rsp_valid_o,
    input  logic         rsp_ready_i,
    output logic [31:0]  rsp_data_o
);
    typedef enum logic [1:0] {
        COLLECT      = 2'd0,
        ISSUE        = 2'd1,
        WAIT_RESULT  = 2'd2,
        RESPOND      = 2'd3
    } frontend_state_t;

    frontend_state_t state_q;
    logic [4:0] request_word_q;
    logic [2:0] response_word_q;
    logic [127:0] result_q;
    logic [31:0] status_q;
    logic q_minus_one_borrow_q;

    assign req_ready_o = (state_q == COLLECT);
    assign request_valid_o = (state_q == ISSUE);
    assign result_ready_o = (state_q == WAIT_RESULT);
    assign rsp_valid_o = (state_q == RESPOND);

    always_comb begin
        case (response_word_q)
            3'd0: rsp_data_o = result_q[31:0];
            3'd1: rsp_data_o = result_q[63:32];
            3'd2: rsp_data_o = result_q[95:64];
            3'd3: rsp_data_o = result_q[127:96];
            default: rsp_data_o = status_q;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= COLLECT;
            request_word_q <= 5'd0;
            response_word_q <= 3'd0;
            key_o <= 128'h0;
            app_id_o <= 64'h0;
            tweak_o <= 128'h0;
            q_o <= 128'h0;
            q_minus_one_o <= 128'h0;
            q_minus_one_borrow_q <= 1'b0;
            config_o <= 32'h0;
            input_o <= 128'h0;
            command_o <= 32'h0;
            result_q <= 128'h0;
            status_q <= 32'h0;
        end else begin
            case (state_q)
                COLLECT: begin
                    if (req_valid_i && req_ready_o) begin
                        case (request_word_q)
                            5'd0:  key_o[31:0] <= req_data_i;
                            5'd1:  key_o[63:32] <= req_data_i;
                            5'd2:  key_o[95:64] <= req_data_i;
                            5'd3:  key_o[127:96] <= req_data_i;
                            5'd4:  app_id_o[31:0] <= req_data_i;
                            5'd5:  app_id_o[63:32] <= req_data_i;
                            5'd6:  tweak_o[31:0] <= req_data_i;
                            5'd7:  tweak_o[63:32] <= req_data_i;
                            5'd8:  tweak_o[95:64] <= req_data_i;
                            5'd9:  tweak_o[127:96] <= req_data_i;
                            5'd10: begin
                                q_o[31:0] <= req_data_i;
                                q_minus_one_o[31:0] <= req_data_i - 32'd1;
                                q_minus_one_borrow_q <= (req_data_i == 32'd0);
                            end
                            5'd11: begin
                                q_o[63:32] <= req_data_i;
                                q_minus_one_o[63:32] <=
                                    req_data_i - {31'd0, q_minus_one_borrow_q};
                                q_minus_one_borrow_q <=
                                    q_minus_one_borrow_q && (req_data_i == 32'd0);
                            end
                            5'd12: begin
                                q_o[95:64] <= req_data_i;
                                q_minus_one_o[95:64] <=
                                    req_data_i - {31'd0, q_minus_one_borrow_q};
                                q_minus_one_borrow_q <=
                                    q_minus_one_borrow_q && (req_data_i == 32'd0);
                            end
                            5'd13: begin
                                q_o[127:96] <= req_data_i;
                                q_minus_one_o[127:96] <=
                                    req_data_i - {31'd0, q_minus_one_borrow_q};
                                q_minus_one_borrow_q <= 1'b0;
                            end
                            5'd14: config_o <= req_data_i;
                            5'd15: input_o[31:0] <= req_data_i;
                            5'd16: input_o[63:32] <= req_data_i;
                            5'd17: input_o[95:64] <= req_data_i;
                            5'd18: input_o[127:96] <= req_data_i;
                            default: command_o <= req_data_i;
                        endcase
                        if (request_word_q == 5'd19) begin
                            request_word_q <= 5'd0;
                            state_q <= ISSUE;
                        end else begin
                            request_word_q <= request_word_q + 1'b1;
                        end
                    end
                end

                ISSUE: begin
                    if (request_valid_o && request_ready_i)
                        state_q <= WAIT_RESULT;
                end

                WAIT_RESULT: begin
                    if (result_valid_i && result_ready_o) begin
                        result_q <= result_i;
                        status_q <= status_i;
                        response_word_q <= 3'd0;
                        state_q <= RESPOND;
                    end
                end

                RESPOND: begin
                    if (rsp_valid_o && rsp_ready_i) begin
                        if (response_word_q == 3'd4) begin
                            response_word_q <= 3'd0;
                            state_q <= COLLECT;
                        end else begin
                            response_word_q <= response_word_q + 1'b1;
                        end
                    end
                end

                default: state_q <= COLLECT;
            endcase
        end
    end
endmodule

`default_nettype wire
