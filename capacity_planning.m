function results = capacity_planning(params)
% CAPACITY_PLANNING  Price-optimal sizing of a grid-responsive data center
% under the chance-constraint reformulation (Koksal / Wenqi two-layer model).
%
% Pure CAPACITY PLANNING -- no time-indexed dispatch. Hardware is sized
% against statistical load descriptors. The "serve at every instant"
% requirement is replaced by a chance constraint: meet aggregate demand
% with probability 1 - eps. Under Gaussian aggregation this is a closed-form
% inequality with no time index (this is the move that removes the DP).
%
% Two-layer architecture:
%   Slow layer  : grid feed + BESS  -> mean load + slow fluctuations
%   Fast layer  : per-rack supercaps -> fast GPU/load bursts the BESS
%                 cannot ramp to
%
% DECISION VARIABLES
%   N        number of servers/racks                 (integer, enumerated --
%            the problem is not assumed jointly convex in N)
%   C_bess   BESS energy capacity            [kWh]
%   P_bess   BESS power rating               [kW]
%   C_sc_i   per-rack supercap capacity      [kWh]   (identical racks -> scalar)
%   P_ref    grid feed (connection) sizing   [kW]
%
% For each fixed N the remaining variables have closed-form optima (all
% costs increase with capacity, so the chance constraints are binding at
% the optimum), which reduces the search to a 1-D enumeration over N.
%
% OBJECTIVE  (minimize total cost over the horizon)
%   c_server*N + c_bess_E*C_bess + c_bess_P*P_bess + N*c_sc*C_sc_i
%     + c_grid_P*P_ref + price_grid*E_grid + J_track
% where J_track = lambda_track * E[energy exceeding the BESS band].
%
% CHANCE CONSTRAINT (slow layer)
%   Aggregate load L ~ N(mu_agg, sigma_agg^2) with
%     mu_agg    = N*mu
%     sigma_agg = sigma * sqrt( N*(1 + (N-1)*rho) )   (equicorrelated racks)
%   Require  P[ L > P_ref + P_bess ] <= eps.  With P_ref = mu_agg this gives
%     P_bess >= z * sigma_agg,   z = Phi^-1(1 - eps)
%   and BESS energy sized to sustain that band over the balancing window:
%     C_bess = P_bess * tau_bess.
%
% UNITS  power [kW], energy [kWh], time [h], money [$]. Mixing scales
% (e.g. MW loads with kWh prices) silently gives wrong answers.
%
% PARAMS (struct; defaults below)
%  Load statistics (per rack):
%   .mu          mean compute load per rack          [kW]
%   .sigma       std of slow load fluctuation        [kW]
%   .rho         inter-rack correlation, 0..1        [-]
%   .burst_amp   burst amplitude (fast layer)        [kW]
%   .tau_sc      supercap ride-through window        [h]
%   .tau_bess    BESS balancing window               [h]
%  Reliability:
%   .eps         chance-constraint violation prob    (0 < eps < 0.5)
%  Costs:
%   .c_server    $/server
%   .c_bess_E    $/kWh BESS energy
%   .c_bess_P    $/kW  BESS power
%   .c_sc        $/kWh supercap
%   .c_grid_P    $/kW  grid feed / connection        (default 0)
%   .price_grid  $/kWh grid energy
%   .horizon_h   operating hours for energy cost     (default 10*8760)
%   .lambda_track $/kWh penalty on expected energy exceeding the BESS
%                 band (VoLL-style; default 0)
%  Search:
%   .N_range     candidate server counts to search   (default 1:200)
%   .demand_total fixed total compute demand to serve [kW]. REQUIRED for a
%                 meaningful optimum: without it every cost term grows with
%                 N and the minimizer is trivially the smallest N.
%   .make_plot   draw diagnostic figure              (default true)
%   .verbose     print the console report            (default true)

if nargin < 1, params = struct(); end
def = struct( ...
  'mu',5,'sigma',2,'rho',0.2,'burst_amp',6,'tau_sc',1/120,'tau_bess',0.25, ...
  'eps',0.01, ...
  'c_server',8000,'c_bess_E',200,'c_bess_P',300,'c_sc',8000,'c_grid_P',0, ...
  'price_grid',0.10,'horizon_h',10*8760,'lambda_track',0, ...
  'N_range',1:200,'demand_total',[],'make_plot',true,'verbose',true);
fn = fieldnames(def);
for j = 1:numel(fn)
    if ~isfield(params,fn{j}), params.(fn{j}) = def.(fn{j}); end
end
p = params;

% ---- input validation ---------------------------------------------------
if ~(isscalar(p.mu) && p.mu > 0)
    error('capacity_planning:badParam','mu must be a scalar > 0 [kW per rack].');
end
if ~(isscalar(p.sigma) && p.sigma >= 0)
    error('capacity_planning:badParam','sigma must be a scalar >= 0 [kW].');
