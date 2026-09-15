%% Modeling of CO2 injection in Stenlille using a thermal MSW

mrstModule add ad-core ad-props co2lab-common ad-blackoil

clear all

%% Set up a 7x7x10 Cartesian grid of a box reservoir with 100x100x20 m at a given depth
[nx, ny, nz] = deal(7, 7, 10);
[Dx, Dy, Dz] = deal(100, 100, 20);

% Top Gassum Fm sandstone 
top_gassum_depth = 1564;

% Shift nodes to match the Gassum depth
G = cartGrid([nx, ny, nz], [Dx*meter, Dy*meter, Dz*meter]);
G.nodes.coords(:, 3) = G.nodes.coords(:, 3) + top_gassum_depth;

% Shift nodes to match the perforation interval of 1570.5-1579 m
nn = (G.nodes.coords(:, 3)==1570);
G.nodes.coords(nn, 3) = 1570.5;

nn = (G.nodes.coords(:, 3)==1580);
G.nodes.coords(nn, 3) = 1579;

G = computeGeometry(G);
%plotGrid(G)

fprintf('Created %d x %d x %d grid\n', nx, ny, nz);
fprintf('Total cells: %d\n', G.cells.num);

%% Set up rock properties
% Base rock properties
perm_base = 100*milli*darcy;
poro_base = 0.2;

% Initialize with base properties
rock.perm = perm_base * ones(G.cells.num, 1);
rock.poro = poro_base * ones(G.cells.num, 1);

% Rock compressibility
cf_rock = 4.35e-5 / barsa;

% Add thermal properties to the rock 
rock = addMyThermalRockProps(rock           , ...   % Original rock
                           'CpR'    , 913.3, ...    % Specific heat capacity
                           'lambdaR', 1.81035, ...  % Thermal conductivity
                           'rhoR'   , 2274.62, ...  % Rock density
                           'tau'    , 1   );        % Tortuosity

%% Set up fluid properties

gravity on
g = norm(gravity);

% Brine properties
rhow = 1000;            % Water density kg/m^3
muw = 1*centi*poise;    % Brine viscosity
cf_wat = 1e-5/barsa;    % Brine compressibility 

% Define reference pressure at the top reservoir 
p_ref = 168 * barsa;

% Define temperature as following the geothermal gradient
tsurf = 5 + 273.15;     % Surface temperature 
tgrad = (52 -5)/1.580;  % Geothermal gradient (degC/km)
t_ref = tsurf + top_gassum_depth * tgrad / 1000;

% Load sampled tables of CO2 properties
co2 = CO2props();

% Calculate CO2 density and viscosity at reference conditions
rho_co2 = co2.rho(p_ref, t_ref);  % CO2 density at ref. press/temp
muco2 = co2.mu(p_ref, t_ref) * Pascal * second;  % CO2 viscosity

% Residual saturations
srw = 0.27;  % Residual water saturation
src = 0.20;  % Residual CO2 saturation

% Capillary pressure parameters
pe = 5 * kilo * Pascal;

% Define water and gas (CO2) with constant viscosities, a constant
% compressibility model for inverse formation volume factors b=exp((p-pRef)*c),
% and linear relative permeabilities
fwc = initSimpleADIFluid('phases', 'WG', ...
    'mu'  , [muw muco2]     , ...
    'rho' , [rhow, rho_co2]     , ...
    'pRef', p_ref           , ...
    'c'   , [cf_wat cf_wat],...
    'cR'  , cf_rock          , ...
    'n'   , [1 1]);

% Define ranges
p_min = 1 * barsa;
p_max = 250 * barsa;
T_min = 4 + 273.15;
T_max = 150 + 273.15;

% Add CO2 density (rhoG), viscosity (muG) AND enthalpy (hG) as functions of
% (P, T) using sampled tables. Sampling the enthalpy also provides the
% internal energy uG = hG - p/rhoG. With real h(p,T) the energy equation
% captures the Joule-Thomson effect (cooling of CO2 on expansion), which a
% constant-Cp model cannot represent.
% NOTE: the first run generates the new enthalpy table (lengthy).
fluid = addSampledFluidProperties(fwc, 'G', ...
    'props', [true, true, true, false], ...  % [rho, mu, enthalpy, conductivity]
    'pspan', [p_min, p_max], ...
    'tspan', [T_min, T_max], ...
    'reservoirT', []);  % Empty = f(P,T)

