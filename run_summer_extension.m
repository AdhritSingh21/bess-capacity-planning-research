% RUN_SUMMER_EXTENSION  Master workflow for the summer project.
% Runs, in order:
%   1. baseline closed-form capacity planning (unchanged original model)
%   2. load-trace generation (or loading of real data if a CSV is present)
%   3. time-indexed BESS dispatch validation on the trace
%   4. sensitivity sweeps (rho, eps, BESS prices, demand, N)
%   5. Monte Carlo validation of the chance constraint
%   6. figures -> outputs/figures/
%   7. text summary -> outputs/summary_report.txt
%
% All parameters live in config_summer.m. Base MATLAB/Octave only.

clear; clc; close all;

cfg = config_summer();
if ~exist(cfg.out.dir, 'dir'),     mkdir(cfg.out.dir);     end
if ~exist(cfg.out.fig_dir, 'dir'), mkdir(cfg.out.fig_dir); end

fprintf('==================================================================\n');
fprintf(' BESS / data-center capacity planning -- summer extension\n');
fprintf('==================================================================\n');

% ---- 1. baseline -----------------------------------------------------------
fprintf('\n[1/6] Baseline closed-form capacity planning\n');
pb = cfg.baseline;  pb.verbose = true;
baseline_res = capacity_planning(pb);
N_opt = baseline_res.best.N;

% ---- 2. traces --------------------------------------------------------------
fprintf('\n[2/6] Load traces\n');
traces = generate_load_traces(cfg, N_opt);

% ---- 3. dispatch validation ---------------------------------------------------
fprintf('\n[3/6] Time-indexed BESS dispatch validation\n');
sizing = struct('P_bess', baseline_res.best.P_bess, ...
                'C_bess', baseline_res.best.C_bess);
% slow layer serves the burst-free aggregate (supercaps absorb bursts locally)
disp_res = simulate_bess_dispatch(traces.agg_slow, traces.P_forecast, ...
                                  traces.dt_h, sizing, cfg.dispatch);
exceed_total = mean(traces.agg_total > traces.P_forecast + sizing.P_bess);
exceed_flat  = mean(traces.agg_slow  > mean(traces.agg_slow) + sizing.P_bess);
fprintf('  band exceedance (slow load)   : %.4f  (theory bound eps = %g)\n', ...
        disp_res.band_exceed_rate, cfg.baseline.eps);
fprintf('  unmet after SOC/efficiency    : %.4f of steps, peak %.1f kW\n', ...
        disp_res.violation_rate, disp_res.peak_unmet_kW);
if disp_res.violation_rate > 2 * disp_res.band_exceed_rate
    fprintf(['  NOTE: unmet rate >> band rate -> the C_bess = P_bess*tau_bess\n' ...
             '  energy window is binding (see summary_report.txt, section 3)\n']);
end
fprintf('  with bursts left in (no SC)   : %.4f  <- why the fast layer exists\n', ...
        exceed_total);
fprintf('  vs FLAT reference (no diurnal): %.4f  <- why P_ref tracks the forecast\n', ...
        exceed_flat);
f = fullfile(cfg.out.dir, 'dispatch_timeseries.csv');
write_csv(f, {'time_h','load_slow_kW','load_total_kW','P_forecast_kW', ...
              'p_bess_kW','soc','unmet_kW'}, ...
          [traces.t_h, traces.agg_slow, traces.agg_total, traces.P_forecast, ...
           disp_res.p_bess, disp_res.soc, disp_res.unmet]);
fprintf('  wrote %s\n', f);

% ---- 4. sensitivity sweeps ------------------------------------------------------
fprintf('\n[4/6] Sensitivity sweeps\n');
sweep = run_sensitivity_sweeps(cfg);

% ---- 5. Monte Carlo --------------------------------------------------------------
fprintf('\n[5/6] Monte Carlo validation\n');
mc = monte_carlo_validation(cfg);

% ---- 6. figures + report -----------------------------------------------------------
fprintf('\n[6/6] Figures and summary report\n');
make_summer_plots(cfg, baseline_res, traces, disp_res, sweep, mc);
write_summary_report(cfg, baseline_res, traces, disp_res, sweep, mc);

fprintf('\nDone. Outputs:\n');
fprintf('  %s\n', fullfile(cfg.out.dir, 'synthetic_load_traces.csv'));
fprintf('  %s\n', fullfile(cfg.out.dir, 'dispatch_timeseries.csv'));
fprintf('  %s\n', fullfile(cfg.out.dir, 'sensitivity_results.csv'));
fprintf('  %s\n', fullfile(cfg.out.dir, 'monte_carlo_validation.csv'));
fprintf('  %s\n', fullfile(cfg.out.dir, 'summary_report.txt'));
fprintf('  %s%s*.png (8 figures)\n', cfg.out.fig_dir, filesep);
