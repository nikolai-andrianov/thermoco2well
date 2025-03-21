%% Gas density from Span-Wagner EoS and viscosity from a correlation by Laesecke (2017) and Luettmer-Strathmann (1995)

function [rhog, drhogdp, drhogdT, ...
          mug, dmugdp, dmugdT, sat] = gas_dens_visc_sw(p, T)

barsa = 1e5;

% assert((T > -30) && (p < 300*barsa), ...
%     ['Span-Wagner EoS: currently not implemented for (p,T) = (' num2str(p) ', ' num2str(T) ')']);

eps = 1e-3;

% Convert to (MPa, degK)
p = p / barsa / 10;
T = T + 273.15;

% Assign the (p, T) to the saturation line if (p, T) is within a stripe -
% to avoid numerical errors
sat = false;
if p<CO2.pc
    if T < CO2.Tc
		% No phase boundary behind the critical point
		pv = CO2.pVap(T);
		if abs(p - pv) < eps
			sat = true;
		end
	end
end

% We are below the saturation line, so choose the increments to move away 
% from it during numerical differentiation
dP = -1e-8;
dT = +1e-8;

if sat  
    % If (p, T) is on the saturation line, rhog is the gas density
    rhog = CO2.rho_pT(pv - eps, T);
    rhog_dp = CO2.rho_pT(pv - eps + dP, T);
    rhog_dT = CO2.rho_pT(pv - eps, T + dT);

    drhogdp = (rhog_dp - rhog) / dP;
    drhogdT = (rhog_dT - rhog) / dT;

    [mug, ~] = CO2.transport_rhoT_i(rhog, T);
    [mug_dp, ~] = CO2.transport_rhoT_i(pv - eps + dP, T);
    [mug_dT, ~] = CO2.transport_rhoT_i(pv - eps, T + dT);

    dmugdp = (mug_dp - mug) / dP;
    dmugdT = (mug_dT - mug) / dT;    

else
    % Away from the saturation line rhog is zero (the single-phase density
    % is denoted by rhol)
    rhog = 0;
    drhogdp = 0;
    drhogdT = 0;  
    mug = 0;
    dmugdp = 0;
    dmugdT = 0;
end

% Convert the pressure derivatives from (*)/MPa to (*)/Pa
drhogdp = drhogdp / barsa / 10;
dmugdp = dmugdp / barsa / 10;

end