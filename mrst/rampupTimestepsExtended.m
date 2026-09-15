function dt = rampupTimestepsExtended(totTime, dt_target, n_init, nRampSteps, dt_init_factor)
% Generate timestep schedule with initial small steps, ramp-up, and constant target steps
%
% SYNOPSIS:
%   dt = rampupTimestepsExtended(totTime, dt_target, n_init, nRampSteps)
%   dt = rampupTimestepsExtended(totTime, dt_target, n_init, nRampSteps, dt_init_factor)
%
% PARAMETERS:
%   totTime        - Total simulation time (e.g., 100*year)
%   dt_target      - Target timestep size for main simulation (e.g., 30*day)
%   n_init         - Number of initial small timesteps
%   nRampSteps     - Number of timesteps in the ramp-up phase
%   dt_init_factor - (Optional) Factor for initial timestep size relative to dt_target
%                    Default: 0.01 (i.e., dt_init = 0.01 * dt_target)
%
% RETURNS:
%   dt - Column vector of timestep sizes [n x 1]
%
% DESCRIPTION:
%   Creates a timestep schedule with three phases:
%   1. Initial phase: n_init small timesteps of size (dt_init_factor * dt_target)
%   2. Ramp phase: nRampSteps timesteps ramping from initial to target size
%   3. Main phase: Constant timesteps of size dt_target until totTime is reached
%
% EXAMPLE:
%   % 10 initial small steps, 20 ramp steps, then 30-day target steps
%   dt = rampupTimestepsExtended(10*year, 30*day, 10, 20);
%
%   % Custom initial timestep factor (5% of target instead of 1%)
%   dt = rampupTimestepsExtended(10*year, 30*day, 10, 20, 0.05);
%
% SEE ALSO:
%   rampupTimesteps, simpleSchedule

% Handle optional argument
if nargin < 5
    dt_init_factor = 0.01;  % Default: initial dt is 1% of target
end

% Validate inputs
assert(totTime > 0, 'Total time must be positive');
assert(dt_target > 0, 'Target timestep must be positive');
assert(n_init >= 0, 'Number of initial steps must be non-negative');
assert(nRampSteps >= 0, 'Number of ramp steps must be non-negative');
assert(dt_init_factor > 0 && dt_init_factor < 1, ...
     'Initial timestep factor must be between 0 and 1');

% Calculate initial timestep size
dt_init = dt_init_factor * dt_target;

% Initialize timestep array
dt = [];

% Phase 1: Initial small timesteps
if n_init > 0
    dt_initial = repmat(dt_init, n_init, 1);
    dt = [dt; dt_initial];
end

% Phase 2: Ramp-up timesteps
if nRampSteps > 0
    % Geometric progression from dt_init to dt_target
    ramp_ratio = (dt_target / dt_init)^(1 / nRampSteps);
    dt_ramp = dt_init * ramp_ratio.^(1:nRampSteps)';
    dt = [dt; dt_ramp];
end

% Calculate remaining time
time_used = sum(dt);
time_remaining = totTime - time_used;

% Phase 3: Constant target timesteps
if time_remaining > 0
    n_target = ceil(time_remaining / dt_target);
    dt_target_steps = repmat(dt_target, n_target, 1);
    
    % Adjust last timestep to exactly match totTime
    dt_target_steps(end) = time_remaining - sum(dt_target_steps(1:end-1));
    
    dt = [dt; dt_target_steps];
else
    warning('Initial and ramp phases exceed total time. Adjusting...');
    % Scale all timesteps proportionally to fit totTime
    dt = dt * (totTime / time_used);
end

% Ensure column vector
dt = dt(:);

% Verify total time (within numerical tolerance)
actual_totTime = sum(dt);
rel_error = abs(actual_totTime - totTime) / totTime;
if rel_error > 1e-10
    warning('Total timestep sum (%.6e) differs from target (%.6e) by %.2e%%', ...
          actual_totTime, totTime, rel_error * 100);
end
end