function test_summer_extension
% TEST_SUMMER_EXTENSION  Fast checks for the summer-extension modules.
% Base MATLAB/Octave, no toolboxes. Run:  test_summer_extension
% Uses a shrunken config and a scratch outputs dir (removed at the end).

% ---- 0. original baseline still works ------------------------------------
test_capacity_planning;   % the original suite must keep passing

cfg = config_summer();
cfg.out.dir     = 'outputs_test';
cfg.out.fig_dir = fullfile('outputs_test','figures');
cfg.trace.days  = 0.25;          % 6 h trace
cfg.trace.n_racks = 20;
cfg.sweep.rho_grid      = [0 0.4];
cfg.sweep.eps_grid      = [0.01 0.05];
cfg.sweep.c_bess_P_grid = [200 400];
cfg.sweep.c_bess_E_grid = [150 300];
cfg.sweep.demand_grid   = [300 600];
cfg.sweep.N_grid        = [50 100];
cfg.mc.rho_scenarios = 0.2;
cfg.mc.eps_scenarios = 0.05;
cfg.mc.trials = 3;  cfg.mc.steps = 4000;
if ~exist(cfg.out.dir,'dir'),     mkdir(cfg.out.dir);     end
if ~exist(cfg.out.fig_dir,'dir'), mkdir(cfg.out.fig_dir); end

% ---- 1. baseline: no negative capacities ---------------------------------
res = capacity_planning(cfg.baseline);
assert(all(res.C_bess >= 0) && all(res.P_bess >= 0) && ...
       all(res.C_sc >= 0)   && all(res.P_ref >= 0), 'negative capacity');
assert(res.best.N == ceil(cfg.baseline.demand_total/cfg.baseline.mu));

% ---- 2. traces: shape, nonnegativity, reproducibility, file ---------------
tr1 = generate_load_traces(cfg, res.best.N);
tr2 = generate_load_traces(cfg, res.best.N);
assert(size(tr1.rack_slow,2) == cfg.trace.n_racks, 'rack count');
assert(all(tr1.agg_total >= 0), 'negative load');
assert(max(abs(tr1.agg_total - tr2.agg_total)) == 0, 'seed not reproducible');
assert(exist(fullfile(cfg.out.dir,'synthetic_load_traces.csv'),'file') == 2);

% ---- 3. dispatch: SOC bounds, power limits, violation counting -----------
sizing = struct('P_bess', res.best.P_bess, 'C_bess', res.best.C_bess);
dr = simulate_bess_dispatch(tr1.agg_slow, tr1.P_forecast, tr1.dt_h, ...
                            sizing, cfg.dispatch);
assert(all(dr.soc >= cfg.dispatch.soc_min - 1e-9) && ...
       all(dr.soc <= cfg.dispatch.soc_max + 1e-9), 'SOC out of bounds');
assert(all(abs(dr.p_bess) <= sizing.P_bess + 1e-9), 'power limit violated');
assert(all(dr.unmet >= 0), 'negative unmet');

% constructed case: 10 kW spikes vs a 1 kW battery -> exact violation count
T = 200; k = 7;
L = 100*ones(T,1); L(10:10+k-1) = 110;
s2 = struct('P_bess', 1, 'C_bess', 1000);    % energy effectively unlimited
d2 = simulate_bess_dispatch(L, 100, 1/60, s2, cfg.dispatch);
assert(abs(d2.violation_rate - k/T) < 1e-12, 'violation counting wrong');
assert(abs(d2.peak_unmet_kW - 9) < 1e-9, 'peak unmet wrong');

% ---- 4. sweeps: nonempty, sane, file --------------------------------------
sw = run_sensitivity_sweeps(cfg);
assert(~isempty(sw.rows), 'empty sweep table');
assert(all(sw.rows(:,8) > 0), 'nonpositive N_opt in sweep');
assert(all(sw.rows(:,13) > 0), 'nonpositive total cost in sweep');
assert(exist(fullfile(cfg.out.dir,'sensitivity_results.csv'),'file') == 2);

% ---- 5. Monte Carlo: rates in range, file ----------------------------------
mc = monte_carlo_validation(cfg);
assert(all(mc.rows(:,6) >= 0 & mc.rows(:,6) <= 1), 'violation rate range');
assert(all(ismember(mc.rows(:,9), [-1 0 1])), 'verdict code');
assert(mc.rows(1,6) < 0.15, 'violation rate implausibly high');
assert(exist(fullfile(cfg.out.dir,'monte_carlo_validation.csv'),'file') == 2);

% ---- 6. plots + report ------------------------------------------------------
make_summer_plots(cfg, res, tr1, dr, sw, mc);
pngs = dir(fullfile(cfg.out.fig_dir, '*.png'));
assert(numel(pngs) == 8, 'expected 8 figures, found %d', numel(pngs));
write_summary_report(cfg, res, tr1, dr, sw, mc);
rep = fullfile(cfg.out.dir, 'summary_report.txt');
assert(exist(rep,'file') == 2);
fi = dir(rep); assert(fi.bytes > 500, 'report suspiciously small');

% ---- cleanup -----------------------------------------------------------------
try rmdir(cfg.out.dir, 's'); catch, end
close all;
fprintf('\nAll summer-extension tests passed.\n');
end