% Add water density (rhoW) and re-define viscosity (muW) as a function of (P, T) using sampled tables
fluid = addSampledFluidProperties(fluid, 'W', ...
    'props', [true, true, false, false], ...  % [rho, mu, enthalpy, conductivity]
    'pspan', [p_min, p_max], ...
    'tspan', [T_min, T_max], ...
    'reservoirT', []);  % Empty = f(P,T)

% Re-define the inverse formation volume factors using sampled density functions
fluid.bW = @(p, t) fluid.rhoW(p, t) / rhow;
fluid.bG = @(p, t) fluid.rhoG(p, t) / rho_co2;

% Modify relperm curves with residual saturations
krW0 = fluid.krW;
krG0 = fluid.krG;
fluid.krW = @(s) krW0(max((s - srw)./(1 - srw), 0));
fluid.krG = @(s) krG0(max((s - src)./(1 - src), 0));

% Add capillary pressure curve 
fluid.pcWG = @(sg) pe * max((1 - sg - srw)./(1 - srw), 1e-5).^(-1/2);

% Add thermal properties to the fluid
% Cp must be an array: [CpW, CpG] for water-gas system
fluid = addMyThermalFluidProps(fluid               , ... % Original fluid
                             'Cp'     , [4.2e3, 1e3], ... % Specific heat capacity [Water, CO2] J/(kg·K)
                             'lambdaF', 0.6         , ... % Thermal conductivity
                             'useEOS' , true        );    % Use equation of state


%% Set up the reservoir model

model = TwoPhaseWaterGasThermalModel(G, rock, fluid, tsurf, tgrad);

% Initialize state function groupings by validating model
model = model.validateModel();

% Replace standard state functions with P-T versions for convergence checking
pvt = model.PVTPropertyFunctions;
pvt = pvt.setStateFunction('ShrinkageFactors', ShrinkageFactorsPT(model));
pvt = pvt.setStateFunction('Viscosity', ViscosityPT(model));
model.PVTPropertyFunctions = pvt;


%% Set up initial state with hydrostatic pressure, fully water-saturated

% Top reservoir pressure is 168 bar, hydrostatic gradient
% within the reservoir
state0.pressure = p_ref + rhow * g * (G.cells.centroids(:,3) - top_gassum_depth);

state0.s = repmat([1, 0], G.cells.num, 1);

% Initialize temperature field using geothermal gradient
state0.T = tsurf + G.cells.centroids(:,3) * tgrad / 1000;


%% Set up injection well in one corner (to be converted to MSW below)

I = 1;
J = 1;

% Perforated layers at depths of 1570.5-1579 m
K = 4:8;

% Calculate cell indices for well perforations
c_inj = arrayfun(@(k) sub2ind(G.cartDims, I, J, k), K)';

% Mass rate 10 tonnes/hour
mass_rate = 10 * 1e3 / 3600;

% Surface injection volumetric rate (surface density = rho_co2 since
% fluid.bG is normalized by rho_co2 above)
vol_rate = mass_rate / rho_co2;

% Add gas injector (Comp_i = [0, 1] for water-gas)
W_inj = addWell([], G, rock, c_inj, ...
            'Name', 'ST-06', ...
            'Type', 'rate', ...
            'Val', vol_rate, ...
            'Comp_i', [0, 1], ...
            'refDepth', G.cells.centroids(c_inj(1), 3));

%% Convert the injector to a multisegment well with riser and completion
% Well structure:
%   Surface (0 m)                          - Node 1
%         |
%   ... n_riser_segs riser segments (no reservoir connection) ...
%         |
%   Top of reservoir (top_gassum_depth)    - Node n_riser_segs+1
%         |
%   Completion segment 1 - Node n_riser_segs+2 -> Cell c_inj(1)
%         |
%   ...
%         |
%   Completion segment nperf - last node   -> Cell c_inj(nperf)

% Riser section parameters
n_riser_segs = 100;
riser_top_depth = 0;                    % Surface
riser_bottom_depth = top_gassum_depth;  % Top of reservoir
riser_seg_length = (riser_bottom_depth - riser_top_depth) / n_riser_segs;

