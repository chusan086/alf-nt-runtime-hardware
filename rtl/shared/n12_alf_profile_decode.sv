`timescale 1ns/1ps
`default_nettype none

// Checks the complete legal ALF (n,t,Q) domain and returns its round count.
// Q remains a runtime value; only the profile-to-round mapping is tabulated.
// 检查完整的 ALF 合法 (n,t,Q) 域并给出轮数。Q 始终为运行时参数，表中只固化参数到轮数的映射。
module n12_alf_profile_decode (
    input  logic [127:0] q_i,
    input  logic [3:0]   n_i,
    input  logic [2:0]   t_i,
    output logic         valid_o,
    output logic [4:0]   rounds_o
);
    import n12_alf_v0_tables_pkg::*;

    logic [6:0]   u;
    logic [127:0] lower_bound;
    logic [127:0] upper_bound;

    always_comb begin
        valid_o = 1'b0;
        rounds_o = 5'd0;
        u = 7'd0;
        lower_bound = 128'd0;
        upper_bound = 128'd0;
        if ((n_i >= 4'd2) && (n_i <= 4'd15)) begin
            u = {n_i, t_i};
            lower_bound = 128'h1 << (u - 7'd1);
            upper_bound = 128'h1 << u;
            if ((q_i > lower_bound) && (q_i <= upper_bound)) begin
                valid_o = 1'b1;
                rounds_o = profile_rounds(n_i, t_i);
            end
        end
    end
endmodule

`default_nettype wire
