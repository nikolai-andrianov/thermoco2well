%% Steady-state isothermal model
%  
% Compares the numerical solution for steady-state wellbore flow.
%
% Uses the formulation with 1 mass conservation equation for the mixture.
%
% USAGE: 
%   * To setup Example 4.1 from Hasan & Kabir P. 47 use param = example41; 
%   * To setup Example 5.1 from Hasan & Kabir P. 75 use param = example51; 
%   * Then thermoco2well_ss(param)
% 
% References
% Hasan, A.R., Kabir, C.S., 2002. Fluid flow and heat transfer in wellbores. 
%   Society of Petroleum Engineers, Richardson, Texas.

function thermoco2well_ss_mix(param)

SMALL_VALUE = 1e-6;        % Avoid division if |val|<SMALL_VALUE
ITER_EPS = 1e-6;           % Continue iterations until |residual|<ITER_EPS

% Gravity acceleration (m/s^2)
grav = 9.80665;	 

% Conversion constants
milli = 1e-3;
centi = 1/100;
meter = 1;
sec = 1;
hour = 3600;
ft = 0.3048;
inch = 2.54 * centi*meter;
pound = 0.45359237;
dyne = 1e-5;
poise = 0.1;
psia = pound*grav/inch^2;
barsa = 1e5;
celsius = @(degF) (degF - 32) * 5 / 9;
degF = celsius(2) - celsius(1);   % 1 degF in degC
fahrenheit = @(degC) degC * 9 / 5  + 32;
   

%% Assign parameters 

