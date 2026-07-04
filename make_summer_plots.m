function make_summer_plots(cfg, baseline_res, traces, disp_res, sweep, mc)
% MAKE_SUMMER_PLOTS  All figures for the summer extension, saved as PNG
% into outputs/figures/. Base MATLAB/Octave graphics only.

fdir = cfg.out.fig_dir;
p = cfg.baseline;
Ns = baseline_res.N;  b = baseline_res.best;

% 1 -- total cost vs N ------------------------------------------------------
f = new_fig();
plot(Ns, baseline_res.total/1e6, '-', 'LineWidth', 1.6); hold on;
capex = (baseline_res.cost_server + baseline_res.cost_bess + ...
         baseline_res.cost_sc + baseline_res.cost_feed)/1e6;
plot(Ns, capex, '--', 'LineWidth', 1.2);
plot(Ns, baseline_res.cost_grid/1e6, '--', 'LineWidth', 1.2);
kb = find(Ns == b.N, 1);
plot(b.N, baseline_res.total(kb)/1e6, 'r*', 'MarkerSize', 12, 'LineWidth', 1.5);
Nmin = min(Ns(baseline_res.feasible));
yl = ylim; plot([Nmin Nmin], yl, 'k:', 'LineWidth', 1.2);
xlabel('N servers'); ylabel('cost over horizon [$M]');
legend('total','capex','grid energy','optimum','min feasible N', ...
       'Location','northwest');
title(sprintf('Total cost vs N (demand %g kW, eps = %g)', ...
      p.demand_total, p.eps));
save_fig(f, fdir, 'cost_vs_N');

% 2 -- aggregate uncertainty vs N ------------------------------------------
f = new_fig();
plot(Ns, baseline_res.sigma_agg, '-', 'LineWidth', 1.6); hold on;
plot(Ns, Ns*p.sigma, '--', 'LineWidth', 1.2);
xlabel('N servers'); ylabel('aggregate load std [kW]');
legend('\sigma_{agg} (multiplexed)', 'N\sigma (perfectly correlated)', ...
       'Location','northwest');
title(sprintf('Statistical multiplexing (\\rho = %g)', p.rho));
save_fig(f, fdir, 'sigma_agg_vs_N');

% 3 -- BESS sizing vs rho ----------------------------------------------------
f = new_fig();
subplot(2,1,1);
plot(sweep.rho_grid, sweep.Pbess_vs_rho, '-o', 'LineWidth', 1.4);
ylabel('P_{bess} [kW]'); grid on;
title('BESS sizing vs inter-rack correlation');
subplot(2,1,2);
plot(sweep.rho_grid, sweep.Cbess_vs_rho, '-o', 'LineWidth', 1.4);
xlabel('\rho'); ylabel('C_{bess} [kWh]'); grid on;
save_fig(f, fdir, 'bess_sizing_vs_rho');

% 4 -- cost heatmap over rho x eps -------------------------------------------
f = new_fig();
imagesc(sweep.costM/1e6); colorbar;
set(gca, 'XTick', 1:numel(sweep.eps_grid), ...
         'XTickLabel', num_labels(sweep.eps_grid), ...
         'YTick', 1:numel(sweep.rho_grid), ...
         'YTickLabel', num_labels(sweep.rho_grid), 'YDir', 'normal');
xlabel('\epsilon (violation probability)'); ylabel('\rho (correlation)');
title('Total cost [$M] over \rho and \epsilon');
save_fig(f, fdir, 'cost_heatmap_rho_eps');

% 5 -- sample aggregate trace with grid reference ----------------------------
f = new_fig();
w = traces.t_h <= 24;                        % first day for readability
plot(traces.t_h(w), traces.agg_total(w), '-', 'Color', [0.6 0.6 0.85]); hold on;
plot(traces.t_h(w), traces.P_forecast(w), 'k-', 'LineWidth', 1.6);
plot(traces.t_h(w), traces.P_forecast(w) + b.P_bess, 'r--', 'LineWidth', 1.4);
xlabel('time [h]'); ylabel('power [kW]');
legend('aggregate load', 'grid reference P_{ref}(t)', ...
       'P_{ref} + P_{bess} (chance band)', 'Location', 'northwest');
title(sprintf('Load trace vs sized band (%s, %d racks)', ...
      strrep(traces.source, '_', '\_'), traces.N));
save_fig(f, fdir, 'load_trace_vs_reference');

% 6 -- BESS state of charge ----------------------------------------------------
f = new_fig();
plot(traces.t_h, disp_res.soc*100, '-', 'LineWidth', 1.2); hold on;
d = cfg.dispatch;
plot(traces.t_h([1 end]), [d.soc_min d.soc_min]*100, 'r:', 'LineWidth', 1.2);
plot(traces.t_h([1 end]), [d.soc_max d.soc_max]*100, 'r:', 'LineWidth', 1.2);
xlabel('time [h]'); ylabel('state of charge [%]'); ylim([0 100]);
title(sprintf('BESS SOC (%.0f kW / %.0f kWh, \\eta_{rt} = %.2f)', ...
      b.P_bess, b.C_bess, d.eta_rt));
save_fig(f, fdir, 'bess_soc_timeseries');

% 7 -- empirical violation vs target eps ---------------------------------------
f = new_fig();
loglog(mc.rows(:,2), mc.rows(:,6), 'o', 'MarkerSize', 8, 'LineWidth', 1.5); hold on;
lims = [min(mc.rows(:,2))/3, max(mc.rows(:,2))*3];
loglog(lims, lims, 'k--');
% hold-on (from new_fig) blocks loglog's implicit scale change -- force it
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('target \epsilon'); ylabel('empirical violation probability');
legend('Monte Carlo scenarios', 'perfect agreement', 'Location', 'northwest');
title('Chance constraint: empirical vs target');
save_fig(f, fdir, 'violation_vs_eps');

% 8 -- cost sensitivity to BESS price assumptions -------------------------------
f = new_fig();
plot(sweep.cP_grid/p.c_bess_P, sweep.cost_vs_cP/1e6, '-o', 'LineWidth', 1.4);
hold on;
plot(sweep.cE_grid/p.c_bess_E, sweep.cost_vs_cE/1e6, '-s', 'LineWidth', 1.4);
xlabel('price relative to baseline'); ylabel('total cost [$M]');
legend(sprintf('c_{bess,P} (base %g $/kW)', p.c_bess_P), ...
       sprintf('c_{bess,E} (base %g $/kWh)', p.c_bess_E), ...
       'Location', 'northwest');
title('Cost sensitivity to BESS price assumptions');
save_fig(f, fdir, 'cost_vs_bess_prices');

fprintf('Saved 8 figures to %s\n', fdir);
end

% ---- helpers -----------------------------------------------------------------
function f = new_fig()
f = figure('Visible', 'off', 'Position', [100 100 780 520], 'Color', 'w');
try set(f, 'Theme', 'light'); catch, end   % publication style even under
                                           % dark-theme MATLAB; no-op in Octave
set(gca, 'FontSize', 11); grid on; hold on;
end

function save_fig(f, fdir, name)
print(f, fullfile(fdir, [name '.png']), '-dpng', '-r150');
close(f);
end

function c = num_labels(v)
c = cellfun(@num2str, num2cell(v), 'UniformOutput', false);
end