% Completion section parameters
nperf = length(c_inj);
layer_depths = G.cells.centroids(c_inj, 3);  % Depths of perforated cells
assert(nperf > 1, 'Should have >1 perforated cells for MSW!')

% Completion segment lengths: first segment spans from the top-reservoir
% node to the first perforated cell, the rest follow the cell spacing
comp_seg_lengths = [layer_depths(1) - riser_bottom_depth; diff(layer_depths)];

% Total segments and nodes
n_total_segs = n_riser_segs + nperf;
n_total_nodes = n_total_segs + 1;  % One node at top

% Top of reservoir node
top_res_node = n_riser_segs + 1;

% Topology: sequential nodes from top (surface) to bottom
topo = [(1:n_total_segs)', (2:n_total_nodes)'];

% Cell-to-node mapping: only the last nperf nodes connect to reservoir
cell2node = sparse((n_riser_segs+2:n_total_nodes)', (1:nperf)', 1, n_total_nodes, nperf);

% Segment lengths: riser segments + completion segments
seg_lengths = [repmat(riser_seg_length, n_riser_segs, 1); comp_seg_lengths];

% Segment diameters: uniform for all segments
well_diam = 2.441 * 0.0254;  % 2.441 inch = 0.062 m (see Table 3-1)
diam = well_diam * ones(n_total_segs, 1);

% Node depths: from surface to bottom of completion
riser_node_depths = linspace(riser_top_depth, riser_bottom_depth, n_riser_segs+1)';
comp_node_depths = layer_depths;
depths = [riser_node_depths; comp_node_depths];

% Node volumes from tubing geometry
tube_area = pi * well_diam^2 / 4;
node_seg_len = 0.5 * [seg_lengths(1); ...
                      seg_lengths(1:end-1) + seg_lengths(2:end); ...
                      seg_lengths(end)];
vols = tube_area * node_seg_len;

fprintf('Total wellbore volume: %.2f m^3\n', sum(vols));

% Convert to MS-well
MSW = convert2MSWell(W_inj, 'cell2node', cell2node, 'topo', topo, 'G', G, ...
                   'vol', vols, 'nodeDepth', depths, ...
                   'segLength', seg_lengths, 'segDiam', diam);

% Set up flow model with wellbore friction for ALL segments
wbix = 1:n_total_segs;  % Apply friction to all segments
roughness = 0.05*milli*meter;  % Pipe roughness is 0.05 mm (Page 8)

MSW.segments.flowModel = @(v, rho, mu) ...
  wellboreFlow(v(wbix), rho(wbix), mu(wbix), MSW.segments.diam(wbix), ...
                   MSW.segments.length(wbix), roughness, 'massRate');

% MSW initially filled with water (see options in
% TwoPhaseThermalMultisegmentWell/validateWellSol)
MSW.init = 'water';

% Heat exchange with the formation through tubing/annulus/casing/cement,
% used by setupMSWellEquationsEnthalpy. Geometry and conductivities from
% the steady-state model (stenlille_pipeline_mix.m); the tubing inner
% diameter matches well_diam (2.441 inch).
MSW.heat = struct( ...
    'd_ti' , well_diam      , ...  % Tubing inner diameter [m]
    'd_to' , 3.65*2/100     , ...  % Tubing outer diameter [m]
    'd_ci' , 6.21*2/100     , ...  % Casing inner diameter [m]
    'd_co' , 6.98*2/100     , ...  % Casing outer diameter [m]
    'd_wb' , 10.8*2/100     , ...  % Wellbore (open hole) diameter [m]
    'k_t'  , 15             , ...  % Tubing thermal conductivity [W/(m K)]
    'k_a'  , 0.662871377    , ...  % Annulus fluid thermal conductivity [W/(m K)]
    'k_c'  , 15             , ...  % Casing thermal conductivity [W/(m K)]
    'k_cem', 6.959284       , ...  % Cement thermal conductivity [W/(m K)]
    'k_e'  , 2.423          , ...  % Formation thermal conductivity [W/(m K)]
    'rho_e', 2375           , ...  % Formation density [kg/m^3]
    'cp_e' , 939.09924      , ...  % Formation specific heat capacity [J/(kg K)]
    'Tsurf', tsurf          , ...  % Formation surface temperature [K]
    'tgrad', tgrad          );     % Geothermal gradient [K/km]

