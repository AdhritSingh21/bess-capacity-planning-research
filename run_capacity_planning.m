% run_capacity_planning.m -- driver for capacity_planning.m
%
% Sizes a grid-responsive data center (grid feed + BESS + per-rack
% supercaps) for a FIXED compute demand target, using the closed-form
% chance-constraint model in capacity_planning.m.
%
% Units everywhere: power [kW], energy [kWh], time [h], money [$].
% Edit the params to your load statistics and cost figures, then run.

clear; clc; close all;

params = struct();

% --- per-rack load statistics (fit these from your load traces) ----------
params.mu        = 5;      % mean compute load per rack             [kW]
params.sigma     = 2;      % std of slow load fluctuation per rack  [kW]
params.rho       = 0.2;    % inter-rack correlation (0..1)          [-]
params.burst_amp = 6;      % fast (GPU) burst amplitude per rack    [kW]
params.tau_sc    = 1/120;  % supercap ride-through window           [h]  (~30 s)
params.tau_bess  = 0.25;   % BESS balancing window                  [h]  (15 min)

% --- reliability ----------------------------------------------------------
params.eps       = 0.01;   % chance-constraint violation prob (serve w.p. 1-eps)

% --- costs ----------------------------------------------------------------
params.c_server   = 8000;    % $/server (rack)
params.c_bess_E   = 200;     % $/kWh BESS energy capacity
params.c_bess_P   = 300;     % $/kW  BESS power rating
params.c_sc       = 8000;    % $/kWh supercap (power-dense, energy-expensive)
params.c_grid_P   = 150;     % $/kW  grid connection / feed sizing
params.price_grid = 0.10;    % $/kWh grid energy
params.horizon_h  = 10*8760; % amortization horizon [h] (10 years)
params.lambda_track = 2;     % $/kWh on expected energy beyond the BESS band
                             % (VoLL-style penalty for residual mismatch)

% --- design requirement ----------------------------------------------------
% Fixed compute demand the site must support. Without this every cost term
% grows with N and the "optimum" trivially collapses to the smallest N.
params.demand_total = 500;   % [kW]  -> needs at least ceil(500/5) = 100 racks

% --- search -----------------------------------------------------------------
params.N_range = 1:300;      % candidate server counts (integer enumeration)

results = capacity_planning(params);
