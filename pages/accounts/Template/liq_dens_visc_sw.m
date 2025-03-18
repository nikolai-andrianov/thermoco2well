%% Liquid density from Span-Wagner EoS and viscosity from a correlation by Laesecke (2017) and Luettmer-Strathmann (1995)

function [rhol, drholdp, drholdT, ...
          mul, dmuldp, dmuldT, sat]  = liq_dens_visc_sw(p, T)

barsa = 1e5;
centi = 1/100;
poise = 0.1;

% assert((T > -30) && (p < 300*barsa), ...
%     ['Span-Wagner EoS: currently not implemented for (p,T) = (' num2str(p) ', ' num2str(T) ')']);

eps = 1e-3;

% Convert to (MPa, degK)
p = p / barsa / 10;
T = T + 273.15;

% Assign the (p, T) to the saturation line if (p, T) is within a stripe -
% to avoid numerical errors
sat = false;
if (p < CO2.pc) && (T < CO2.Tc)
    % No phase boundary behind the critical point
    pv = CO2.pVap(T);
    if abs(p - pv) < eps
        sat = true;
    end
end

% We are above the saturation line, so choose the increments to move away 
% from it during numerical differentiation
dP = +1e-8;
dT = -1e-8;

if sat  
    % If (p, T) is on the saturation line, rhol is the liquid density
    rhol = CO2.rho_pT(pv + eps, T);
    rhol_dp = CO2.rho_pT(pv + eps + dP, T);
    rhol_dT = CO2.rho_pT(pv + eps, T + dT);

    drholdp = (rhol_dp - rhol) / dP;
    drholdT = (rhol_dT - rhol) / dT;

    [mul, ~] = CO2.transport_rhoT_i(rhol, T);
    [mul_dp, ~] = CO2.transport_rhoT_i(pv + eps + dP, T);
    [mul_dT, ~] = CO2.transport_rhoT_i(pv + eps, T + dT);

    dmuldp = (mul_dp - mul) / dP;
    dmuldT = (mul_dT - mul) / dT;  

else
    % Away from the saturation line rhol denotes the single-phase density
    rhol = CO2.rho_pT(p, T);
    rhol_dp = CO2.rho_pT(p + dP, T);
    rhol_dT = CO2.rho_pT(p, T + dT);

    drholdp = (rhol_dp - rhol) / dP;
    drholdT = (rhol_dT - rhol) / dT;   

    [mul, ~] = CO2.transport_rhoT_i(rhol, T);
    [mul_dp, ~] = CO2.transport_rhoT_i(rhol_dp, T);
    [mul_dT, ~] = CO2.transport_rhoT_i(rhol_dT, T + dT);

    dmuldp = (mul_dp - mul) / dP;
    dmuldT = (mul_dT - mul) / dT;      

end

% Convert the viscosity and its derivatives to Pa*s
mul = mul * centi*poise;  
dmuldp = dmuldp * centi*poise;  
dmuldT = dmuldT * centi*poise;  

% Convert the pressure derivatives from (*)/MPa to (*)/Pa
drholdp = drholdp / barsa / 10;
dmuldp = dmuldp / barsa / 10;

% % Debug
% drholdT = 0;
% dmuldT = 0;


end