end
if ~(isscalar(p.rho) && p.rho >= 0 && p.rho <= 1)
    error('capacity_planning:badParam', ...
        'rho must be in [0,1] (negative correlations not supported).');
end
if ~(isscalar(p.eps) && p.eps > 0 && p.eps < 0.5)
    error('capacity_planning:badParam', ...
        'eps must be in (0, 0.5) so that z = Phi^{-1}(1-eps) > 0.');
end
if ~(p.burst_amp >= 0 && p.tau_sc > 0 && p.tau_bess > 0)
    error('capacity_planning:badParam', ...
        'burst_amp must be >= 0 and tau_sc, tau_bess > 0 [h].');
end
costs = [p.c_server p.c_bess_E p.c_bess_P p.c_sc p.c_grid_P ...
         p.price_grid p.horizon_h p.lambda_track];
if ~(all(isfinite(costs)) && all(costs >= 0))
    error('capacity_planning:badParam','all cost parameters must be finite and >= 0.');
end
if isempty(p.N_range) || any(p.N_range < 1) || any(p.N_range ~= round(p.N_range))
    error('capacity_planning:badParam','N_range must be positive integers.');
end
if ~isempty(p.demand_total) && ~(isscalar(p.demand_total) && p.demand_total > 0)
    error('capacity_planning:badParam','demand_total must be a positive scalar [kW] or [].');
end

% Gaussian quantile z_{1-eps}. Uses erfcinv (base MATLAB/Octave) instead of
% norminv, so the Statistics Toolbox is NOT required:
%   norminv(q) == -sqrt(2)*erfcinv(2q)
z = -sqrt(2) * erfcinv(2*(1 - p.eps));

Ns = p.N_range(:);
M  = numel(Ns);

C_bess = zeros(M,1); P_bess = zeros(M,1); C_sc = zeros(M,1);
P_ref  = zeros(M,1); sigma_agg = zeros(M,1);
cost_server = zeros(M,1); cost_bess = zeros(M,1); cost_sc = zeros(M,1);
cost_feed = zeros(M,1); cost_grid = zeros(M,1); cost_track = zeros(M,1);
total = zeros(M,1);

for m = 1:M
    N = Ns(m);

    % aggregate load statistics (statistical multiplexing)
    mu_agg  = N * p.mu;
    s_agg   = sqrt( N * p.sigma^2 * (1 + (N-1)*p.rho) );   % sigma_agg(N)
    sigma_agg(m) = s_agg;

    % ---- SLOW LAYER ----------------------------------------------------
    % Grid feed: flat feed covering the mean aggregate load.
    P_ref(m) = mu_agg;

    % BESS power rating: binding chance constraint
    %   P[ load > P_ref + P_bess ] <= eps  ->  P_bess = z * sigma_agg
    P_bess(m) = z * s_agg;

    % BESS energy: sustain the fluctuation band over the balancing window.
    C_bess(m) = P_bess(m) * p.tau_bess;

    % ---- FAST LAYER ----------------------------------------------------
    % Per-rack supercap rides through one worst-case burst. Supercaps are
    % power-dense, so only their energy (not power) is costed.
    C_sc(m) = p.burst_amp * p.tau_sc;     % per rack [kWh]

    % ---- COST ----------------------------------------------------------
    cost_server(m) = p.c_server * N;
    cost_bess(m)   = p.c_bess_E*C_bess(m) + p.c_bess_P*P_bess(m);
    cost_sc(m)     = N * p.c_sc * C_sc(m);
    cost_feed(m)   = p.c_grid_P * P_ref(m);

    % grid energy: mean aggregate power over the horizon (fluctuations have
    % zero mean; BESS round-trip losses neglected)
    E_grid = mu_agg * p.horizon_h;        % kWh
    cost_grid(m) = p.price_grid * E_grid;

    % tracking penalty: expected load exceedance beyond the BESS band,
    % the Gaussian partial moment
    %   E[(L - P_ref - P_bess)^+] = sigma_agg * ( phi(z) - z*(1 - Phi(z)) )
    % with 1 - Phi(z) = eps by construction. lambda_track prices this
    % expected unserved energy over the horizon [$ / kWh, VoLL-style].
    phi_z = exp(-z^2/2) / sqrt(2*pi);
    resid_kW = s_agg * (phi_z - z*p.eps);
    cost_track(m) = p.lambda_track * resid_kW * p.horizon_h;

    total(m) = cost_server(m) + cost_bess(m) + cost_sc(m) ...
             + cost_feed(m) + cost_grid(m) + cost_track(m);
end

% ---- demand feasibility -------------------------------------------------
% Only N with enough compute capacity (N*mu >= demand_total) qualify.
feasible = true(M,1);
if ~isempty(p.demand_total)
    feasible = (Ns * p.mu) >= p.demand_total;
    if ~any(feasible)
        error('capacity_planning:infeasible', ...
            ['No N in N_range can serve demand_total = %.1f kW ' ...
             '(max(N_range)*mu = %.1f kW). Extend N_range or lower demand_total.'], ...
            p.demand_total, max(Ns)*p.mu);
    end
