# ===========================================================================
# caudal_system.sdc — Synopsys Design Constraints
#
# Proyecto : Caudalímetro Difuso Embebido en FPGA
# Target   : Intel MAX 10 · 50 MHz
# ===========================================================================

# ── Reloj principal: 50 MHz ──
create_clock -name clk_50mhz -period 20.000 [get_ports {i_clk_50mhz}]

# ── Constraintes de entrada (señales asíncronas del sensor) ──
# El sensor es asíncrono: usamos set_false_path para que el timing
# analyzer no reporte violaciones en la cadena de sincronización
set_false_path -from [get_ports {i_sensor}] -to *

# ── Constraintes de entrada para switches (quasi-estáticos) ──
set_false_path -from [get_ports {i_sw[*]}] -to *

# ── Constraintes de entrada para reset (asíncrono) ──
set_false_path -from [get_ports {i_rst_n}] -to *

# ── Constraintes de salida ──
# Display no tiene requerimientos de timing estrictos
set_false_path -from * -to [get_ports {o_seg[*]}]
set_false_path -from * -to [get_ports {o_dig[*]}]

# ── Incertidumbre de reloj ──
derive_clock_uncertainty

# ── Multicycle Paths: Motor Difuso ──
# El fuzzifier usa divisiones combinacionales de 32 bits que no caben
# en 1 ciclo de 20 ns. El controlador fuzzy solo se actualiza a 1 Hz
# (via i_valid), por lo que la lógica tiene millones de ciclos para
# estabilizarse. Constraint de 5 ciclos: 5 × 20 ns = 100 ns.
set_multicycle_path -setup 5 -to [get_registers {fuzzy_controller:u_fuzzy_ctrl|fuzzifier:*|*}]
set_multicycle_path -hold  4 -to [get_registers {fuzzy_controller:u_fuzzy_ctrl|fuzzifier:*|*}]

set_multicycle_path -setup 5 -to [get_registers {fuzzy_controller:u_fuzzy_ctrl|rule_base:*|*}]
set_multicycle_path -hold  4 -to [get_registers {fuzzy_controller:u_fuzzy_ctrl|rule_base:*|*}]

set_multicycle_path -setup 5 -to [get_registers {fuzzy_controller:u_fuzzy_ctrl|defuzzifier:*|*}]
set_multicycle_path -hold  4 -to [get_registers {fuzzy_controller:u_fuzzy_ctrl|defuzzifier:*|*}]
