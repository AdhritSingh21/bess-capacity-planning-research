function traces = generate_load_traces(cfg, N_default)
% GENERATE_LOAD_TRACES  Time-series rack loads: real CSV if present,
% otherwise synthetic. Writes outputs/synthetic_load_traces.csv.
%
%   traces = generate_load_traces(cfg, N_default)
%
% cfg is config_summer(); N_default is the rack count to synthesize when
% cfg.trace.n_racks is empty (typically the baseline optimal N).
%
% Synthetic model per rack i (units kW, time step dt_h hours):
%   load_i(t) = max(0, mu_t + sigma*( sqrt(rho)*g(t) + sqrt(1-rho)*e_i(t) ))
%               + burst_i(t)
%   mu_t   : diurnal mean, mu*(1 + A*cos(2*pi*(hour - peak)/24))
%   g, e_i : AR(1) processes with unit marginal variance and correlation
%            time tau_corr_h -> equicorrelation rho across racks at every t
%            (the same one-factor structure the closed-form model assumes)
%   burst  : rare fast spikes of amplitude burst_amp, duration ~ tau_sc,
%            the component the per-rack supercaps are sized to absorb
%
% Returns struct:
%   .t_h        T x 1 time [h]           .dt_h      scalar step [h]
%   .rack_slow  T x N slow+diurnal load  .rack_burst T x N burst component
%   .agg_slow   T x 1 aggregate slow     .agg_burst  T x 1 aggregate burst
%   .agg_total  T x 1 slow + burst
%   .P_forecast T x 1 aggregate day-ahead reference (known diurnal mean,
%               or time-of-day binned average for real data)
%   .N, .source

t = cfg.trace;
p = cfg.baseline;

% ---- real data, if any ---------------------------------------------------
for k = 1:numel(t.real_candidates)
    f = t.real_candidates{k};
    if exist(f, 'file') == 2
        M = read_numeric_csv(f);
        traces.t_h  = M(:,1);
        rack        = M(:,2:end);
        traces.dt_h = median(diff(traces.t_h));
        traces.rack_slow  = rack;              % no burst decomposition known
        traces.rack_burst = zeros(size(rack));
        traces.agg_slow   = sum(rack, 2);
        traces.agg_burst  = zeros(size(traces.agg_slow));
        traces.agg_total  = traces.agg_slow;
        traces.P_forecast = tod_forecast(traces.t_h, traces.agg_total);
        traces.N      = size(rack, 2);
        traces.source = f;
        fprintf('Loaded real load trace %s: %d racks x %d steps (dt = %.1f s)\n', ...
                f, traces.N, numel(traces.t_h), traces.dt_h*3600);
        save_trace_csv(cfg, traces);
        return;
    end
end

% ---- synthetic -----------------------------------------------------------
N = t.n_racks;
if isempty(N), N = N_default; end
seed_rng(t.seed);

T    = round(t.days * 24 / t.dt_h);
t_h  = (0:T-1)' * t.dt_h;
hour = mod(t_h, 24);

% diurnal mean profile (per rack)
mu_t = p.mu * (1 + t.diurnal_amp * cos(2*pi*(hour - t.diurnal_peak)/24));

% AR(1) slow fluctuations, unit marginal variance:
%   x(t) = phi*x(t-1) + sqrt(1-phi^2)*w(t),  phi = exp(-dt/tau_corr)
phi = exp(-t.dt_h / t.tau_corr_h);
g   = ar1(T, 1, phi);          % common factor  (T x 1)
e   = ar1(T, N, phi);          % idiosyncratic  (T x N)
slow = repmat(mu_t, 1, N) + p.sigma * ...
       (sqrt(p.rho) * repmat(g, 1, N) + sqrt(1 - p.rho) * e);
slow = max(slow, 0);           % loads cannot be negative (slight tail bias)

% fast bursts: rare starts, short duration, fixed amplitude
p_start = t.bursts_per_rack_day * t.dt_h / 24;
burst = zeros(T, N);
[ti, ri] = find(rand(T, N) < p_start);
lmin = t.burst_len_steps(1); lmax = t.burst_len_steps(2);
for k = 1:numel(ti)
    len = lmin + floor(rand() * (lmax - lmin + 1));
    idx = ti(k) : min(ti(k) + len - 1, T);
    burst(idx, ri(k)) = p.burst_amp;
end

traces.t_h        = t_h;
traces.dt_h       = t.dt_h;
traces.rack_slow  = slow;
traces.rack_burst = burst;
traces.agg_slow   = sum(slow, 2);
traces.agg_burst  = sum(burst, 2);
traces.agg_total  = traces.agg_slow + traces.agg_burst;
traces.P_forecast = N * mu_t;    % day-ahead reference: known diurnal mean
traces.N          = N;
traces.source     = 'synthetic';
fprintf(['Generated synthetic traces: %d racks x %d steps ' ...
         '(%.1f days at dt = %.0f s, seed %d)\n'], ...
        N, T, t.days, t.dt_h*3600, t.seed);
save_trace_csv(cfg, traces);
end

% ---- helpers ---------------------------------------------------------------
function X = ar1(T, N, phi)
% AR(1) with unit marginal variance, stationary start.
X = zeros(T, N);
X(1,:) = randn(1, N);
w = randn(T, N) * sqrt(1 - phi^2);
for k = 2:T
    X(k,:) = phi * X(k-1,:) + w(k,:);
end
end

function f = tod_forecast(t_h, agg)
% Day-ahead reference for real data: mean load by time-of-day bin (1 h bins).
hour = mod(floor(t_h), 24);
f = zeros(size(agg));
for h = 0:23
    sel = (hour == h);
    if any(sel), f(sel) = mean(agg(sel)); end
end
end

function M = read_numeric_csv(path)
% One header row; numeric body.
if exist('readmatrix', 'file') == 2
    M = readmatrix(path);
else
    M = dlmread(path, ',', 1, 0);   % Octave fallback
end
end

function save_trace_csv(cfg, traces)
n_save = min(cfg.trace.n_racks_saved, traces.N);
rack_total = traces.rack_slow(:, 1:n_save) + traces.rack_burst(:, 1:n_save);
cols = {'time_h','agg_total_kW','agg_slow_kW','agg_burst_kW','P_forecast_kW'};
for i = 1:n_save
    cols{end+1} = sprintf('rack%d_kW', i); %#ok<AGROW>
end
M = [traces.t_h, traces.agg_total, traces.agg_slow, traces.agg_burst, ...
     traces.P_forecast, rack_total];
f = fullfile(cfg.out.dir, 'synthetic_load_traces.csv');
write_csv(f, cols, M);
fprintf('  wrote %s (aggregate + first %d racks)\n', f, n_save);
end
