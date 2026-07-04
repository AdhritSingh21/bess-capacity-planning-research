function sweep = run_sensitivity_sweeps(cfg)
% RUN_SENSITIVITY_SWEEPS  One-at-a-time sweeps around the baseline plus a
% rho x eps grid. Writes outputs/sensitivity_results.csv.
%
% CSV columns (numeric; sweep_id decodes as):
%   1 rho | 2 eps | 3 c_bess_P | 4 c_bess_E | 5 demand_total
%   6 fixed N (demand pinned to N*mu) | 7 rho-x-eps grid (for the heatmap)
% Each row: the swept value(s), the resulting optimal design and costs, and
% the tracking metric resid_kW = E[(load - P_ref - P_bess)^+].

base = cfg.baseline;
base.verbose = false;  base.make_plot = false;
s = cfg.sweep;

cols = {'sweep_id','param_value','rho','eps','c_bess_P','c_bess_E', ...
        'demand_total','N_opt','P_ref_kW','P_bess_kW','C_bess_kWh', ...
        'C_sc_total_kWh','cost_total','cost_track','resid_kW'};
rows = [];

for v = s.rho_grid
    p = base; p.rho = v;
    rows(end+1,:) = eval_case(p, 1, v); %#ok<AGROW>
end
for v = s.eps_grid
    p = base; p.eps = v;
    rows(end+1,:) = eval_case(p, 2, v); %#ok<AGROW>
end
for v = s.c_bess_P_grid
    p = base; p.c_bess_P = v;
    rows(end+1,:) = eval_case(p, 3, v); %#ok<AGROW>
end
for v = s.c_bess_E_grid
    p = base; p.c_bess_E = v;
    rows(end+1,:) = eval_case(p, 4, v); %#ok<AGROW>
end
for v = s.demand_grid
    p = base; p.demand_total = v;
    % make sure the search range can serve the largest demand values
    p.N_range = 1:(ceil(v / p.mu) + 50);
    rows(end+1,:) = eval_case(p, 5, v); %#ok<AGROW>
end
for v = s.N_grid
    p = base; p.N_range = v; p.demand_total = v * p.mu;  % pin design to N=v
    rows(end+1,:) = eval_case(p, 6, v); %#ok<AGROW>
end

% rho x eps grid (heatmap source)
nr = numel(s.rho_grid); ne = numel(s.eps_grid);
costM = zeros(nr, ne);
for i = 1:nr
    for j = 1:ne
        p = base; p.rho = s.rho_grid(i); p.eps = s.eps_grid(j);
        row = eval_case(p, 7, 0);
        costM(i,j) = row(13);            % cost_total column
        rows(end+1,:) = row; %#ok<AGROW>
    end
end

f = fullfile(cfg.out.dir, 'sensitivity_results.csv');
write_csv(f, cols, rows);
fprintf('Sensitivity sweeps: %d scenarios -> %s\n', size(rows,1), f);

sweep.colnames = cols;
sweep.rows     = rows;
sweep.rho_grid = s.rho_grid;   sweep.eps_grid = s.eps_grid;
sweep.costM    = costM;        % nr x ne total cost for the heatmap
% convenience slices for plotting
sel = rows(:,1) == 1;
sweep.Pbess_vs_rho = rows(sel, 10);  sweep.Cbess_vs_rho = rows(sel, 11);
sel = rows(:,1) == 3;
sweep.cost_vs_cP = rows(sel, 13);    sweep.cP_grid = s.c_bess_P_grid;
sel = rows(:,1) == 4;
sweep.cost_vs_cE = rows(sel, 13);    sweep.cE_grid = s.c_bess_E_grid;
end

function row = eval_case(p, id, val)
res  = capacity_planning(p);
b    = res.best;
% tracking metric independent of lambda_track: Gaussian partial moment
phi_z    = exp(-res.z^2/2) / sqrt(2*pi);
resid_kW = b.sigma_agg * (phi_z - res.z * p.eps);
row = [id, val, p.rho, p.eps, p.c_bess_P, p.c_bess_E, p.demand_total, ...
       b.N, b.P_ref, b.P_bess, b.C_bess, b.C_sc_total, b.total, b.track, ...
       resid_kW];
end
