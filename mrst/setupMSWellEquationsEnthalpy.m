function [eqs, eqsMS, cq_s, wellSol, mix_s, status, cstatus, cq_r] = setupMSWellEquationsEnthalpy(wm, model, wellSol0, wellSol, q_s, bhp, pN, alpha, vmix, tN, hN, resProps, dt, iteration)
% Setup well residual equations for multi-segmented wells with thermal
% effects, using mixture ENTHALPY as the thermal primary variable.
%
% Based on setupMSWellEquationsThermal_exp2.m, with the following changes:
%
% 1. Energy conservation is written in terms of the node mixture enthalpy
%    hN (nodes 2:nn). The accumulation uses the internal energy
%    u = h - p/rho, the advection upstreams the node enthalpy. Enthalpy is
%    smooth and monotone across the CO2 vapor dome, so the phase
%    transition gas <-> liquid does not destroy Newton convergence the way
%    a temperature-primary formulation does. The conserved quantity is the
%    TOTAL specific energy h + phi with phi = -g*depth (gravitational
%    work: descending fluid warms by g*dz/Cp, ~+5.7 K over 1580 m of
%    liquid CO2); hN itself remains thermodynamic enthalpy.
%
% 2. Temperature tN remains an unknown but becomes algebraic: the closure
%    tN - T(p, hN, composition) = 0 defines it, where T comes from the
%    two-phase (p,h) flash invertMixtureEnthalpy. Inside the CO2 vapor
%    dome T ramps linearly (Tsat-epsT -> Tsat+epsT) with the vapor
%    quality, so the closure is strictly monotone in hN everywhere.
%
% 2b. TWO-PHASE CO2 TREATMENT: a node at p < Pc with CO2-part enthalpy
%    between the bubble/dew values is physically two-phase liquid+vapor
%    CO2 (the wellhead sits at 35-45 bar ~ psat(8 degC) during
%    unloading). The flash returns the vapor quality and the effective
%    CO2-phase density/viscosity (harmonic/McAdams two-phase mixing),
%    which replace the discontinuous single-phase rhoG(p,T)/muG(p,T)
%    table lookups in the node mixture density, hydrostatic head and
%    friction. The boundary (injected) gas enthalpy hG(bhp, t_inj) -
%    a step function of bhp at psat(t_inj) - is smoothed over a
%    +/- 1.5 bar pressure window (smoothGasBoundaryEnthalpy below).
%
% 3. Heat exchange with the surrounding formation (tubing -> annulus ->
%    casing -> cement -> formation), reused from the steady-state code
%    thermoco2well_ss_mix.m (Hasan & Kabir, 2002):
%      U   = 1/( ln(dto/dti)/kt + ln(dci/dto)/ka + ln(dco/dci)/kc + ln(dwb/dco)/kcem )
%      tD  = t*ke/(rho_e*cp_e*rwb^2),  TD = Hasan-Kabir approximation
%      k   = 2*pi*U*ke/(ke + 0.5*pi*U*TD)        [W/(m*K)]
%      q'  = k*(T - Te)                          [W/m]
%    Parameters are taken from the struct wm.W.heat (set in the driver
%    script). The cumulative injection time for tD is carried in
%    wellSol.injTime.
%
% 4. The advected enthalpy of the TOP segment explicitly carries the
%    injection enthalpy h(bhp, t_inj) when flow is downward. (The generic
%    segmentUpstr operator maps the node-1 upstream value to node 2, which
%    previously locked the top of the well to node 2's initial state.)
%
% 5. The node mixture density is computed consistently from the mass
%    fractions and the LOCAL phase densities (harmonic mixing):
%    rhom = 1/(xW/rhoW(p,T) + xG/rhoG(p,T)).
%
% RETURNS (same interface as setupMSWellEquationsThermal_exp2, one extra
% equation in eqsMS):
%   eqsMS - { mass_W, mass_G, pDrop, energy(h), hClosure(T), compClosure }

    % Get operators
    op = wm.operators;
    w = wm.W;

    % Properties for perforated reservoir cells
    m = resProps.mob;
    b = resProps.b;
    pr = resProps.pressure;

    % Placeholders for the equations:
    % mass(numPh) + pressure + energy + enthalpy closure + composition closure
    numPh = numel(b);
    eqs   = cell(1, numPh);
    eqsMS = cell(1, numPh + 4);

    if numPh ~= 2
        error('setupMSWellEquationsEnthalpy: only two-phase (WG) implemented!');
    end

    % Use surface densities as weighting
    rho_s = model.getSurfaceDensities();

    fluid = model.fluid;

    % Boundary (node 1) temperature: use wm.t_inj (injection temperature)
    % rather than wm.tsurf (geothermal surface temperature). The two differ
    % when the well is initialized with the true geothermal gradient: the
    % injected-fluid boundary enthalpy must reflect the actual injection
    % temperature so that the CO2 phase (gas vs liquid, psat(T)) is
    % evaluated correctly. For a well starting at the surface, depth(1)=0
    % so t_node1 = wm.t_inj.
    t_node1 = wm.t_inj + w.nodes.depth(1) * wm.tgrad / 1000;

    % Sampled-table temperature span (with a 0.5 K margin) and the gas
    % heat capacity used for linear continuation outside it. The tables
    % extrapolate FLAT outside their span (dh/dT = drho/dT = 0), which
    % makes equations singular - density/viscosity evaluations are clamped
    % to the span, and the enthalpy inversion (invertMixtureEnthalpy)
    % continues h(T) linearly beyond it.
    T_lo = 277.65;   % 0.5 K inside the sampled span [4, 150] degC
    T_hi = 422.65;
    Cp_ext = 2.0e3;  % J/(kg K) continuation slope
    clampT = @(T) min(max(T, T_lo), T_hi);

    % Top-node (boundary) phase MASS fractions from the surface rates
    qm_top = cell(1, numPh);
    qm_tot = 0;
    for ph = 1:numPh
        qm_top{ph} = abs(q_s{ph}) * rho_s(ph);
        qm_tot = qm_tot + qm_top{ph};
    end
    x_top = cell(1, numPh);
    for ph = 1:numPh
        x_top{ph} = qm_top{ph} ./ (qm_tot + 1e-30);
    end

    % ---------------- Two-phase (p,h) CO2 flash at the nodes ----------------
    % Boundary (node 1) mixture enthalpy at (bhp, t_inj). The gas part
    % hG(p, t_inj) is a step function of pressure at psat(t_inj) (~43.5
    % bar for 8 degC): when the wellhead pressure rises through the
    % saturation line during unloading, the injected CO2 condenses and
    % its enthalpy drops by the latent heat. The step is smoothed over a
    % +/- 1.5 bar window and linearized in bhp so Newton can walk through.
    [hGb, dhGbdp] = smoothGasBoundaryEnthalpy(fluid, value(bhp), t_node1);
    hG_bnd = hGb + dhGbdp.*(bhp - value(bhp));
    h_bnd  = x_top{1}.*fluid.hW(bhp, t_node1) + x_top{2}.*hG_bnd;

    % Flash (p, h, composition) -> T, vapor quality and effective
    % CO2-phase density/viscosity (two-phase mixing inside the vapor
    % dome), evaluated on values and reconstructed to first order in the
    % AD variables. This makes the phase transition representable: a
    % node between the bubble/dew enthalpies is physically TWO-PHASE
    % CO2, where no single-phase rhoG(p,T) lookup is meaningful.
    p_all  = [bhp; pN];
    h_all  = [h_bnd; hN];
    xW_all = [x_top{1}; alpha{1}];
    xG_all = [x_top{2}; alpha{2}];
    fl = invertMixtureEnthalpy(fluid, value(p_all), value(h_all), ...
                               value(xW_all), value(xG_all), T_lo, T_hi, Cp_ext);
    dH  = h_all  - value(h_all);
    dP  = p_all  - value(p_all);
    dXW = xW_all - value(xW_all);
    dXG = xG_all - value(xG_all);
    T_fl     = fl.T    + fl.dTdh   .*dH + fl.dTdp   .*dP + fl.dTdxW   .*dXW + fl.dTdxG   .*dXG;
    rhoG_eff = fl.rhoG + fl.drhoGdh.*dH + fl.drhoGdp.*dP + fl.drhoGdxW.*dXW + fl.drhoGdxG.*dXG;
    muG_eff  = fl.muG  + fl.dmuGdh .*dH + fl.dmuGdp .*dP + fl.dmuGdxW .*dXW + fl.dmuGdxG .*dXG;

    % Node mixture properties at the current state. The water properties
    % use the AD variable tN (clamped to the table span); the CO2-phase
    % density/viscosity come from the flash above.
    t_all = [t_node1; clampT(tN)];
    [mix_s, rhom, mum] = getNodeMixEnth(fluid, bhp, pN, alpha, x_top, rho_s, t_all, rhoG_eff, muG_eff);

    % Previous time step (plain values; flash values only, no derivatives)
    ws0 = wellSol0;
    alpha0 = {ws0.nodeComp(:,1), ws0.nodeComp(:,2)};
    q_s0 = {ws0.qWs, ws0.qGs};
    qm_top0 = {abs(q_s0{1})*rho_s(1), abs(q_s0{2})*rho_s(2)};
    qm_tot0 = qm_top0{1} + qm_top0{2};
    x_top0 = {qm_top0{1}./(qm_tot0 + 1e-30), qm_top0{2}./(qm_tot0 + 1e-30)};
    t0_all = [t_node1; ws0.t];
    hGb0 = smoothGasBoundaryEnthalpy(fluid, ws0.bhp, t_node1);
    h_bnd0 = x_top0{1}.*fluid.hW(ws0.bhp, t_node1) + x_top0{2}.*hGb0;
    fl0 = invertMixtureEnthalpy(fluid, [ws0.bhp; ws0.nodePressure], ...
                                [h_bnd0; ws0.h], [x_top0{1}; alpha0{1}], ...
                                [x_top0{2}; alpha0{2}], T_lo, T_hi, Cp_ext, false);
    [~, rhom0, ~] = getNodeMixEnth(fluid, ws0.bhp, ws0.nodePressure, alpha0, x_top0, rho_s, t0_all, fl0.rhoG, fl0.muG);

    % Pressure drawdown <0 for injection, >0 for production
    drawdown  = pr - (w.cell2node'*[bhp; pN]);
    injInx    = (drawdown < 0); % current injecting connections

    % Connections phase volume rates
    cq = cell(1, numPh);
    Tw = w.WI;

    allowCrossflow = wm.allowCrossflow;
    if ~allowCrossflow
        Tw(injInx) = 0;
    end

    % Use well index to estimate phase volume rates at res conditions
    for ph = 1:numPh
        cq{ph} = -Tw.*m{ph}.*drawdown;
    end

    % Connections phase volume rates at standard conditions
    cq_s = cell(1, numPh);
    for ph = 1:numPh
        cq_s{ph} = b{ph}.*cq{ph};
    end

    % Redefine the phase split for injecting connections using the
    % wellbore mixture composition (totMob*fraction); important for
    % convergence
    if allowCrossflow && any(injInx)
        cq_s_tot = cq_s{1}(injInx);
        for ph = 2:numPh
            cq_s_tot = cq_s_tot + cq_s{ph}(injInx);
        end
        for ph = 1:numPh
            cq_s{ph}(injInx) = cq_s_tot.*(w.cell2node(:, injInx)'*mix_s{ph});
        end

        cq_tot = cq{1}(injInx);
        for ph = 2:numPh
            cq_tot = cq_tot + cq{ph}(injInx);
        end
        for ph = 1:numPh
            cq{ph}(injInx) = cq_tot.*(w.cell2node(:, injInx)'*mix_s{ph});
        end
    end

    vols = w.nodes.vol;

    % Upwind flags for the segments (positive vmix = flow from topo(:,1)
    % to topo(:,2), i.e. downward for a top-to-bottom topology)
    up = value(vmix) >= 0;

    % Pressure drop relation quantities
    ddz = op.grad(w.nodes.depth);
    rhoSeg = op.aver(rhom);
    muSeg  = op.segmentUpstr(up, mum(2:end));
    dph = norm(gravity())*rhoSeg.*ddz;

    % ------------------- Phase mass conservation for nodes -------------------
    for ph = 1:numPh
        % Divergence of the phase mass flux (mixture flux times upstreamed
        % mass fraction) plus the mass leaving through the perforations
        ec = op.div(op.segmentUpstr(up, alpha{ph}).*vmix) + w.cell2node*cq_s{ph}*rho_s(ph);

        % For all nodes except the 1st one, add mass accumulation
        ec(2:end) = ec(2:end) + (alpha{ph}.*rhom(2:end) - alpha0{ph}.*rhom0(2:end)).*vols(2:end)/dt;

        % Surface-rate coupling: q_s is the SURFACE volumetric rate (the
        % quantity the rate control pins to W.val), converted to mass with
        % the SURFACE density rho_s
        eqs{ph} = q_s{ph}*rho_s(ph) - sum(ec);

        % Mass conservation equations for MSW nodes
        eqsMS{ph} = ec(2:end);
    end

    % ------------------- Energy conservation (enthalpy form) -------------------

    p0_all = [ws0.bhp; ws0.nodePressure];

    % Gravitational potential per node, phi = -g*depth. The equation
    % conserves TOTAL specific energy h + phi (kinetic energy is
    % negligible): descending fluid converts potential energy into
    % enthalpy, g*dz/Cp ~ +5.7 K over a 1580 m liquid-CO2 column.
    % Without this term a steady adiabatic column keeps h constant with
    % depth (pure isenthalpic descent) and arrives ~6 K too cold at the
    % completions. NOTE: hN, the closure and the flash stay THERMODYNAMIC
    % enthalpy; phi enters the conservation terms only, and must appear
    % consistently in accumulation, advection AND perforation flux, or a
    % steady column would not reproduce h + phi = const.
    phi_all = -norm(gravity()) * w.nodes.depth;

    % Internal energy u = h - p/rho at nodes 2:nn
    uN  = hN - p_all(2:end)./rhom(2:end);
    uN0 = ws0.h - p0_all(2:end)./rhom0(2:end);

    % 1. Accumulation of total energy rho*(u + phi)
    accumulation_E = (rhom(2:end).*(uN  + phi_all(2:end)) - ...
                      rhom0(2:end).*(uN0 + phi_all(2:end))).*vols(2:end)/dt;

    % 2. Advection: mixture mass flux carries the upstreamed node TOTAL
    %    specific energy h + phi
    % [vmix] = [kg/s]
    qAdv = op.segmentUpstr(up, hN + phi_all(2:end)).*vmix;

    % Boundary fix for the TOP segment: when flow is downward, the
    % advected enthalpy is that of the injected fluid at (bhp, t_inj) -
    % h_bnd computed above, smoothed through the saturation line.
    % (The generic upstream operator would substitute node 2's enthalpy.)
    if up(1)
        qAdv(1) = (h_bnd + phi_all(1)).*vmix(1);
    end

    advection_E = op.div(qAdv);

    % 3. Perforation enthalpy exchange. Positive total mass flux = out of
    %    the wellbore (injection), carrying the WELLBORE total energy;
    %    negative = production, carrying the reservoir total energy
    %    (phi at the perforated node depth on both branches).
    q_perf_mass = cq_s{1}*rho_s(1) + cq_s{2}*rho_s(2);

    % Wellbore mixture total energy at the perforated nodes
    h_well_perf = w.cell2node'*[h_bnd + phi_all(1); hN + phi_all(2:end)];

    % Reservoir mixture total energy carried by the per-phase produced mass
    phi_perf = w.cell2node'*phi_all;
    p_res = resProps.pressure;
    t_res = resProps.T;
    hW_res = fluid.hW(p_res, t_res);
    hG_res = fluid.hG(p_res, t_res);
    qPerf_prod = cq_s{1}*rho_s(1).*(hW_res + phi_perf) + cq_s{2}*rho_s(2).*(hG_res + phi_perf);

    perfInj = (value(drawdown) < 0);
    qPerfAdv = perfInj.*(q_perf_mass.*h_well_perf) + (~perfInj).*qPerf_prod;
    qPerfNodes = w.cell2node*qPerfAdv;

    % 4. Heat exchange with the formation through tubing/annulus/casing/
    %    cement (Hasan & Kabir, parameters in w.heat); the cumulative
    %    injection time for the transient formation conduction is carried
    %    in wellSol.injTime
    if isfield(ws0, 'injTime')
        injTime0 = ws0.injTime;
    else
        injTime0 = 0;
    end
    [qFormation, time_now] = wellboreFormationHeat(w, tN, dt, injTime0);
    wellSol.injTime = time_now;

    % Energy equation for nodes 2:nn (node 1 is the boundary; its
    % divergence row is discarded)
    eEnergy = accumulation_E + advection_E(2:end) + qPerfNodes(2:end) + qFormation;

    % Temporarily ignore reservoir heat transfer
    %eEnergy = accumulation_E + advection_E(2:end) + qPerfNodes(2:end);

    % Scale to "kelvin" units: divide by (mass rate scale)*(Cp scale) so
    % the residual reads as an equivalent temperature imbalance and the
    % Jacobian rows stay O(1). The mass-rate scale is the larger of the
    % node storage rate and the actual segment throughput; do NOT use the
    % q_s well variables here - their initial guess can be wildly off,
    % which previously inflated the scale by ~1e3 and made the energy rows
    % numerically zero (RCOND ~ 1e-17).
    Cp_ref  = 4.2e3;  % J/(kg K)
    rho_ref = mean(rho_s);
    V_ref   = mean(vols(2:end));
    qm_scale = max([rho_ref*V_ref/dt; abs(value(vmix)); 1e-3]);
    E_scale = qm_scale * Cp_ref;
    wellSol.E_scale = value(E_scale);

    eqsMS{numPh + 2} = eEnergy / E_scale;

    % ------------------- Enthalpy closure (defines tN) -------------------
    % tN = T(p, h, composition) from the two-phase (p,h) flash above
    % (first-order AD reconstruction T_fl). Posing this closure directly
    % as h_mix(p,T) - hN = 0 made Newton CHATTER across the near-vertical
    % hG(p,T) ramp at the CO2 saturation line; the flashed T(p,h) ramps
    % linearly (Tsat-epsT -> Tsat+epsT) with the vapor quality inside
    % the dome, so it is strictly monotone in hN and the phase transition
    % is crossed smoothly. Residual units: kelvin.
    eqsMS{numPh + 3} = tN - T_fl(2:end);

    % ------------------- Pressure drop equation -------------------
    % Pressure drop is written 
    if ~isa(w.segments.flowModel, 'function_handle')
        eqsMS{numPh + 1} = (op.grad([bhp; pN]) - dph - wm.pressureDropModel(pN, vmix, alpha, rho_s, rhoSeg))/value(bhp);
    else
        % 1st term is a FD approximation to dp, 2nd and the 3rd are
        % multiplied by segment lengths
        eqsMS{numPh + 1} = (op.grad([bhp; pN]) - dph - w.segments.flowModel(vmix, rhoSeg, muSeg))/value(bhp);
    end

    % ------------------- Composition closure -------------------
    eqsMS{numPh + 4} = 1;
    for i = 1:numPh
        eqsMS{numPh + 4} = eqsMS{numPh + 4} - alpha{i};
    end

    % Update these if necessary
    [status, cstatus, cq_r] = deal(true, true(size(value(pr))), cellfun(@value, cq, 'UniformOutput', false));

    % Return mix_s (just values)
    mix_s = cell2mat(cellfun(@value, mix_s, 'UniformOutput', false));

    % Keep derived quantities in wellSol
    wellSol.t = value(tN);
    wellSol.h = value(hN);
    wellSol.q_vap = fl.q(2:end);   % CO2 vapor quality at the nodes
    wellSol.volRate = value(vmix./rhoSeg);
end

% -------------------------------------------------------------------------

function [y, rhom, mum] = getNodeMixEnth(fluid, bhp, pN, x, x_top, rho_s, t, rhoG_eff, muG_eff)
% Node mixture properties from phase MASS fractions, using local phase
% densities (consistent harmonic mixing):
%   rhom = 1/(xW/rhoW(p,T) + xG/rhoG_eff)
%   y_p  = x_p*rhom/rho_p           (local volume fractions, sum to 1)
%   mum  = sum(y_p*mu_p)
%
% The CO2-phase density/viscosity rhoG_eff/muG_eff come from the
% two-phase (p,h) flash (invertMixtureEnthalpy): single-phase table
% values outside the vapor dome, two-phase mixtures inside it. They are
% NOT looked up from the (p,T) tables here - that lookup is
% discontinuous at the saturation line.
%
% y (returned as mix_s) follows the surface-volume convention of the
% original code: volume fractions computed with the SURFACE densities,
% used for the crossflow phase split of surface-volume rates.
%
% PARAMETERS:
%   x        - phase mass fractions at nodes 2:nn (cell of nph)
%   x_top    - phase mass fractions at the top (boundary) node (cell of nph)
%   t        - temperature at ALL nodes (1:nn), used for the water phase
%   rhoG_eff - effective CO2-phase density at ALL nodes (from the flash)
%   muG_eff  - effective CO2-phase viscosity at ALL nodes (from the flash)

    nph = numel(x);

    % Full-node mass fractions (top node prepended)
    xa = cell(1, nph);
    for p = 1:nph
        xa{p} = [x_top{p}; x{p}];
    end

    p_all = [bhp; pN];

    % Local phase densities and viscosities (water from the smooth
    % (p,T) tables, CO2 from the flash)
    rho = cell(1, nph);
    mu  = cell(1, nph);
    rho{1} = fluid.rhoW(p_all, t);
    rho{2} = rhoG_eff;
    mu{1}  = fluid.muW(p_all, t);
    mu{2}  = muG_eff;

    % Harmonic (mass-consistent) mixture density
    invrho = xa{1}./rho{1};
    for p = 2:nph
        invrho = invrho + xa{p}./rho{p};
    end
    rhom = 1./invrho;

    % Local volume fractions and mixture viscosity
    mum = 0;
    for p = 1:nph
        yloc = xa{p}.*rhom./rho{p};
        mum = mum + yloc.*mu{p};
    end

    % Surface-volume fractions (for crossflow split of surface rates)
    ratio = cell(1, nph);
    sumr = 0;
    for p = 1:nph
        ratio{p} = xa{p}/rho_s(p);
        sumr = sumr + ratio{p};
    end
    y = cell(1, nph);
    for p = 1:nph
        y{p} = ratio{p}./sumr;
    end
end

% -------------------------------------------------------------------------

function [h, dhdp] = smoothGasBoundaryEnthalpy(fluid, p, T)
% Injected-gas enthalpy hG(p, T) at the fixed injection temperature,
% smoothed in PRESSURE across the CO2 saturation line. The sampled table
% value is a (grid-smeared, ~0.5 bar wide) step of size ~latent heat at
% psat(T): vapor above the line at low p, liquid below it at high p.
% Newton cannot cross such a step with bar-sized bhp updates, so the two
% branches are blended with a smoothstep over psat(T) +/- dpw:
%   h = (1-w)*hG(min(p, psat-dpw), T) + w*hG(max(p, psat+dpw), T)
% Inside the window the boundary fluid is effectively two-phase, which
% is also what the node flash sees for the same (p, h) - consistent.
%
% PARAMETERS:
%   p - pressure(s) [Pa], plain values
%   T - injection temperature [K], scalar
%
% RETURNS:
%   h    - smoothed gas enthalpy [J/kg]
%   dhdp - finite-difference slope for the AD linearization [J/(kg Pa)]

    Tc_co2 = 304.1282;   % [K] CO2 critical temperature
    dpfd   = 5e3;        % [Pa] FD step for the slope

    if T >= Tc_co2 - 0.5
        % Supercritical injection temperature: no saturation line
        blend = @(pp) fluid.hG(pp, T + 0*pp);
    else
        psat = CO2VaporPressure(T);
        dpw  = 1.5e5;    % [Pa] smoothing half-width
        blend = @(pp) blendH(fluid, pp, T, psat, dpw);
    end

    h    = blend(p);
    dhdp = (blend(p + dpfd) - blend(p - dpfd))/(2*dpfd);
end

function h = blendH(fluid, p, T, psat, dpw)
    Tv = T + 0*p;
    hv = fluid.hG(min(p, psat - dpw), Tv);   % vapor branch
    hl = fluid.hG(max(p, psat + dpw), Tv);   % liquid branch
    s  = min(max((p - (psat - dpw))/(2*dpw), 0), 1);
    w  = s.^2.*(3 - 2*s);                    % smoothstep weight
    h  = (1 - w).*hv + w.*hl;
end