else
    warning('capacity_planning:noDemandTarget', ...
        ['demand_total is empty: every cost term increases with N, so the ' ...
         '"optimum" is trivially the smallest N in N_range. Set ' ...
         'params.demand_total [kW] for a meaningful sizing.']);
end

cost_feas = total;
cost_feas(~feasible) = Inf;
[~, idx] = min(cost_feas);

% ---- pack ---------------------------------------------------------------
results.N          = Ns;
results.feasible   = feasible;
results.sigma_agg  = sigma_agg;
results.C_bess     = C_bess;
results.P_bess     = P_bess;
results.C_sc       = C_sc;
results.P_ref      = P_ref;
results.cost_server= cost_server;
results.cost_bess  = cost_bess;
results.cost_sc    = cost_sc;
results.cost_feed  = cost_feed;
results.cost_grid  = cost_grid;
results.cost_track = cost_track;
results.total      = total;
results.z          = z;
results.params     = p;

b = idx;
capex_b = cost_server(b) + cost_bess(b) + cost_sc(b) + cost_feed(b);
results.best = struct('N',Ns(b),'C_bess',C_bess(b),'P_bess',P_bess(b), ...
   'C_sc_per_rack',C_sc(b),'C_sc_total',Ns(b)*C_sc(b),'P_ref',P_ref(b), ...
   'sigma_agg',sigma_agg(b),'capex',capex_b, ...
   'grid',cost_grid(b),'track',cost_track(b),'total',total(b));

% ---- report -------------------------------------------------------------
if p.verbose
fprintf('\n=== Capacity Planning (chance-constraint, eps=%.3f, z=%.3f) ===\n', p.eps, z);
if ~isempty(p.demand_total)
    fprintf('Demand target    : %.1f kW  (min feasible N = %d)\n', ...
            p.demand_total, min(Ns(feasible)));
end
fprintf('Optimal N        : %d servers\n', results.best.N);
fprintf('P_ref (grid feed): %.2f kW   (mean aggregate load)\n', results.best.P_ref);
fprintf('P_bess           : %.2f kW   (z*sigma_agg fluctuation band)\n', results.best.P_bess);
fprintf('C_bess           : %.2f kWh  (band sustained for %.0f min)\n', ...
        results.best.C_bess, p.tau_bess*60);
fprintf('C_sc (per rack)  : %.4f kWh  (total %.2f kWh, %.0f-s burst ride-through)\n', ...
        results.best.C_sc_per_rack, results.best.C_sc_total, p.tau_sc*3600);
sig_nomux = results.best.N * p.sigma;
fprintf('sigma_agg        : %.2f kW   (vs %.2f kW unmultiplexed: %.0f%% smaller)\n', ...
        results.best.sigma_agg, sig_nomux, 100*(1 - results.best.sigma_agg/max(sig_nomux,eps)));
fprintf('---\n');
fprintf('Capex (srv+BESS+SC+feed) : $%.0f\n', results.best.capex);
fprintf('Grid energy (%.0f yr)     : $%.0f\n', p.horizon_h/8760, results.best.grid);
if p.lambda_track > 0
    fprintf('Tracking penalty         : $%.0f\n', results.best.track);
end
fprintf('TOTAL                    : $%.0f\n', results.best.total);
end

% ---- plot ---------------------------------------------------------------
if p.make_plot
    figure('Name','Capacity planning cost vs N');

    subplot(1,2,1);
    h = plot(Ns, total/1e6,'-','LineWidth',1.4); hold on;
    h(2) = plot(Ns, (cost_server+cost_bess+cost_sc+cost_feed)/1e6,'--');
    h(3) = plot(Ns, cost_grid/1e6,'--');
    h(4) = plot(Ns(b), total(b)/1e6,'r*','MarkerSize',12,'LineWidth',1.5);
    lab = {'total','capex','grid energy','optimum'};
    if ~isempty(p.demand_total)
        yl = ylim;
        Nmin_dem = min(Ns(feasible));
        h(5) = plot([Nmin_dem Nmin_dem], yl, 'k:','LineWidth',1.2);
        lab{5} = sprintf('min feasible N = %d', Nmin_dem);
    end
    xlabel('N servers'); ylabel('cost over horizon [$M]');
    legend(h, lab, 'Location','northwest'); grid on;
    title('Total cost vs N (left of dotted line: infeasible)');

    subplot(1,2,2);
    plot(Ns, sigma_agg,'-','LineWidth',1.4); hold on;
    plot(Ns, Ns*p.sigma,'--','LineWidth',1.0);
    xlabel('N servers'); ylabel('kW');
    legend('\sigma_{agg} (multiplexed)','\Sigma\sigma (no mux)','Location','northwest');
    grid on; title('Statistical multiplexing');
end
end
