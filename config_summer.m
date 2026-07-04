function cfg = config_summer()
% CONFIG_SUMMER  Every parameter of the summer extension in one struct.
% Edit here; all other scripts read from this function.
% Units: power [kW], energy [kWh], time [h], money [$].

% ---- baseline closed-form model (matches run_capacity_planning.m) -------
b = struct();
b.mu        = 5;       % mean compute load per rack             [kW]
b.sigma     = 2;       % std of slow load fluctuation per rack  [kW]
b.rho       = 0.2;     % inter-rack correlation                 [-]
b.burst_amp = 6;       % fast (GPU) burst amplitude per rack    [kW]
b.tau_sc    = 1/120;   % supercap ride-through window           [h] (~30 s)
b.tau_bess  = 0.25;    % BESS balancing window                  [h] (15 min)
b.eps       = 0.01;    % chance-constraint violation probability
b.c_server  = 8000;    % $/server
b.c_bess_E  = 200;     % $/kWh BESS energy
b.c_bess_P  = 300;     % $/kW  BESS power
b.c_sc      = 8000;    % $/kWh supercap
b.c_grid_P  = 150;     % $/kW  grid connection
b.price_grid   = 0.10; % $/kWh grid energy
b.horizon_h    = 10*8760;
b.lambda_track = 2;    % $/kWh on expected energy beyond the BESS band
b.demand_total = 500;  % [kW] fixed compute demand target
b.N_range   = 1:300;
b.make_plot = false;   % extension makes its own figures
b.verbose   = false;   % extension prints its own summaries
cfg.baseline = b;

% ---- synthetic load traces -----------------------------------------------
t = struct();
t.n_racks       = [];      % [] -> use the baseline optimal N
t.days          = 2;       % trace length [days]
t.dt_h          = 30/3600; % time step [h]  (30 s)
t.diurnal_amp   = 0.15;    % relative diurnal swing of mean load (+/-15%)
t.diurnal_peak  = 15;      % hour-of-day of peak mean load
t.tau_corr_h    = 10/60;   % AR(1) correlation time of slow fluctuations [h]
t.bursts_per_rack_day = 4; % expected fast bursts per rack per day
t.burst_len_steps = [1 4]; % burst duration, uniform in this range [steps]
t.seed          = 42;      % RNG seed for reproducibility
t.n_racks_saved = 5;       % how many per-rack columns to keep in the CSV
% real data is loaded instead of synthesized if one of these exists
% (format: one header row; col 1 = time [h]; cols 2..end = per-rack load [kW])
t.real_candidates = {'real_load_data.csv','load_trace.csv', ...
                     fullfile('data','load_trace.csv')};
cfg.trace = t;

% ---- time-indexed BESS dispatch validation --------------------------------
d = struct();
d.eta_rt   = 0.92;    % round-trip efficiency (split sqrt/sqrt charge/discharge)
d.soc0     = 0.50;    % initial state of charge [fraction of C_bess]
d.soc_min  = 0.10;    % usable SOC window (depth-of-discharge limits)
d.soc_max  = 0.90;
d.unmet_tol_kW = 1e-6; % unmet power above this counts as a violated step
cfg.dispatch = d;

% ---- sensitivity sweeps (one-at-a-time around baseline + rho x eps grid) --
s = struct();
s.rho_grid      = 0:0.1:0.8;
s.eps_grid      = [0.001 0.002 0.005 0.01 0.02 0.05 0.1];
s.c_bess_P_grid = [100 200 300 450 600 800 1000];   % $/kW
s.c_bess_E_grid = [80 140 200 300 400 600 800];     % $/kWh
s.demand_grid   = [200 350 500 750 1000 1500 2000]; % kW
s.N_grid        = [50 75 100 150 200 250];          % fixed rack counts
cfg.sweep = s;

% ---- Monte Carlo validation of the chance constraint ----------------------
m = struct();
m.rho_scenarios = [0 0.2 0.5];
m.eps_scenarios = [0.001 0.01 0.05];
m.trials        = 25;     % independent trials per scenario
m.steps         = 20000;  % iid time samples per trial (marginal constraint)
m.seed          = 7;
cfg.mc = m;

% ---- output locations ------------------------------------------------------
cfg.out.dir     = 'outputs';
cfg.out.fig_dir = fullfile('outputs','figures');
end
