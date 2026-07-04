function seed_rng(s)
% SEED_RNG  Seed the random generator portably (MATLAB and old/new Octave).
try
    rng(s);                                  % MATLAB, Octave >= 7
catch
    rand('twister', s);  randn('state', s);  % older Octave fallback
end
end
