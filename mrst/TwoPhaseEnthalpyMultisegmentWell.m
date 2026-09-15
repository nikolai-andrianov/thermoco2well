classdef TwoPhaseEnthalpyMultisegmentWell < TwoPhaseThermalMultisegmentWell
    % Thermal multisegment well with mixture ENTHALPY as the thermal
    % primary variable (suitable for CO2 phase transitions in the
    % wellbore).
    %
    % Extends TwoPhaseThermalMultisegmentWell with:
    %   * extra primary variable 'hN' (node mixture enthalpy, nodes 2:nn),
    %     stored in wellSol.h
    %   * energy conservation written in enthalpy plus a closure equation
    %     that defines the node temperature tN from (p, hN, composition)
    %   * heat exchange with the formation through tubing/annulus/casing/
    %     cement (parameters in W.heat), reused from thermoco2well_ss_mix
    %
    % The node temperature wellSol.t remains available for the reservoir
    % energy coupling in TwoPhaseWaterGasThermalModel.insertWellEquations.

    properties
        % Injection temperature (K) at node 1 — used as the wellhead
        % boundary condition in the enthalpy equations. Kept separate from
        % well.tsurf (geothermal surface temperature) so that the initial
        % wellbore temperature profile (tsurf + depth*tgrad/1000) can be
        % the true geothermal gradient while the injected-fluid boundary
        % condition remains at the actual injection temperature.
        t_inj
    end

    methods
        function well = TwoPhaseEnthalpyMultisegmentWell(W, t_surf, t_grad, t_inj_val, varargin)
            % t_surf   : geothermal surface temperature [K], used for the
            %            initial wellbore temperature profile in validateWellSol
            % t_grad   : geothermal gradient [K/km]
            % t_inj_val: (optional) injection temperature [K] at node 1;
            %            defaults to t_surf for backward compatibility
            well = well@TwoPhaseThermalMultisegmentWell(W, t_surf, t_grad, varargin{:});
            if nargin < 4 || isempty(t_inj_val)
                well.t_inj = t_surf;
            else
                well.t_inj = t_inj_val;
            end
        end

        function [weqs, ctrlEq, weqsMS, extraNames, qMass, qSurf, wellSol] = computeWellEquations(well, wellSol0, wellSol, resmodel, q_s, bh, packed, dt, iteration)
            % Node pressures for the well
            pN = packed.extravars{strcmpi(packed.extravars_names, 'pN')};
            % Node temperatures (algebraic, defined by the enthalpy closure)
            tN = packed.extravars{strcmpi(packed.extravars_names, 'tN')};
            % Node mixture enthalpies (thermal primary variable)
            hN = packed.extravars{strcmpi(packed.extravars_names, 'hN')};
            % Mass fractions for the phases
            wN = packed.extravars(strncmpi(packed.extravars_names, 'r', 1));
            % Mixture mass flux in segments
            vmS = packed.extravars{strcmpi(packed.extravars_names, 'vmix')};

            % Create struct with the reservoir quantities for the perforated cells
            resProps = struct();
            resProps.pressure = packed.pressure;
            resProps.mob = packed.mob;
            resProps.rho = packed.rho;
            resProps.dissolved = packed.dissolved;
            resProps.b = packed.rho;

            % Extract reservoir temperature at perforated cells (stored
            % temporarily during equation assembly by the reservoir model)
            wc = well.W.cells;
            if isfield(wellSol, 'currentResTemperature')
                T_res = wellSol.currentResTemperature;
                resProps.T = T_res(wc);
            else
                error('wellSol does not have currentResTemperature field!');
            end

            rhoS = resmodel.getSurfaceDensities();
            for i = 1:numel(resProps.b)
                den = rhoS(i);
                resProps.b{i} = resProps.b{i}./den;
            end

            % Setup all well equations (enthalpy formulation)
            [weqs, weqsMS, qSurf, wellSol, alpha_s, status, cstatus, qRes] = ...
                setupMSWellEquationsEnthalpy(well, resmodel, wellSol0, wellSol, q_s, bh, pN, wN, vmS, tN, hN, resProps, dt, iteration);

            extraNames = well.getExtraEquationNames(resmodel);
            qMass = qSurf;
            for i = 1:numel(qMass)
                % Mass source terms
                qMass{i} = qSurf{i}.*rhoS(i);
            end

            % Finally setup single well control equation
            ctrlEq = setupWellControlEquationsSingleWell(well, wellSol0, wellSol, bh, q_s, status, alpha_s, resmodel);

            % Update well properties which are not primary variables
            toDouble = @(x)cellfun(@value, x, 'UniformOutput', false);
            cq_sDb = cell2mat(toDouble(qSurf));

            wellSol.cqs     = cq_sDb;
            wellSol.cstatus = cstatus;
            wellSol.status  = status;
        end

        function [names, fromResModel] = getExtraPrimaryVariableNames(well, resmodel)
            % Parent adds 'tN'; append the enthalpy node variable 'hN'
            [names, fromResModel] = getExtraPrimaryVariableNames@TwoPhaseThermalMultisegmentWell(well, resmodel);
            names = [names, 'hN'];
            fromResModel = [fromResModel, false];
        end

        function [names, types] = getExtraEquationNames(well, resmodel)
            % Parent order: [phaseNodes..., pDropSeg, energyNode, segMassClosure]
            % Insert the enthalpy closure equation after energyNode:
            % [phaseNodes..., pDropSeg, energyNode, hClosureNode, segMassClosure]
            [names, types] = getExtraEquationNames@TwoPhaseThermalMultisegmentWell(well, resmodel);
            names = [names(1:end-1), 'hClosureNode', names(end)];
            if nargout > 1
                types = [types(1:end-1), 'node', types(end)];
            end
        end

        function counts = getVariableCounts(wm, fld)
            switch lower(fld)
                case {'hn', 'nodeenthalpy', 'enthalpy'}
                    % Same count as node pressure/temperature (nodes 2:nn)
                    counts = numel(wm.W.nodes.depth) - 1;
                otherwise
                    counts = getVariableCounts@TwoPhaseThermalMultisegmentWell(wm, fld);
            end
        end

        function [fn, index] = getVariableField(model, name, varargin)
            index = 1;
            switch lower(name)
                case {'hn', 'nodeenthalpy', 'enthalpy'}
                    fn = 'h';
                otherwise
                    [fn, index] = getVariableField@TwoPhaseThermalMultisegmentWell(model, name, varargin{:});
            end
        end

        function ws = updateWellSol(well, ws, variables, dx, resmodel)
            % Chop the thermal updates: large Newton overshoots in tN/hN
            % can leave the sampled (p,T) property tables (flat
            % extrapolation -> singular closure Jacobian)
            act = true(size(dx));
            for i = 1:numel(dx)
                switch variables{i}
                    case 'tN'
                        % NOTE: chop the update only - do NOT clamp the
                        % value to the table range. A hard clamp makes the
                        % system infeasible when the physical solution
                        % (e.g. JT cooling near the wellhead) approaches
                        % the table edge, and Newton then stagnates
                        % forever. If T leaves the table span, widen the
                        % sampled tables instead.
                        dv = well.limitUpdateAbsolute(dx{i}, 25);   % K
                        ws.t = ws.t + dv;
                        act(i) = false;
                    case 'hN'
                        dv = well.limitUpdateAbsolute(dx{i}, 1e5);  % J/kg
                        ws.h = ws.h + dv;
                        act(i) = false;
                end
            end
            ws = updateWellSol@TwoPhaseThermalMultisegmentWell(well, ws, variables(act), dx(act), resmodel);
        end

        function wellSol = validateWellSol(well, resmodel, wellSol, state)
            % Parent initializes nodePressure, nodeComp, segmentFlux, t, ...
            wellSol = validateWellSol@TwoPhaseThermalMultisegmentWell(well, resmodel, wellSol, state);

            % Initialize the node mixture enthalpy from (p, T, composition)
            if ~isfield(wellSol, 'h') || isempty(wellSol.h)
                f = resmodel.fluid;
                pN = wellSol.nodePressure;
                tn = wellSol.t;
                wellSol.h = wellSol.nodeComp(:,1).*f.hW(pN, tn) + ...
                            wellSol.nodeComp(:,2).*f.hG(pN, tn);
            end

            % Initialize the cumulative injection time used by the
            % transient formation heat conduction (Hasan & Kabir)
            if ~isfield(wellSol, 'injTime') || isempty(wellSol.injTime)
                wellSol.injTime = 0;
            end

            % CO2 vapor quality from the (p,h) flash (diagnostic; 1 =
            % vapor/supercritical, 0 = liquid, in between = two-phase).
            % Must exist before assembly: FacilityModel propagates
            % wellSol fields across the whole wellSol struct array.
            if ~isfield(wellSol, 'q_vap') || isempty(wellSol.q_vap)
                wellSol.q_vap = ones(numel(wellSol.nodePressure), 1);
            end
        end
    end
end
