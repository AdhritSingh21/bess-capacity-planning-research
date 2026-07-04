function mc = monte_carlo_validation(cfg)
% MONTE_CARLO_VALIDATION  Empirically test the chance constraint.
% For each (rho, eps) scenario: size the system with capacity_planning,
% then simulate per-rack equicorrelated Gaussian loads EXPLICITLY (no reuse
% of the aggregation formula, so the variance math is genuinely tested) and
% measure how often aggregate load exceeds P_ref + P_bess.
%
% Sampling is iid over time because the constraint bounds the MARGINAL
% per-instant probability; temporal correlation does not change it.
% Writes outputs/monte_carlo_validation.csv with verdict codes:
%   -1 conservative (empirical < target - 3 SE)
%    0 accurate     (within +/- 3 SE)
%   +1 optimistic   (empirical > target + 3 SE)

base = cfg.baseline;
base.verbose = false;  base.make_plot = false;
m = cfg.mc;
seed_rng(m.seed);

cols = {'rho','eps_target','N','P_ref_kW','P_bess_kW', ...
        'emp_violation','mc_stderr','n_samples','verdict_code'};
rows = [];

fprintf('Monte Carlo validation (%d trials x %d steps per scenario):\n', ...
        m.trials, m.steps);
for r = m.rho_scenarios
    for e = m.eps_scenarios
        p = base; p.rho = r; p.eps = e;
        res = capacity_planning(p);
        N   = res.best.N;
        cap = res.best.P_ref + res.best.P_bess;

        viol = 0; n = 0;
        for tr = 1:m.trials
            % per-rack one-factor model: X_i = mu + sigma*(sqrt(rho)*G
            %                                   + sqrt(1-rho)*E_i), clip at 0
            G = randn(m.steps, 1);
            X = p.mu + p.sigma * (sqrt(r) * repmat(G, 1, N) ...
                                  + sqrt(1 - r) * randn(m.steps, N));
            L = sum(max(X, 0), 2);
            viol = viol + sum(L > cap);
            n = n + m.steps;
        end
        emp = viol / n;
        se  = sqrt(e * (1 - e) / n);
        if emp < e - 3*se,     vc = -1;
        elseif emp > e + 3*se, vc = +1;
        else,                  vc = 0;
        end
        rows(end+1,:) = [r, e, N, res.best.P_ref, res.best.P_bess, ...
                         emp, se, n, vc]; %#ok<AGROW>
        fprintf('  rho=%.1f eps=%.3f: empirical %.5f (target %.3f, SE %.5f) -> %s\n', ...
                r, e, emp, e, se, verdict_str(vc));
    end
end

f = fullfile(cfg.out.dir, 'monte_carlo_validation.csv');
write_csv(f, cols, rows);
fprintf('  wrote %s\n', f);

mc.colnames = cols;
mc.rows = rows;
end

function s = verdict_str(vc)
if vc < 0,      s = 'conservative';
elseif vc > 0,  s = 'optimistic';
else,           s = 'accurate';
end
end