fprintf('\nMSW Setup:\n');
fprintf('  Riser segments: %d (%.1f m each)\n', n_riser_segs, riser_seg_length);
fprintf('  Completion segments: %d\n', nperf);
fprintf('  Total nodes: %d, total segments: %d\n', n_total_nodes, n_total_segs);

%% Set up pressure relief well in another corner (remains a SimpleWell)

I = nx;
J = ny;

% Perforated layers at depths of 1570.5-1579 m
K = 4:8;

% Calculate cell indices for well perforations
c_pw = arrayfun(@(k) sub2ind(G.cartDims, I, J, k), K)';

% BHP-controlled production well
W_pw = addWell([], G, rock, c_pw, ...
            'Name', 'PW', ...
            'Type', 'bhp', ...
            'Val', p_ref, ...
            'Comp_i', [0, 1], ...
            'refDepth', G.cells.centroids(c_pw(1), 3));

%% Combine wells: regular wells first, MS wells last
% Resulting order: W_all(1) = PW (SimpleWell), W_all(2) = ST-06 (MSW)
W_all = combineMSwithRegularWells(W_pw, MSW);

iPW  = 1;  % Index of the relief well in W_all / wellSols
iINJ = 2;  % Index of the MSW injector in W_all / wellSols

%% Set up simulation schedule

% Target simulation time
totTime = 24*hour;

% Schedule with ramped timesteps
dt_target = 100*minute;  % Final timestep size
nRampSteps = 10;         % Number of ramp-up steps
n_init = 10;
dt_init_factor = 0.001;
timesteps = rampupTimestepsExtended(totTime, dt_target, n_init, nRampSteps, dt_init_factor);
schedule = simpleSchedule(timesteps);

%% Set up the facility with the thermal MSW model

% Switch between the wellbore thermal formulations:
%   true  - enthalpy primary variable (TwoPhaseEnthalpyMultisegmentWell):
%           handles CO2 phase transitions in the wellbore and includes
%           heat exchange with the formation (MSW.heat)
%   false - temperature primary variable (TwoPhaseThermalMultisegmentWell):
%           passive-scalar T advection, no formation heat exchange
use_enthalpy = true;

% Validate model and setup facility
model = model.validateModel();

% Model injection temperature to be higher than surface temperature
t_inj = 8 + 273.15;     % Injection temperature (Page 15)

% Create the thermal MSW model for the injector and a standard SimpleWell
% for the relief well. The order must match W_all.
if use_enthalpy
    mswWellModel = TwoPhaseEnthalpyMultisegmentWell(W_all(iINJ), t_inj, tgrad);
else
    mswWellModel = TwoPhaseThermalMultisegmentWell(W_all(iINJ), t_inj, tgrad);
end
pwWellModel  = SimpleWell(W_all(iPW));

model.FacilityModel = model.FacilityModel.setupWells(W_all, ...
                          {pwWellModel, mswWellModel});

% Use the combined wells to control the schedule
schedule.control.W = W_all;

%% Run simulation

[wellSols, states, report] = simulateScheduleAD(state0, model, schedule);

fprintf('\nSimulation completed successfully!\n');
fprintf('  Total simulation time: %.2f seconds\n', sum(report.SimulationTime));

%% Plot well bottom-hole pressure over time
% For the MSW, take the pressure at the top-reservoir node; node 1
% (wellhead) pressure is stored in wellSol.bhp, nodes 2:nn in
% wellSol.nodePressure (node k -> nodePressure(k-1))
figure('Name', 'Well Bottom-Hole Pressure');

% Smaller figure to get bigger labels 
set(gcf, 'Position', [1     1   680   400])

time_hr = report.ReservoirTime / hour;

bhp_inj  = cellfun(@(x) x(iINJ).nodePressure(top_res_node - 1), wellSols) / barsa;
whp_inj  = cellfun(@(x) x(iINJ).bhp, wellSols) / barsa;
bhp_prod = cellfun(@(x) x(iPW).bhp, wellSols) / barsa;

ll = plot(time_hr, bhp_inj, time_hr, whp_inj, time_hr, bhp_prod);
set(ll, 'LineWidth', 2);
grid on;
xlabel('Time [hours]');
ylabel('Pressure [bar]');
xlim([0 max(time_hr)])
legend('Top-reservoir node', 'Wellhead', 'Relief well', ...
       'Location', 'best');
