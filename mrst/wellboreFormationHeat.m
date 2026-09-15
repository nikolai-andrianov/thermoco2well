function [qF, time_now] = wellboreFormationHeat(w, tN, dt, injTime0)
% Heat exchange between the wellbore and the surrounding formation through
% tubing -> annulus -> casing -> cement, with transient radial conduction
% in the formation (Hasan & Kabir, 2002). Reused from the steady-state
% model thermoco2well_ss_mix.m.
%
% SYNOPSIS:
%   [qF, time_now] = wellboreFormationHeat(w, tN, dt, injTime0)
%
% PARAMETERS:
%   w        - MSW well structure. Heat-transfer parameters are read from
%              w.heat (set in the driver script): diameters d_ti, d_to,
%              d_ci, d_co, d_wb; conductivities k_t, k_a, k_c, k_cem, k_e;
%              formation rho_e, cp_e; Tsurf and tgrad of the undisturbed
%              geothermal profile. If w.heat is absent, qF = 0.
%   tN       - node temperatures for nodes 2:nn (may be AD)
%   dt       - current time step [s]
%   injTime0 - cumulative injection time at the START of the step [s]
%              (carried in wellSol.injTime; pass [] or omit-equivalent 0
%              if not yet initialized)
%
% RETURNS:
%   qF       - heat LOSS from the wellbore to the formation per node,
%              nodes 2:nn [W] (positive when the wellbore is warmer than
%              the formation). Same AD status as tN.
%   time_now - updated cumulative injection time [s]

    if isempty(injTime0)
        injTime0 = 0;
    end
    time_now = injTime0 + dt;

    if ~isfield(w, 'heat') || isempty(w.heat)
        qF = 0;
        return
    end

    ht = w.heat;

    % Overall heat transfer coefficient of the completion [W/(m*K)]:
    % series of radial conduction resistances tubing/annulus/casing/cement
    U = 1./(log(ht.d_to/ht.d_ti)/ht.k_t + log(ht.d_ci/ht.d_to)/ht.k_a + ...
            log(ht.d_co/ht.d_ci)/ht.k_c + log(ht.d_wb/ht.d_co)/ht.k_cem);

    % Hasan & Kabir dimensionless time and temperature for the transient
    % radial conduction in the formation
    td = time_now * ht.k_e / (ht.rho_e * ht.cp_e * (ht.d_wb/2)^2);
    if td < 1.5
        TD = 1.128*sqrt(td)*(1 - 0.3*sqrt(td));
    else
        TD = (0.4063 + 0.5*log(td))*(1 + 0.6/td);
    end

    % Combined wellbore/formation heat transfer coefficient [W/(m*K)]
    kHT = 2*pi*U*ht.k_e / (ht.k_e + 0.5*pi*U*TD);

    % Undisturbed formation temperature at the node depths
    Te = ht.Tsurf + w.nodes.depth(2:end) * ht.tgrad / 1000;

    % Wellbore length associated with each node (half of each adjacent
    % segment)
    nn_tot = numel(w.nodes.depth);
    topo = w.segments.topo;
    Lnode = accumarray([topo(:,1); topo(:,2)], ...
                       0.5*[w.segments.length; w.segments.length], ...
                       [nn_tot, 1]);

    % Heat loss to the formation [W]
    qF = kHT .* (tN - Te) .* Lnode(2:end);
end
