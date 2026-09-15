function res = invertMixtureEnthalpy(fluid, p, h, xW, xG, Tlo, Thi, Cp_ext, computeDerivs)
% Two-phase (p,h) flash for the wellbore water/CO2 mixture.
%
% Solves the mixture enthalpy relation
%     xW*hW(p,T) + xG*hG(p,T) = h
% for the temperature, with a PROPER TWO-PHASE treatment of the CO2 phase
% inside the vapor dome. A wellbore node at p < Pc whose CO2-part enthalpy
% lies between the bubble- and dew-point enthalpies is physically a
% two-phase (liquid+vapor) CO2 node; no single-phase rhoG(p,T) table
% evaluation is meaningful there (rho jumps ~195 <-> ~880 kg/m^3 across
% the saturation line and Newton chatters on the discontinuity).
%
% Two-phase treatment:
%   * Tsat(p) from the Span & Wagner (1996) vapor-pressure equation
%     (co2lab's CO2VaporPressure), inverted by vectorized bisection.
%   * Liquid/vapor CO2 properties sampled from the (p,T) tables just
%     below/above the saturation line: hL = hG(p, Tsat-epsT),
%     hV = hG(p, Tsat+epsT), with epsT = 0.75 K. The offset clears the
%     bilinear smearing of the table discontinuity, which spans about
%     dT_grid + dp_grid/(dpsat/dT) ~ 0.18 + 0.31/1.1 ~ 0.5 K for the
%     800x800 tables on [4,150] degC x [1,250] bar.
%   * Vapor quality from the lever rule on the CO2 part of the mixture
%     enthalpy: q = (h - hL_mix)/(hV_mix - hL_mix), where
%     h*_mix = xW*hW(p,Tsat) + xG*h*_CO2.
%   * Two-phase CO2 density from harmonic (volume-additive) mixing,
%     rhoG = 1/((1-q)/rhoL + q/rhoV). This is the physically correct
%     rho(h): both v = (1-q)*vL + q*vV and h = (1-q)*hL + q*hV are
%     linear in q, so 1/rho is linear in h through the dome.
%     Viscosity uses McAdams mixing, 1/mu = (1-q)/muL + q/muV.
%   * The returned temperature ramps LINEARLY from Tsat-epsT (q=0) to
%     Tsat+epsT (q=1) through the dome, so T(h) is continuous with both
%     single-phase branches and STRICTLY increasing in h everywhere:
%     the closure tN - T(p,h,x) = 0 never loses rank and Newton cannot
%     chatter on the phase transition.
%
% Outside the dome the temperature is found by vectorized bisection on
% the monotone G(T) = xW*hW + xG*hG, with linear continuation of slope
% xW*CpW + xG*Cp_ext outside the sampled table span [Tlo, Thi] (the
% tables extrapolate flat, which would make the closure singular), and
% rhoG/muG are the table values at the (clamped) single-phase T.
%
% KNOWN LIMITATION: the dome treatment needs epsT of table room on the
% liquid side, so it only covers Tsat in [Tlo+epsT, Tc], i.e. pressures
% in ~[psat(Tlo+epsT), Pc] = [39.9, 73.8] bar for the 4 degC table
% floor. In the sliver p in [psat(Tlo), psat(Tlo+epsT)] ~ [38.8, 39.9]
% bar a MID-DOME enthalpy still hits the smeared table ramp (seam in
% rhoG/T along p). This is off the physical trajectory - at those
% pressures the wellbore CO2 is superheated vapor (h > dew enthalpy)
% because the boundary feeds vapor until bhp > psat(t_inj) ~ 43.5 bar -
% but if it ever bites, regenerate the tables with T_min ~ -5 degC and
% lower Tlo accordingly.
%
% All derivatives (d/dh, d/dp, d/dxW, d/dxG of T, rhoG, muG) are central
% finite differences OF THE FULL FLASH, so the kinks at the dome
% boundaries are averaged over the stencil. The caller uses them to
% build first-order (exact at the evaluation point) AD linearizations.
%
% PARAMETERS:
%   fluid    - fluid object with hW, hG, rhoG, muG (all (p,T)) and CpW()
%   p, h     - node pressure [Pa] and mixture enthalpy [J/kg] (plain values)
%   xW, xG   - phase mass fractions (plain values)
%   Tlo, Thi - temperature bounds of the sampled tables [K]
%   Cp_ext   - gas heat capacity for the linear continuation [J/(kg K)]
%   computeDerivs - optional (default true); pass false when only the
%              values are needed (e.g. previous-timestep properties)
%
% RETURNS: struct res with fields
%   T, q, rhoG, muG  - temperature [K], CO2 vapor quality [-] (0 = liquid,
%                      1 = vapor/supercritical), effective CO2-phase
%                      density [kg/m^3] and viscosity [Pa s]
%   dTdh, dTdp, dTdxW, dTdxG          \
%   drhoGdh, drhoGdp, drhoGdxW, drhoGdxG > only if computeDerivs
%   dmuGdh, dmuGdp, dmuGdxW, dmuGdxG  /

    if nargin < 9
        computeDerivs = true;
    end

    epsT = 0.75;  % [K] table sampling offset from the saturation line

    [res.T, res.q, res.rhoG, res.muG] = ...
        flashPH(fluid, p, h, xW, xG, Tlo, Thi, Cp_ext, epsT);

    if ~computeDerivs
        return;
    end

    % Central finite differences of the full flash. Steps are small
    % against the physical scales (dome width ~2e5 J/kg, table cell
    % ~3e4 Pa) but large enough to average over table-cell noise.
    dh = 5e2;    % [J/kg]
    dp = 2e3;    % [Pa]
    dx = 1e-4;   % [-]

    [T1, ~, r1, m1] = flashPH(fluid, p, h + dh, xW, xG, Tlo, Thi, Cp_ext, epsT);
    [T2, ~, r2, m2] = flashPH(fluid, p, h - dh, xW, xG, Tlo, Thi, Cp_ext, epsT);
    res.dTdh    = (T1 - T2)/(2*dh);
    res.drhoGdh = (r1 - r2)/(2*dh);
    res.dmuGdh  = (m1 - m2)/(2*dh);

    [T1, ~, r1, m1] = flashPH(fluid, p + dp, h, xW, xG, Tlo, Thi, Cp_ext, epsT);
    [T2, ~, r2, m2] = flashPH(fluid, p - dp, h, xW, xG, Tlo, Thi, Cp_ext, epsT);
    res.dTdp    = (T1 - T2)/(2*dp);
    res.drhoGdp = (r1 - r2)/(2*dp);
    res.dmuGdp  = (m1 - m2)/(2*dp);

    [T1, ~, r1, m1] = flashPH(fluid, p, h, xW + dx, xG, Tlo, Thi, Cp_ext, epsT);
    [T2, ~, r2, m2] = flashPH(fluid, p, h, xW - dx, xG, Tlo, Thi, Cp_ext, epsT);
    res.dTdxW    = (T1 - T2)/(2*dx);
    res.drhoGdxW = (r1 - r2)/(2*dx);
    res.dmuGdxW  = (m1 - m2)/(2*dx);

    [T1, ~, r1, m1] = flashPH(fluid, p, h, xW, xG + dx, Tlo, Thi, Cp_ext, epsT);
    [T2, ~, r2, m2] = flashPH(fluid, p, h, xW, xG - dx, Tlo, Thi, Cp_ext, epsT);
    res.dTdxG    = (T1 - T2)/(2*dx);
    res.drhoGdxG = (r1 - r2)/(2*dx);
    res.dmuGdxG  = (m1 - m2)/(2*dx);

    % The closure tN - T(p,h,x) = 0 must keep a strictly positive
    % h-sensitivity (T is monotone in h by construction; this guards
    % against FD cancellation in degenerate table cells)
    res.dTdh = max(res.dTdh, 1e-9);
end

% -------------------------------------------------------------------------

function [T, q, rhoG, muG] = flashPH(fluid, p, h, xW, xG, Tlo, Thi, Cp_ext, epsT)
% Core flash on plain values (vectorized over the nodes)

    n = numel(h);
    G = @(T) xW.*fluid.hW(p, T) + xG.*fluid.hG(p, T);

    TloV = repmat(Tlo, n, 1);
    ThiV = repmat(Thi, n, 1);
    glo = G(TloV);
    ghi = G(ThiV);

    % Linear continuation slope outside the table span
    slope_ext = xW.*fluid.CpW() + xG.*Cp_ext;
    below = h <= glo;
    above = h >= ghi;

    % Single-phase: vectorized bisection on the monotone G(T) (45
    % halvings of a ~145 K bracket resolve T to ~4e-12 K)
    Tl = TloV;
    Tu = ThiV;
    for k = 1:45
        Tm = 0.5*(Tl + Tu);
        up = G(Tm) < h;
        Tl(up)  = Tm(up);
        Tu(~up) = Tm(~up);
    end
    T = 0.5*(Tl + Tu);

    % Out-of-range points: linear continuation
    T(below) = Tlo + (h(below) - glo(below))./slope_ext(below);
    T(above) = Thi + (h(above) - ghi(above))./slope_ext(above);

    % Default (single-phase) CO2 properties at the clamped temperature
    Tcl  = max(min(T, ThiV), TloV);
    rhoG = fluid.rhoG(p, Tcl);
    muG  = fluid.muG(p, Tcl);
    q    = ones(n, 1);   % vapor/supercritical by default

    % ---- Two-phase CO2 dome ----
    [Tsat, hasDome] = satTempInTable(p, Tlo, Thi, epsT);
    cand = hasDome & (xG > 1e-8);
    if any(cand)
        ic  = find(cand);
        pc  = p(ic);
        Ts  = Tsat(ic);
        % Mixture enthalpies at the dome boundaries = G(Tsat -/+ epsT)
        % EXACTLY (water sampled at the same temperatures as the CO2
        % branches), so the dome branch joins the single-phase bisection
        % branch continuously at both edges. The water sensible-heat
        % contribution across the 2*epsT ramp (~xW*CpW*1.5 K) is
        % negligible against the CO2 latent heat in the lever rule.
        hLm = xW(ic).*fluid.hW(pc, Ts - epsT) + xG(ic).*fluid.hG(pc, Ts - epsT);
        hVm = xW(ic).*fluid.hW(pc, Ts + epsT) + xG(ic).*fluid.hG(pc, Ts + epsT);
        qd  = (h(ic) - hLm)./max(hVm - hLm, 1e-3);

        % Liquid side of the dome
        q(ic(qd <= 0)) = 0;

        % Inside the dome: lever rule, harmonic density, McAdams viscosity
        in = (qd > 0) & (qd < 1);
        id = ic(in);
        if ~isempty(id)
            qi   = qd(in);
            Tsi  = Ts(in);
            rhoL = fluid.rhoG(p(id), Tsi - epsT);
            rhoV = fluid.rhoG(p(id), Tsi + epsT);
            muL  = fluid.muG(p(id), Tsi - epsT);
            muV  = fluid.muG(p(id), Tsi + epsT);
            T(id)    = Tsi - epsT + 2*epsT*qi;  % monotone ramp through dome
            q(id)    = qi;
            rhoG(id) = 1./((1 - qi)./rhoL + qi./rhoV);
            muG(id)  = 1./((1 - qi)./muL  + qi./muV);
        end
    end
end

% -------------------------------------------------------------------------

function [Tsat, hasDome] = satTempInTable(p, Tlo, Thi, epsT)
% Invert the Span-Wagner vapor-pressure curve for Tsat(p), restricted to
% the part of the saturation line that lies inside the sampled table
% span with epsT of room on both sides (needed to sample the liquid and
% vapor branches). Outside that pressure window no dome treatment is
% possible (or needed): for p < psat(Tlo+epsT) the CO2 is vapor over the
% whole table T-range, for p > Pc it is supercritical.

    Tc_co2 = 304.1282;            % [K] CO2 critical temperature
    Tmin = Tlo + epsT;
    Tmax = min(Tc_co2 - 1e-3, Thi - epsT);

    Tsat    = nan(size(p));
    hasDome = false(size(p));
    if Tmin >= Tmax
        return;
    end

    pmin = CO2VaporPressure(Tmin);
    pmax = CO2VaporPressure(Tmax);
    hasDome = (p > pmin) & (p < pmax);
    if ~any(hasDome)
        return;
    end

    pd = p(hasDome);
    Tl = repmat(Tmin, size(pd));
    Tu = repmat(Tmax, size(pd));
    for k = 1:40
        Tm = 0.5*(Tl + Tu);
        up = CO2VaporPressure(Tm) < pd;
        Tl(up)  = Tm(up);
        Tu(~up) = Tm(~up);
    end
    Tsat(hasDome) = 0.5*(Tl + Tu);
end
