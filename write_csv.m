function write_csv(path, colnames, M)
% WRITE_CSV  Numeric matrix -> CSV with one header row.
% Uses fprintf only, so it works in base MATLAB and Octave (no writetable,
% which Octave lacks).
%
%   write_csv('out.csv', {'a','b'}, [1 2; 3 4])

if numel(colnames) ~= size(M,2)
    error('write_csv:shape', 'need one column name per matrix column');
end
fid = fopen(path, 'w');
if fid < 0
    error('write_csv:io', 'cannot open %s for writing', path);
end
fprintf(fid, '%s\n', strjoin(colnames, ','));
fmt = [repmat('%.10g,', 1, size(M,2)-1) '%.10g\n'];
fprintf(fid, fmt, M.');    % fprintf consumes column-wise -> transpose
fclose(fid);
end