% Annulus parameters
rho_a = param.rho_a;    % Density (kg/m3)
mu_a = param.mu_a * 0.001;      % Viscosity (Pa*s)  
cp_a = param.cp_a;      % Specific heat capacity (J/(kg*degC)
k_a = param.k_a;        % Thermal conductivity (W/(m*degC)
beta_a = param.beta_a;  % Thermal expansion coefficient (1/degC)

% Well data
D = param.D;            % Well depth (m) 
alpha = param.alpha;    % Inclination angle from horizontal
d_ti = param.d_ti;      % Tubing inner diameter (m)
d_to = param.d_to;      % Tubing outer diameter (m)
d_ci = param.d_ci;      % Casing inner diameter (m)
d_co = param.d_co;      % Casing outer diameter (m)
d_wb = param.d_wb;      % Wellbore daiameter (m)
k_t = param.k_t;        % Tubing thermal conductivity (W/(m*degC)
k_c = param.k_c;        % Casing thermal conductivity (W/(m*degC)
k_cem = param.k_cem;    % Cement thermal conductivity (W/(m*degC)
k_e = param.k_e;        % Formation thermal conductivity (W/(m*degC)
rho_e = param.rho_e;    % Formation density (kg/m3)
cp_e = param.cp_e;   % Formation specific heat capacity (J/(kg*degC)
dTgeo = param.dTgeo / 1e3; % Geothermal gradient (degC/m)
% The following parameters are calculated in a loop below
% Tei: Initial formation temperature
% tD: Dimensionless time
% TD: Dimensionless temperature

% Formation surface temperature
Twh = param.Twh; % in degC

% Experimental data 
exp_data = param.exp_data;

% Setup well geometry
dl = ones(param.N, 1) * param.D / param.N;
len = [0; cumsum(dl)];
x = len * cos(param.alpha);
y = zeros(length(x), 1);
z = - len * sin(param.alpha);   % z-axis is oriented downwards
%z = len * sin(param.alpha);   % z-axis is oriented upwards
Nn = length(x);         % Number of nodes
Ns = Nn - 1;            % Number of segments

% Provide roughness which is not available at Examples 4.1 & 5.1
rough = 0.0254*milli*meter;     % Roughness (mm)

% Get the PVT properties
pvt = param.pvt;

%% Heat conduction in the formation 

% Production/injection time
time = param.T_prod * 3600;  % in sec

% Dimensionless time
td = time * k_e / (rho_e * cp_e * d_wb^2/4);

% Hasan & Kabir approximation to the dimensionless temperature
if td < 1.5
    TD = 1.128*sqrt(td).*(1 - 0.3*sqrt(td));
else
    TD = (0.4063 + 0.5*log(td)).*(1 + 0.6./td);
end

% The integral solution
I = - 0.5 * pi * TD;

%% Define nodes

% Constant fields for nodes
% x, y, z: coordinates (m) 
% Ns: number of adjacent segments
% ss: index of the corresponding source or sink 
%     =-1 if the node is not a source or a sink
%     = 0 for a p-node
%     = 1 for a q-node
ncvals =    {0,   0,   0,  2,  -1};
ncfields = {'x', 'y', 'z', 'Ns', 'ss'};

% Variable fields for nodes
% p: pressure (Pa)
% T: temperature (degC)
% s: array of indices of adjacent segments
nvvals =    {0,   0,  []};
nvfields = {'p', 'T', 's'};

% Merge the nodes' fields
nvals = cat(2, nvvals, ncvals);
nfields = cat(2, nvfields, ncfields);

%% Define segments
% Constant fields for segments
% ind: segment index
% i1: index of the 1st node
% i2: index of the 1st node
% diam: diameter (m)
% rough: roughness (mm)
% len: length (m)
scvals =    {0,     0,    0,    d_ti,   rough,   0,     0};
scfields = {'ind', 'i1', 'i2', 'diam', 'rough', 'len', 'angle'};

% Variable fields for segments
% vsl:  Superficial liquid velocity
% vsg:  Superficial gas velocity
% ll:   Liquid holdup
% regime: 1 - bubble, 2 - slug
% k_e:  Formation thermal conductivity 
% U: overall heat transfer coefficient
% I: Hasan & Kabir approximation to the integral solution for heat conduction in the formation
% Te: formation temperature at infinity using geothermal gradient
svvals = cell(1, 8);
svvals(1:8) = {-1};
svfields = {'vsl', 'vsg', 'll', 'regime', 'k_e', 'U', 'I', 'Te'};

% Debug fields for segments
sdvals = cell(1, 10);
sdvals(1:10) = {-1};
sdfields = {'rhog', 'drhogdp', 'rhol', 'drholdp', 'mug', 'dmugdp', 'mul', 'dmuldp', 'st', 'qs'};

% Merge the segments' fields
svals = cat(2, svvals, scvals, sdvals);
sfields = cat(2, svfields, scfields, sdfields);

%% Initialize the nodes' constant fields and the initial solution
N(1) = cell2struct(nvals, nfields, 2);
N(1).x = x(1);
N(1).y = y(1);
N(1).z = z(1);

% Assign the initial formation temperature
N(1).T = Twh;

for i = 2:Nn
    N(i) = cell2struct(nvals, nfields, 2);
    N(i).x = x(i);
    N(i).y = y(i);
    N(i).z = z(i);
    N(i).s(1) = i - 1;
    N(i).s(2) = i;

    S(i - 1) = cell2struct(svals, sfields, 2);
    S(i - 1).i1 = i - 1;
    S(i - 1).i2 = i;
    S(i - 1).len = sqrt((x(i) - x(i-1))^2 + (y(i) - y(i-1))^2 + (z(i) - z(i-1))^2);

    % Segment angle from horizontal ("-z" because the vertical coordinate
    % is oriented downwards).
    if (S(i - 1).len > SMALL_VALUE)	
        S(i - 1).angle = asin((-N(S(i - 1).i2).z + N(S(i - 1).i1).z) / S(i - 1).len);
        %S(i - 1).angle = asin((N(S(i - 1).i2).z - N(S(i - 1).i1).z) / S(i - 1).len);
    end

    % Initialize the nodes with the BHP
    N(i).p = param.P * barsa;

    % Initialize the temperature in the nodes using the geothermal gradient
    N(i).T = N(i-1).T - S(i-1).len * sin(S(i-1).angle) * dTgeo; 

    % Assign the temperature at infinity at the segments' midpoint level
    % with the geothermal gradient
    S(i-1).Te = N(i-1).T - 0.5 * S(i-1).len * sin(S(i-1).angle) * dTgeo; 

    % Overall heat transfer coefficient
    S(i-1).U = 1. / (log(d_to/d_ti)/k_t + log(d_ci/d_to)/k_a + log(d_co/d_ci)/k_c + log(d_wb/d_co)/k_cem);

    % Integral solution to the heat conduction eq in the formation
    S(i-1).I = I;

    % Formation thermal conductivity
    S(i-1).k_e = k_e;
   
end

% Set up the parameters for the top ...	
if param.nodeT == 1
    disp('BC: q-node at the top')
    N(1).Ns = 1;    % One neighbor segment
    N(1).s = 1;     
    N(1).ss = 1;    % q-node
    N(1).Qm = param.Qm; % Assign the mass flow rates (kg/sec)
    % Assign the BHP pressure for initialization
    N(1).p = param.P * barsa;
elseif param.nodeT == 0
    disp('BC: p-node at the top')
    N(1).Ns = 1;    % One neighbor segment
    N(1).s = 1;     
    N(1).ss = 0;    % p-node
    % Assign the BHP pressure for initialization
    N(1).p = param.P * barsa;
    N(1).T = param.T;

else
    error('Top BC: not implemented..')
end

% ... and bottom 
if param.nodeB == 0
    disp('BC: p-node at the bottom')
    N(Nn).Ns = 1;   % One neighbor segment
    N(Nn).s = Nn - 1;
    N(Nn).ss = 0;   % p-node
    N(Nn).p = param.P * barsa;
    N(Nn).T = param.T; 
elseif param.nodeB == 1
    disp('BC: q-node at the bottom')
    N(Nn).Ns = 1;   % One neighbor segment
    N(Nn).s = Nn - 1;
    N(Nn).ss = 1;   % q-node
    N(Nn).Qm = param.Qm; % Assign the mass flow rates (kg/sec)
else
    error('Bottom BC: not implemented..')
end

% Set up the initial solution for the segments using the initial pressure.
% By convention in gas_dens_visc_sw, gas density is non-zero only on the
% saturation line
[rg_init, ~, ~, ~, ~, ~, ~] = pvt.gas_dens_visc(param.P * barsa, param.T);
[rl_init, ~, ~, ~, ~, ~, ~] = pvt.liq_dens_visc(param.P * barsa, param.T);

% Assign the initial velocity using the liquid density and mass flow rate
Area = pi * S(N(Nn).s(1)).diam^2 / 4;
ql_init = param.Qm / Area;
vsl_init = ql_init / rl_init;

for j = 1:Ns    
    % Assign the single flow liquid conditions
    S(j).ll = 1;
    
    % Assign bubble regime for consistency
    S(j).regime = 1;
    
    S(j).vsl = vsl_init;
    [S(j).vsg, ~] = drift_flux(S(j));

    S(j).rhog = rg_init;
    S(j).rhol = rl_init;
end


%% Newton iterations until the residual norm is large
niter = 0;
while (true) 
    
    niter = niter + 1;
    
    [J, Fs, S] = computeJacobian(N, S, pvt, SMALL_VALUE);

    % Debug - compare with CPP
    debug = false;
    if debug
        Jac_cpp = readmatrix(['Jacs_p' num2str(niter) '.dat']);
        ind = (Jac_cpp==0);
        J_nz = Jac_cpp;
        J_nz(ind) = 999;
        dJ = abs(J - Jac_cpp) ./ J_nz;
        diff_dJ = max(max(dJ));
    
        Fs_cpp = readmatrix(['Fs' num2str(niter) '.dat']);
        ind = (Fs_cpp==0);
        F_nz = Fs_cpp;
        F_nz(ind) = 999;
        dF = abs(Fs - Fs_cpp) ./ F_nz;
        diff_dF = max(max(dF));
    end

    resnorm = norm(Fs);
    disp(['iter = ' num2str(niter) ', residual = ' num2str(resnorm)]);

%     if niter == 50
%         break;
%     end

    % Find the solution increments
    dS = J \ Fs;

%     % Debug
%     dS = 0.05 * dS;

    % Number of p-nodes
    ni = vertcat(N.ss);
    Npss = sum(ni==0);    

    % Update the pressures and temperatures everywhere except of the p-nodes
    inss = 1;
    for i = 1:Nn
        if (N(i).ss ~= 0) 
            N(i).p = N(i).p + dS(inss);
            N(i).T = N(i).T + dS(Nn - Npss + Ns + inss);
            inss =  inss + 1;
        end
    end

    % Update the velocities 
    for j = 1:Ns
		S(j).vsl = S(j).vsl + dS(Nn - Npss + j);
    end

    if resnorm < ITER_EPS
        break
    end

end

% Get the numerical results
MD = sqrt(x.^2 + y.^2 + z.^2);  % Measured depth
p = [N(:).p]' / barsa;
T = [N(:).T]';
Te = [S(:).Te]';

% Save the results
%  csvwrite('results.csv', [MD, p, T]);

filename = "results.csv";
fid = fopen (filename, "w");
fputs(fid, "MD (m),Pressure (bar), Temperature (degC)\n");
fclose(fid);
dlmwrite(filename, [MD, p, T], "-append")
 
disp('Results are saved to results.csv');

end

%% Compute the Jacobian and the RHS
function [J, Fs, S] = computeJacobian(N, S, pvt, SMALL_VALUE)

Nn = length(N);
Ns = length(S);

% Index shift due to cutting of p-nodes
npss = 0; 

% Number of p-nodes
ni = vertcat(N.ss);
Npss = sum(ni==0);

% Allocate the space for the Jacobian and for the RHS
% Nn - Npss mass conservation eqs for the mixture
% Ns pressure drop eqs
% Ns temperature drop eqs
J = zeros(Nn - Npss + 2 * Ns, Nn - Npss + 2 * Ns);
Fs = zeros(Nn - Npss + 2 * Ns, 1);

% Mass conservation in nodes
for i = 1:Nn

    % Keep pressure derivatives for the node N(i) in dFdp(N(i).Ns + 1)
    dFgdp(N(i).Ns + 1) = 0;
    dFodp(N(i).Ns + 1) = 0;
    dFdp_nind(N(i).Ns + 1) = i;

    % Keep temperature derivatives for the node N(i) in dFdT(N(i).Ns + 1)
    dFgdT(N(i).Ns + 1) = 0;
    dFodT(N(i).Ns + 1) = 0;

    % RHS
	if (N(i).ss == 1) 
        % For q-nodes initialize the RHS with rates
        Fs(i - npss) = - N(i).Qm;   
    else
        % For interior nodes; don't include the entry for p-nodes 
        if (N(i).ss ~= 0) 
            Fs(i - npss) = 0;   
        else
            % Increase the counter only if the p-node is at the start of
            % the branch (e.g. in stenlille, but not in example51).
            if i ~= Nn
                npss = npss + 1; 
            end
        end
    end

    % Include contributions from neighbor nodes
    for j = 1:N(i).Ns

        ib1 = i;
        if i == 1
            % Current segment is to the right of N(i)
            ib2 = ib1 + 1;
            sgn = +1;
        else
            if N(i).s(j) == ib1 - 1
                % Current segment is to the left of N(i)
                ib2 = ib1 - 1;
                sgn = -1;	
            elseif N(i).s(j) == ib1
                % Current segment is to the right of N(i)
                ib2 = ib1 + 1;
                sgn = +1;
            else
                disp('Something wrong with node numbering! Exiting..');
                return;
            end

        end

        ps = 0.5 *(N(ib1).p + N(ib2).p); % Average pressure for the segment
        Ts = 0.5 *(N(ib1).T + N(ib2).T); % Average temperature for the segment

        % Update the current segment's vsg using vsl and liquid holdup in the drift-flux model 
        [S(N(i).s(j)).vsg, S(N(i).s(j)).dvsgdvsl] = drift_flux(S(N(i).s(j)));

        [rhogs, drhogsdps, drhogsdTs, ~, ~, ~, ~] = pvt.gas_dens_visc(ps, Ts);  % Average gas density for the segment and its derivatives
        drhogsdp1 = 0.5 * drhogsdps;
        drhogsdp2 = 0.5 * drhogsdps;
        drhogsdT1 = 0.5 * drhogsdTs;
        drhogsdT2 = 0.5 * drhogsdTs;

        [rhols, drholsdps, drholsdTs, ~, ~, ~, ~] = pvt.liq_dens_visc(ps, Ts);  % Average liquid density for the segment and its derivative
        drholsdp1 = 0.5 * drholsdps;
        drholsdp2 = 0.5 * drholsdps;
        drholsdT1 = 0.5 * drholsdTs;
        drholsdT2 = 0.5 * drholsdTs;        

        Area = pi * S(N(i).s(j)).diam^2 / 4;   % Segment's cross-sectional area

		dFgdp1 = Area * drhogsdp1 * sgn * S(N(i).s(j)).vsg;
		dFgdp2 = Area * drhogsdp2 * sgn * S(N(i).s(j)).vsg;
		%dFgdvsg = Area * rhogs * sgn;
		dFgdvsl = Area * rhogs * sgn * S(N(i).s(j)).dvsgdvsl;
		dFgdT1 = Area * drhogsdT1 * sgn * S(N(i).s(j)).vsg;
		dFgdT2 = Area * drhogsdT2 * sgn * S(N(i).s(j)).vsg;        

        dFodp1 = Area * drholsdp1 * sgn * S(N(i).s(j)).vsl;		% dFdp1=dFdp2 by definition rhos=rhos(0.5*(p1+p2))
		dFodp2 = Area * drholsdp2 * sgn * S(N(i).s(j)).vsl;
		%dFodvsg = 0;
		dFodvsl = Area * rhols * sgn;
        dFodT1 = Area * drholsdT1 * sgn * S(N(i).s(j)).vsl;		% dFdp1=dFdp2 by definition rhos=rhos(0.5*(p1+p2))
		dFodT2 = Area * drholsdT2 * sgn * S(N(i).s(j)).vsl;        

        % Accumulate the pressure derivatives 
		dFgdp(j) = dFgdp1;			                    % dFdp1=dFdp2 by definition rhos=rhos(0.5*(p1+p2))
        dFdp_nind(j) = ib2;		    	                    % Index for consequent writing of columns
		dFgdp(N(i).Ns + 1) = dFgdp(N(i).Ns + 1) + dFgdp1;	% Accumulate the derivative in the current node N(i) for all segments

		dFodp(j) = dFodp1;			
		dFodp(N(i).Ns + 1) = dFodp(N(i).Ns + 1) + dFodp1;	

        % Accumulate the temperature derivatives
        dFgdT(j) = dFgdT1;	
        dFgdT(N(i).Ns + 1) = dFgdT(N(i).Ns + 1) + dFgdT1;	% Accumulate the derivative in the current node N(i) for all segments

        dFodT(j) = dFodT1;		  
        dFodT(N(i).Ns + 1) = dFodT(N(i).Ns + 1) + dFodT1;	

        
        % Velocity derivatives
		%dFGdvsg(j) = dFgdvsg;
		dFGdvsl(j) = dFgdvsl;
		dFdV_sind(j) = N(i).s(j);

		%dFOdvsg(j) = dFodvsg;
		dFOdvsl(j) = dFodvsl;

        % Don't include the RHS entries for p-nodes 
        if (N(i).ss ~= 0)     
            Fs(i - npss) = Fs(i - npss) - Area * (rhogs * sgn * S(N(i).s(j)).vsg + rhols * sgn * S(N(i).s(j)).vsl);
        end

    end

    % Don't include the Jacobian entries for p-nodes 
    if (N(i).ss ~= 0) 

        % Set up the Jacobian entries for the mass conservation eqs
        for k = 1:N(i).Ns + 1
            j = dFdp_nind(k);
            % Write the pressure and temperature derivatives for all nodes except the
            % pressure nodes.
            if (N(j).ss ~= 0) 
		        J(i - npss, j - npss) = dFgdp(k) + dFodp(k);
                %disp([num2str(i - npss) ', ' num2str(j - npss)])
                J(i - npss, j - npss + Nn-Npss + Ns) = dFgdT(k) + dFodT(k);
                %disp([num2str(i - npss) ', ' num2str(j - npss + Nn-Npss + Ns)])
            end
        end

        for k = 1:N(i).Ns 
            j = dFdV_sind(k);
            % Velocity derivatives
            J(i - npss, j + Nn-Npss)  = dFGdvsl(k) + dFOdvsl(k); 
            %disp([num2str(i - npss) ', ' num2str(j + Nn-Npss)])
        end

    end       

end

% Pressure and temperature drops across the segments
for j = 1:Ns

    % Get the segment phase densities and viscosities and their derivatives, 
    % using the average pressure and temperature.
    ps = 0.5*(N(S(j).i1).p + N(S(j).i2).p);
    Ts = 0.5*(N(S(j).i1).T + N(S(j).i2).T);

    % Keep the segment average temperature
    S(j).T = Ts;
        
    % Average gas density and viscosity for the segment and its derivatives
    [S(j).rhog, S(j).drhogdp, S(j).drhogdT, ...
     S(j).mug, S(j).dmugdp, S(j).dmugdT, S(j).sat] = pvt.gas_dens_visc(ps, Ts);  

    % Average liquid density and viscosity for the segment and its derivatives
    [S(j).rhol, S(j).drholdp, S(j).drholdT, ...
     S(j).mul, S(j).dmuldp, S(j).dmuldT, S(j).sat] = pvt.liq_dens_visc(ps, Ts);  

    % Assign the constant surface tension and the phase heat capacities
    S(j).st = pvt.st;
    S(j).cp_g = pvt.cp_g;
    S(j).cp_l = pvt.cp_l;

    [S(j), pg, d_pg_dp, d_pg_dvsl, d_pg_dT, ...
           Q, d_Q_dp, d_Q_dvsl, d_Q_dT] ...
        = pressure_temp_drop(S(j), SMALL_VALUE);

    % Pressure drop derivatives
    dFdp1 = -1 + 0.5 * d_pg_dp;
	dFdp2 = 1 + 0.5 * d_pg_dp;
	dFdvsl = d_pg_dvsl;
    dFdT1 = 0.5 * d_pg_dT;
	dFdT2 = 0.5 * d_pg_dT;

    % Temperature drop derivatives
    dGdp1 = 0.5 * d_Q_dp;
	dGdp2 = 0.5 * d_Q_dp;
	dGdvsl = d_Q_dvsl;
    dGdT1 = -1 + 0.5 * d_Q_dT;
    dGdT2 = 1 + 0.5 * d_Q_dT;

    % Write the pressure and temperature derivatives for all nodes except the
    % pressure nodes.
    if (N(S(j).i2).ss ~= 0) 
        J(Nn - Npss + j, S(j).i2 - npss) = dFdp2;
        J(Nn - Npss + j, Nn - Npss + Ns + S(j).i2 - npss) = dFdT2;
        J(Nn - Npss + Ns + j, S(j).i2 - npss) = dGdp2;     
        J(Nn - Npss + Ns + j, Nn - Npss + Ns + S(j).i2 - npss) = dGdT2;   

%         disp([num2str(Nn - Npss + j) ', ' num2str(S(j).i2 - npss)])
%         disp([num2str(Nn - Npss + j) ', ' num2str(Nn - Npss + Ns + S(j).i2 - npss)])
%         disp([num2str(Nn - Npss + Ns + j) ', ' num2str(S(j).i2 - npss)])
%         disp([num2str(Nn - Npss + Ns + j) ', ' num2str(Nn - Npss + Ns + S(j).i2 - npss)])

    end
    if (N(S(j).i1).ss ~= 0) 
        J(Nn - Npss + j, S(j).i1 - npss) = dFdp1;
        J(Nn - Npss + j, Nn - Npss + Ns + S(j).i1 - npss) = dFdT1;
        J(Nn - Npss + Ns + j, S(j).i1 - npss) = dGdp1;   
        J(Nn - Npss + Ns + j, Nn - Npss + Ns + S(j).i1 - npss) = dGdT1;  

%         disp([num2str(Nn - Npss + j) ', ' num2str(S(j).i1 - npss)])
%         disp([num2str(Nn - Npss + j) ', ' num2str(Nn - Npss + Ns + S(j).i1 - npss)])
%         disp([num2str(Nn - Npss + Ns + j) ', ' num2str(S(j).i2 - npss)])
%         disp([num2str(Nn - Npss + Ns + j) ', ' num2str(Nn - Npss + Ns + S(j).i1 - npss)])

    end

    J(Nn - Npss + j, Nn - Npss + j) = dFdvsl;
    J(Nn - Npss + Ns + j, Nn - Npss + j) = dGdvsl;    

%     disp([num2str(Nn - Npss + j) ', ' num2str(Nn - Npss + j)])
%     disp([num2str(Nn - Npss + Ns + j) ', ' num2str(Nn - Npss + j)])

    % RHS
    Fs(Nn - Npss + j) = -(N(S(j).i2).p - N(S(j).i1).p + pg);
    Fs(Nn - Npss + Ns + j) = -(N(S(j).i2).T - N(S(j).i1).T + Q);

end


end

%% Compute the pressure drop across a segment
function [S, pg, d_pg_dp, d_pg_dvsl, d_pg_dT, ...
             Q, d_Q_dp, d_Q_dvsl, d_Q_dT] = pressure_temp_drop(S, SMALL_VALUE)

g = 9.80665;    % Gravity acceleration 

% Use the absolute values of vsl for calculating the holdup.
sgn_vsl = 1;
if (S.vsl < 0) 
    sgn_vsl = -1;
end
vsl = sgn_vsl * S.vsl;

% Calculate vsg = vsg(vsl) and the derivative - using the absolute values of velocities
St.ll = S.ll;
St.regime = S.regime;
St.vsl = vsl;
[vsg, dvsgdvsl] = drift_flux(St);
sgn_vsg = 1;
if (vsg < 0) 
    sgn_vsg = -1;
end
vsg = sgn_vsg * vsg;

% Mixture velocity... 
vm = vsg + vsl;	

% ... and its derivatives
dvmdp = 0;
dvmdvsl = dvsgdvsl + 1;

% The homogeneous (no-slip) holdup..
if ((vsl < SMALL_VALUE) || (vm < SMALL_VALUE)) 
    error('Single-phase gas flow currently not handled!')
	ll = 0;
    dlldvsg = 0;
    dlldvsl = 0;
else

    S.regime = get_regime(S);

    if (S.regime == 1) 	
        % Bubble flow
        
        % Approximate with the homogeneous (no-slip) holdup
        ll = vsl / vm;
        dlldvsl = (vsg - vsl * dvsgdvsl) / vm^2;

        % Mixture density and viscosity..
        rhom = S.rhol * ll + S.rhog * (1 - ll);
        mum = S.mul * ll + S.mug * (1 - ll);
        
        % ... and their derivatives
        drhomdp = S.drholdp * ll + S.drhogdp * (1 - ll);
        drhomdT = S.drholdT * ll + S.drhogdT * (1 - ll);
        drhomdvsl = dlldvsl * (S.rhol - S.rhog);
        
        dmumdp = S.dmuldp * ll + S.dmugdp * (1 - ll);
        dmumdT = S.dmuldT * ll + S.dmugdT * (1 - ll);
        dmumdvsl = dlldvsl * (S.mul - S.mug);
        
        % Reynolds number..
        Re = rhom * vm * S.diam / mum;
        
        % ... and its derivatives
        dRedp = vm * S.diam / mum^2 * (drhomdp*mum - rhom*dmumdp);
        dRedT = vm * S.diam / mum^2 * (drhomdT*mum - rhom*dmumdT);
        dRedvsl = S.diam * ( dvmdvsl * rhom/mum + vm *(drhomdvsl*mum - rhom*dmumdvsl) / mum^2);
        
        % Friction coefficient..
        f = (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-2;
        
        % ... and its derivatives
        dfdp = -2 * (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-3 * ...
            2 * (4.5223 * log(Re) - 3.8215) / Re * ...
            dRedp*(4.5223 * (log(Re) - 1) - 3.8215) / (4.5223 * log(Re) - 3.8215)^2;

        dfdT = -2 * (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-3 * ...
            2 * (4.5223 * log(Re) - 3.8215) / Re * ...
            dRedT*(4.5223 * (log(Re) - 1) - 3.8215) / (4.5223 * log(Re) - 3.8215)^2;

        dfdvsl = -2 * (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-3 * ...
            2 * (4.5223 * log(Re) - 3.8215) / Re * ...
            dRedvsl*(4.5223 * (log(Re) - 1) - 3.8215) / (4.5223 * log(Re) - 3.8215)^2;

    elseif (S.regime == 2) 	
        % Slug flow

        C0 = 2;
        ll = 1 - vsg / (C0 * vm);
        dlldvsl =  C0 * (vsg - vsl * dvsgdvsl) / (C0*vm)^2;

        % Mixture density and viscosity..
        rhom = S.rhol * ll + S.rhog * (1 - ll);
        mum = S.mul * ll + S.mug * (1 - ll);
        
        % ... and their derivatives
        drhomdp = S.drholdp * ll + S.drhogdp * (1 - ll);
        drhomdT = S.drholdT * ll + S.drhogdT * (1 - ll);
        drhomdvsl = dlldvsl * (S.rhol - S.rhog);
        
        dmumdp = S.dmuldp * ll + S.dmugdp * (1 - ll);
        dmumdT = S.dmuldT * ll + S.dmugdT * (1 - ll);
        dmumdvsl = dlldvsl * (S.mul - S.mug);
        
        % Reynolds number..
        Re = rhom * vm * S.diam / mum;
        
        % ... and its derivatives
        dRedp = vm * S.diam / mum^2 * (drhomdp*mum - rhom*dmumdp);
        dRedT = vm * S.diam / mum^2 * (drhomdT*mum - rhom*dmumdT);
        dRedvsl = S.diam * ( rhom/mum + vm *(drhomdvsl*mum - rhom*dmumdvsl) / mum^2);

        % Apparently this expression for the friction coefficient is
        % leading to a bad approximation to the pressure gradient for
        % Example 4.1
%         f = 0.3164 * Re^-0.25;
%         dfdp = - 0.3164 * 0.25 * Re^-1.25 * dRedp;
%         dfdvsg = - 0.3164 * 0.25 * Re^-1.25 * dRedvsg;
%         dfdvsl = - 0.3164 * 0.25 * Re^-1.25 * dRedvsl;

        % Friction coefficient..
        f = (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-2;
        
        % ... and its derivatives
        dfdp = -2 * (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-3 * ...
            2 * (4.5223 * log(Re) - 3.8215) / Re * ...
            dRedp*(4.5223 * (log(Re) - 1) - 3.8215) / (4.5223 * log(Re) - 3.8215)^2;

        dfdT = -2 * (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-3 * ...
            2 * (4.5223 * log(Re) - 3.8215) / Re * ...
            dRedT*(4.5223 * (log(Re) - 1) - 3.8215) / (4.5223 * log(Re) - 3.8215)^2;
      
        dfdvsl = -2 * (2 * log(Re / (4.5223 * log(Re) - 3.8215)))^-3 * ...
            2 * (4.5223 * log(Re) - 3.8215) / Re * ...
            dRedvsl*(4.5223 * (log(Re) - 1) - 3.8215) / (4.5223 * log(Re) - 3.8215)^2;
    else
        error('pressure_temp_drop: Flow regime not implemented..');
    end


end

% Keep liquid holdup among segments' fields
S.ll = ll;

% Gas holdup and its derivatives
lg = 1 - ll;
dlgdvsl = - dlldvsl;

% Gravitational pressure drop...
pgg = rhom * g * S.len * sin(S.angle);

% ... and its derivatives
d_pgg_dp = drhomdp * g * S.len * sin(S.angle);
d_pgg_dT = drhomdT * g * S.len * sin(S.angle);
d_pgg_dvsl = drhomdvsl * g * S.len * sin(S.angle);

% Frictional pressure drop...
pgf = 0.5 * f * rhom * sgn_vsl * vm * abs(sgn_vsl * vm) / S.diam * S.len;

% ... and its derivatives
d_pgf_dp = sgn_vsl * vm^2 * S.len / (2 * S.diam) * (dfdp*rhom + f*drhomdp);
d_pgf_dT = sgn_vsl * vm^2 * S.len / (2 * S.diam) * (dfdT*rhom + f*drhomdT);
d_pgf_dvsl = sgn_vsl * S.len / (2 * S.diam) * (2*vm*dvmdvsl * f * rhom + vm^2*(dfdvsl*rhom + f*drhomdvsl));

% Total pressure drop and its derivatives
pg = pgg + pgf;
d_pg_dp = d_pgg_dp + d_pgf_dp;
d_pg_dT = d_pgg_dT + d_pgf_dT;
d_pg_dvsl = d_pgg_dvsl + d_pgf_dvsl;

Area = pi * S.diam^2 / 4;   % Segment's cross-sectional area

% Heat flux from/to the formation
k = 2*pi*S.U*S.k_e / (S.k_e - S.U*S.I);

% % Debug
% g = 0;
% k = 0;

qs = k * (S.T - S.Te);
dqsdT = k;

% Debug - keep qs in output fields
S.qs = qs;



% If a holdup is zero, set the corresponding velocity and density locally 
% to 1e9 to avoid division by zero 
rhog = S.rhog;
rhol = S.rhol;
if lg < SMALL_VALUE
    vsg = 1e9;
    rhog = 1e9;
end
if ll < SMALL_VALUE
    vsl = 1e9;
    rhol = 1e9;
end

% Temperature drop
Q = S.len * (g * sin(S.angle) * (lg/S.cp_g + ll/S.cp_l) + ...
    qs * (lg^2/(Area*rhog*sgn_vsg*vsg*S.cp_g) + ll^2/(Area*rhol*sgn_vsl*vsl*S.cp_l)) );

d_Q_dp = - S.len * qs * (lg^2/(Area * rhog^2 * sgn_vsg* vsg*S.cp_g) * S.drhogdp + ...
                         ll^2/(Area * rhol^2 * sgn_vsl*vsl*S.cp_l) * S.drholdp) ;

d_Q_dT = S.len * dqsdT * (lg^2/(Area*rhog*sgn_vsg*vsg*S.cp_g) + ll^2/(Area*rhol*sgn_vsl*vsl*S.cp_l)) - ....
         S.len * qs * (lg^2/(Area * rhog^2 * sgn_vsg*vsg*S.cp_g) * S.drhogdT + ...
                       ll^2/(Area * rhol^2 * sgn_vsl*vsl*S.cp_l) * S.drholdT) ;

d_Q_dvsl = S.len * (g * sin(S.angle) * dlgdvsl * (1/S.cp_g - 1/S.cp_l) + ...
           qs * (2 * lg * dlgdvsl * vsg - lg^2 * dvsgdvsl)/(Area*rhog*vsg^2*S.cp_g) + ...
           qs * (2 * ll * dlldvsl * vsl - ll^2)           /(Area*rhol*vsl^2*S.cp_l));


end

%% Get flow regime and liquid holdup for the segment

function [regime, ll] = get_regime(S)

% Use the absolute values of velocities for calculating the holdup.
sgn_vsg = 1;
if (S.vsg < 0) 
    sgn_vsg = -1;
end
sgn_vsl = 1;
if (S.vsl < 0) 
    sgn_vsl = -1;
end

vsg = sgn_vsg * S.vsg;
vsl = sgn_vsl * S.vsl;

% Mixture velocity... 
vm = vsg + vsl;	

g = 9.80665;    % Gravity acceleration 

% Harmathy's terminal rise velocity, Eq. (3.6) p. 24
v00 = 1.53 * (g*(S.rhol - S.rhog)*S.st / S.rhol^2)^0.25;

% Superficial gas velocity needed for transition bubbly -> slug flow. 
vt = (0.429*vsl + 0.357*v00)*abs(sin(S.angle));  % Use abs value to account for proper alpha  = 3*pi/2 + theta

if (vsg < vt) 	
    % Bubble flow
    regime = 1;

    % Approximate with the homogeneous (no-slip) holdup
    ll = vsl / vm;    
else
    % Slug flow
    regime = 2;

    C0 = 2;
    ll = vsl / (C0 * vm);    
end

end

%% Drift-flux model

function [vsg, dvsgdvsl] = drift_flux(S)

SMALL_VALUE = 1e-6;        % Avoid division if |val|<SMALL_VALUE

if (S.regime == 1) 	
    % Bubble flow
    C0 = 1;
elseif (S.regime == 2) 	
    % Slug flow
    C0 = 2;
else
    error('drift_flux: Flow regime not implemented..');
end

lg = 1 - S.ll;
denom = 1 - lg * C0;
if abs(denom) < SMALL_VALUE
    error('drift_flux: Division by zero')
end

vsg = S.vsl * lg*C0 / denom;
dvsgdvsl = lg*C0 / denom;

end

% function [vsl, dvsldvsg] = drift_flux(S)
% 
% if (S.regime == 1) 	
%     % Bubble flow
%     C0 = 1;
% elseif (S.regime == 2) 	
%     % Slug flow
%     C0 = 2;
% else
%     error('drift_flux: Flow regime not implemented..');
% end
% 
% lg = 1 - S.ll;
% vsl = S.vsg * (1 - lg*C0) / (lg*C0);
% dvsldvsg = (1 - lg*C0) / (lg*C0);
% 
% end

