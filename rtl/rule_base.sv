import fuzzy_pkg::*;

module rule_base (
  input  logic                   i_clk,
  input  logic                   i_rst_n,
  input  logic [MU_WIDTH-1:0]    i_mu_error [NUM_SETS_ERROR],
  input  logic [MU_WIDTH-1:0]    i_mu_deriv [NUM_SETS_DERIV],
  input  logic                   i_valid,
  output logic [MU_WIDTH-1:0]           o_firing_strength [NUM_RULES],
  output logic signed [OUTPUT_WIDTH-1:0] o_consequent       [NUM_RULES],
  output logic                   o_valid
);

  logic [MU_WIDTH-1:0]           w_firing [NUM_RULES];
  logic signed [OUTPUT_WIDTH-1:0] w_conseq [NUM_RULES];

  always_comb begin
    for (int e = 0; e < NUM_SETS_ERROR; e++) begin
      for (int d = 0; d < NUM_SETS_DERIV; d++) begin
        automatic int rule_idx = e * NUM_SETS_DERIV + d;
        // T-norma minimo: AND difuso
        if (i_mu_error[e] < i_mu_deriv[d])
          w_firing[rule_idx] = i_mu_error[e];
        else
          w_firing[rule_idx] = i_mu_deriv[d];
        // Consecuente Takagi-Sugeno
        w_conseq[rule_idx] = TS_CONSEQUENT[e][d];
      end
    end
  end

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      for (int r = 0; r < NUM_RULES; r++) begin
        o_firing_strength[r] <= '0;
        o_consequent[r]      <= '0;
      end
      o_valid <= 1'b0;
    end
    else begin
      if (i_valid) begin
        for (int r = 0; r < NUM_RULES; r++) begin
          o_firing_strength[r] <= w_firing[r];
          o_consequent[r]      <= w_conseq[r];
        end
      end
      o_valid <= i_valid;
    end
  end

endmodule : rule_base