title('Pressures');

set(gca, 'XScale', 'log');

saveas(gcf, 'BHP.png')


%% Select time steps for the wellbore profile plots
steps_to_plot = unique(round(linspace(1, numel(states), 4)));
colors = lines(numel(steps_to_plot));

% Replace yellow with green
colors(3, :) = [0.4660, 0.6740, 0.1880];

% Node depths from the MSW structure (node 1 = wellhead)
node_depths = MSW.nodes.depth;

%% Plot pressure profile along the wellbore
figure('Name', 'Pressure Profile Along Well');
hold on;
for i = 1:numel(steps_to_plot)
    step = steps_to_plot(i);
    ws = wellSols{step}(iINJ);

    % Combine wellhead pressure (bhp = node 1) with node pressures (2:nn)
    p_all = [ws.bhp; ws.nodePressure] / barsa;

    ll = plot(p_all, node_depths, 'Color', colors(i,:), ...
        'DisplayName', sprintf('%.2f h', report.ReservoirTime(step) / hour));
    set(ll, 'LineWidth', 2);
end
hold off;
set(gcf, 'Position', [1     1   680   400])
set(gca, 'YDir', 'reverse');  % Depth increases downward
grid on;
xlabel('Pressure [bar]');
ylabel('Depth [m]');
title('Pressure Profile Along Wellbore');
legend('Location', 'best');

saveas(gcf, 'pres_wellbore.png')

%% Plot temperature profile along the wellbore
figure('Name', 'Temperature Profile Along Well');
hold on;
for i = 1:numel(steps_to_plot)
    step = steps_to_plot(i);
    ws = wellSols{step}(iINJ);

    % Node 1 (wellhead) is held at the injection temperature; nodes 2:nn
    % are stored in wellSol.t
    t_all = [t_inj; ws.t];

    ll = plot(t_all - 273.15, node_depths, 'Color', colors(i,:), ...
        'DisplayName', sprintf('%.2f h', report.ReservoirTime(step) / hour));
    set(ll, 'LineWidth', 2);
end
hold off;
set(gca, 'YDir', 'reverse');
grid on;
xlabel('Temperature [degC]');
ylabel('Depth [m]');
title('Temperature Profile Along Wellbore');
legend('Location', 'best');

saveas(gcf, 'temper_wellbore.png')

%% Plot gas mass fraction along the wellbore
figure('Name', 'Gas Mass Fraction Along Well');
hold on;

% Get a position of the interface between the injected CO2 and the initial
% fluid in the wellbore (plug-flow estimate, uniform tubing diameter)
area = pi * well_diam^2 / 4;
v_if = vol_rate / area;
interface = riser_top_depth + v_if * report.ReservoirTime(steps_to_plot);

for i = 1:numel(steps_to_plot)
    step = steps_to_plot(i);
    ws = wellSols{step}(iINJ);
    plot(ws.nodeComp(:, 2), node_depths(2:end), '-', ...
        'Color', colors(i,:), 'LineWidth', 2, ...
        'DisplayName', sprintf('%.2f h', report.ReservoirTime(step) / hour));
    if interface(i) < riser_bottom_depth
        line([0 1], [interface(i) interface(i)], ...
            'LineStyle', '--', 'Color', colors(i,:), ...
            'HandleVisibility', 'off')
    end
end
hold off;
set(gca, 'YDir', 'reverse');
grid on;
xlabel('Gas Mass Fraction [-]');
ylabel('Depth [m]');
title('Gas Mass Fraction Along Wellbore');
legend('Location', 'best');

saveas(gcf, 'gas_massfrac_wellbore.png')

%% Plot (P, T) path of the wellbore on the CO2 density map
step = numel(wellSols);
time_lbl = sprintf('%.1f h', report.ReservoirTime(step) / hour);

% Create grid of (P, T) values
n_points = 100;
p_vec = linspace(p_min, p_max, n_points);
T_vec = linspace(T_min, T_max, n_points);
[T_grid, P_grid] = meshgrid(T_vec, p_vec);

% Evaluate density for all points at once
rho_map = reshape(fluid.rhoG(P_grid(:), T_grid(:)), size(P_grid));

