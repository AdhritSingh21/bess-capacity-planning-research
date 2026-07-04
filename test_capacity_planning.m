function test_capacity_planning
% TEST_CAPACITY_PLANNING  Sanity checks for capacity_planning.m.
% Needs only base MATLAB/Octave (no toolboxes). Run:  test_capacity_planning

base = struct('mu',5,'sigma',2,'rho',0.2,'burst_amp',6, ...
              'tau_sc',1/120,'tau_bess',0.25,'eps',0.01, ...
              'demand_total',500,'N_range',1:300,'make_plot',false);

% 1) Gaussian quantile: erfcinv form matches known value (and norminv if present)
r = capacity_planning(base);
assert(abs(r.z - 2.326347874) < 1e-6, 'z_{0.99} should be ~2.3263');
if exist('norminv','file')
    assert(abs(r.z - norminv(1 - 0.01)) < 1e-12, 'z must match norminv');
end

% 2) aggregate std: rho=0 -> sqrt(N)*sigma, rho=1 -> N*sigma
p = base; p.rho = 0;
r0 = capacity_planning(p);
k = find(r0.N == 100);
assert(abs(r0.sigma_agg(k) - sqrt(100)*p.sigma) < 1e-9, 'rho=0 multiplexing');
p.rho = 1;
r1 = capacity_planning(p);
assert(abs(r1.sigma_agg(k) - 100*p.sigma) < 1e-9, 'rho=1 no multiplexing');

% 3) with a demand floor and monotone costs, optimum = smallest feasible N
assert(r.best.N == ceil(base.demand_total/base.mu), ...
    'optimum should be the minimum feasible N');

% 4) chance-constraint sizing is binding: P_bess = z*sigma_agg, C = P*tau
assert(abs(r.best.P_bess - r.z*r.best.sigma_agg) < 1e-9);
assert(abs(r.best.C_bess - r.best.P_bess*0.25) < 1e-9);

% 5) infeasible demand raises a clear error (not a silent fallback)
p = base; p.demand_total = 1e6;
ok = false;
try
    capacity_planning(p);
catch err
    ok = strcmp(err.identifier, 'capacity_planning:infeasible');
end
assert(ok, 'infeasible demand must raise capacity_planning:infeasible');

% 6) empty demand target warns about the trivial optimum
p = base; p.demand_total = [];
lastwarn('');
r2 = capacity_planning(p);
[~, wid] = lastwarn();
assert(strcmp(wid, 'capacity_planning:noDemandTarget'), 'must warn when demand empty');
assert(r2.best.N == min(p.N_range), 'trivial optimum is min N');

% 7) parameter validation rejects bad inputs
bad = {struct('eps',0), struct('eps',0.7), struct('rho',-0.1), ...
       struct('mu',-5), struct('N_range',[0 1]), struct('demand_total',-10)};
for i = 1:numel(bad)
    p = base;
    f = fieldnames(bad{i});
    p.(f{1}) = bad{i}.(f{1});
    ok = false;
    try
        capacity_planning(p);
    catch err
        ok = strcmp(err.identifier, 'capacity_planning:badParam');
    end
    assert(ok, 'bad %s must raise capacity_planning:badParam', f{1});
end

close all;
fprintf('\nAll capacity_planning tests passed.\n');
end
