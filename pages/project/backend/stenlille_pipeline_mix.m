%% CO2 injection in Stenlille - pipeline - Mixture formulation

function param = stenlille_pipeline_mix(infile)

% Read the input data
[prop, var, val, unit] = textread(infile, "%s %s %f %s", 'delimiter', ',', 'headerlines', 1);
N = length(prop);

% Gravity acceleration (m/s^2)
grav = 9.80665;	

% Conversion constants
centi = 1/100;
meter = 1;
poise = 0.1;
barsa = 1e5;
year = 31556952;
ton = 1e3;

% % Thermodynamic functions using Span-Wagner EoS
param.pvt.gas_dens_visc = @(p, T) gas_dens_visc_sw(p, T);
param.pvt.liq_dens_visc = @(p, T) liq_dens_visc_sw(p, T);

% Fluids data
param.pvt.st = 0.029;	% Surface_tension gas-oil (N/m) 

% Fluid specific heat capacity (J/(kg*degC)
param.pvt.cp_o = 12870;        % Value for 90 bar and 40 degC

% Assign the heat capacities
param.pvt.cp_g = param.pvt.cp_o;
param.pvt.cp_l = param.pvt.cp_o;

for n = 1:N

switch (var{n})

% Well data
case 'D'
	param.D = val(n);		% Well measured depth (m) 
case 'phi'
	param.alpha = val(n) * pi / 180;    	% Inclination angle from horizontal	(convert to rad)
case 'r_ti'
	param.d_ti = 2 * val(n) *centi*meter;	% Tubing inner diameter (m)		
case 'r_to'
	param.d_to = 2 * val(n) *centi*meter;	% Tubing outer diameter (m) - assumed 	
case 'r_ci'
	param.d_ci = 2 * val(n) *centi*meter;	% Casing inner diameter (m)	
case 'r_co'
	param.d_co = 2 * val(n) *centi*meter;	% Casing outer diameter (m)	
case 'r_wb'
	param.d_wb = 2 * val(n) *centi*meter;	% Wellbore daiameter (m)

case 'k_t'
	param.k_t = val(n);		% Tubing thermal conductivity (W/(m*degC)
case 'k_c'
	param.k_c = val(n);		% Casing thermal conductivity (W/(m*degC)	
case 'k_cem'
	param.k_cem = val(n);	% Cement thermal conductivity (W/(m*degC)	
case 'k_e'
	param.k_e = val(n);		% Formation thermal conductivity (W/(m*degC)
case 'rho_e'
	param.rho_e = val(n);	% Formation density (kg/m3)	
case 'cp_e'
	param.cp_e = val(n);	% Formation specific heat capacity (J/(kg*degC)	
case 'dTgeo'
	param.dTgeo = val(n);	% Geothermal gradient (degC/km)	

% Annulus parameters
case 'rho_a'
	param.rho_a = val(n);	% Density (kg/m3)
case 'mu_a'
	param.mu_a = val(n);	% Viscosity (cP)
case 'cp_a'
	param.cp_a = val(n);	% Specific heat capacity (J/(kg*degC)
case 'k_a'
	param.k_a = val(n);		% Thermal conductivity (W/(m*degC)

% Boundary conditions at the top
case 'P'
	param.P = val(n);		% Top boundary pressure (bar)
case 'T'
	param.T = val(n);		% Top boundary temperature (degC)

% Boundary conditions at the bottom
case 'Qm'
	param.Qm = 1e6*val(n)*ton/year;		% CO2 mass flow rate 
	
otherwise
    disp(['"' var{n} '"' ' not handled' ])
endswitch

end

% Annulus parameters
param.beta_a = 3.204e-04; % Thermal expansion coefficient (1/degC)

% Production time
param.T_prod = 50; % in hours
disp(['Steady-state after ' num2str(param.T_prod) ' hours of injection'])

% Boundary conditions at the top
param.nodeT = 0; % p-node at the top

% Bottom hole (p, T)
param.nodeB = 1; % q-node at the bottom

% Formation surface temperature
param.Twh = 24.44; % in degC

% Number of cells
param.N = 100;            

% Experimental data 
param.exp_data = [[NaN NaN NaN];
[NaN NaN NaN]];


end