% Plot filled contour map
figure('Name', 'CO2 Density Map');
contourf(T_grid - 273.15, P_grid / barsa, rho_map, 50, 'LineColor', 'none');
colorbar;
xlim([5 80])
xlabel('Temperature [degC]');
ylabel('Pressure [bar]');
title(['CO_2 Density [kg/m^3] at ' time_lbl]);
grid on;
hold on;

% Critical point
p_crit = 73.77;
T_crit = 31.1;
plot(T_crit, p_crit, 'ok');
text(T_crit + 2, p_crit, 'Critical Point');

% (P, T) along the wellbore at the selected step
ws = wellSols{step}(iINJ);
p_wb = [ws.bhp; ws.nodePressure];
t_wb = [t_inj; ws.t];

plot(t_wb - 273.15, p_wb / barsa, '.-k');
plot(t_wb(1) - 273.15, p_wb(1) / barsa, 'ok', 'MarkerFaceColor', 'k');
text(t_wb(1) - 273.15 + 2, p_wb(1) / barsa, ...
    ['Wellhead']);
plot(t_wb(end) - 273.15, p_wb(end) / barsa, 'ok', 'MarkerFaceColor', 'k');
text(t_wb(end) - 273.15 + 2, p_wb(end) / barsa, ...
    ['Bottomhole']);
hold off;

saveas(gcf, 'CO2_Density_Map.png')

%% Plot different paths

% Create grid of (P, T) values
n_points = 100;
p_vec = linspace(p_min, p_max, n_points);
T_vec = linspace(T_min, T_max, n_points);
[T_grid, P_grid] = meshgrid(T_vec, p_vec);

% Evaluate density for all points at once
rho_map = reshape(fluid.rhoG(P_grid(:), T_grid(:)), size(P_grid));

% Plot filled contour map
figure('Name', 'CO2 Density Map');
contourf(T_grid - 273.15, P_grid / barsa, rho_map, 50, ...
    'LineColor', 'none', 'HandleVisibility', 'off');
colorbar;
xlim([5 80])
xlabel('Temperature [degC]');
ylabel('Pressure [bar]');
title(['CO_2 Density [kg/m^3]']);
grid on;
hold on;

% Critical point
p_crit = 73.77;
T_crit = 31.1;
plot(T_crit, p_crit, 'ok', 'HandleVisibility', 'off');
text(T_crit + 2, p_crit, 'Critical Point');

% Plot (P, T) path of the wellbore on the CO2 density map
step = numel(wellSols);
time_lbl = sprintf('%.1f h', report.ReservoirTime(step) / hour); 

for i = 1:numel(steps_to_plot)
    step = steps_to_plot(i);    

    % (P, T) along the wellbore at the selected step
    ws = wellSols{step}(iINJ);
    p_wb = [ws.bhp; ws.nodePressure];
    t_wb = [t_inj; ws.t];
    
    plot(t_wb - 273.15, p_wb / barsa, 'Color', colors(i,:), 'LineWidth', 2, ...
        'DisplayName', sprintf('%.2f h', report.ReservoirTime(step) / hour));
    plot(t_wb(1) - 273.15, p_wb(1) / barsa, 'ok', 'MarkerFaceColor', colors(i,:), 'HandleVisibility', 'off');

    if i == 1
        % text(t_wb(1) - 273.15 + 2, p_wb(1) / barsa, ['Wellhead: \rho=' num2str(fluid.rhoG(p_wb(1), t_wb(1)), '%.1f') ' kg/m^3']);
        text(t_wb(1) - 273.15 + 2, p_wb(1) / barsa, 'Wellhead');
    end

    plot(t_wb(end) - 273.15, p_wb(end) / barsa, 'ok', 'MarkerFaceColor', colors(i,:), 'HandleVisibility', 'off');
    % text(t_wb(end) - 273.15 + 2, p_wb(end) / barsa, ...
    %     sprintf('%.2f h', report.ReservoirTime(step) / hour));

    % text(t_wb(end) - 273.15 + 2, p_wb(end) / barsa, ...
    %     ['Bottom: \rho=' num2str(fluid.rhoG(p_wb(end), t_wb(end)), '%.1f') ' kg/m^3']);
end

legend('Location', 'best');
hold off;
saveas(gcf, 'CO2_Density_Map_paths.png')