function r = simulate_bess_dispatch(L, P_ref, dt_h, sizing, dcfg)
% SIMULATE_BESS_DISPATCH  Greedy time-indexed dispatch of a sized BESS.
% Validates whether the closed-form sizing actually tracks the grid
% reference on a load trace once SOC limits and efficiency are real.
%
%   r = simulate_bess_dispatch(L, P_ref, dt_h, sizing, dcfg)
%
%   L      T x 1 aggregate load to serve [kW]
%   P_ref  T x 1 (or scalar) grid reference the site may draw [kW]
%   dt_h   time step [h]
%   sizing struct: .P_bess [kW], .C_bess [kWh]  (from capacity_planning)
%   dcfg   struct: .eta_rt, .soc0, .soc_min, .soc_max, .unmet_tol_kW
%
% Dispatch rule per step (greedy, no foresight):
%   deficit  d = L - P_ref > 0  -> discharge up to power, energy, SOC limits
%   surplus  d < 0              -> recharge from unused grid headroom
% Round-trip efficiency eta_rt is split sqrt/sqrt between charge and
% discharge. Whatever the BESS cannot cover is 'unmet' (in reality: demand
% response, curtailment, or an SLA violation).
%
% Returns:
%   .soc, .p_bess (+discharge/-charge), .unmet   T x 1 series
%   .violation_rate   fraction of steps with unmet > tol  (empirical)
%   .band_exceed_rate fraction of steps with L > P_ref + P_bess
%                     (what the marginal chance constraint bounds by eps)
%   .peak_unmet_kW, .unmet_energy_kWh, .soc_at_min_frac, .throughput_kWh

P   = sizing.P_bess;
C   = sizing.C_bess;
if C <= 0 || P < 0
    error('simulate_bess_dispatch:badSizing', 'need C_bess > 0 and P_bess >= 0');
end
eta = sqrt(dcfg.eta_rt);
T   = numel(L);
if isscalar(P_ref), P_ref = repmat(P_ref, T, 1); end

E    = dcfg.soc0    * C;
Emin = dcfg.soc_min * C;
Emax = dcfg.soc_max * C;

soc    = zeros(T,1);
p_bess = zeros(T,1);
unmet  = zeros(T,1);

for k = 1:T
    d = L(k) - P_ref(k);
    if d >= 0
        % discharge: limited by rating, and by usable energy above Emin
        p_dis = min([d, P, (E - Emin) * eta / dt_h]);
        E = E - p_dis * dt_h / eta;
        p_bess(k) = p_dis;
        unmet(k)  = d - p_dis;
    else
        % charge from grid headroom: limited by rating and room below Emax
        p_ch = min([-d, P, (Emax - E) / (eta * dt_h)]);
        E = E + p_ch * dt_h * eta;
        p_bess(k) = -p_ch;
    end
    soc(k) = E / C;
end

r.soc    = soc;
r.p_bess = p_bess;
r.unmet  = unmet;
r.violation_rate   = mean(unmet > dcfg.unmet_tol_kW);
r.band_exceed_rate = mean(L > P_ref + P);
r.peak_unmet_kW    = max([unmet; 0]);
r.unmet_energy_kWh = sum(unmet) * dt_h;
r.soc_at_min_frac  = mean(soc <= dcfg.soc_min + 1e-9);
r.throughput_kWh   = sum(abs(p_bess)) * dt_h;
end
