classdef TwoPhaseWaterGasThermalModel < TwoPhaseWaterGasModel
    % Two-phase gas and water thermal model for the reservoir
    properties
        % Choice of thermal primary variable. Possible values are 'temperature'
        % and 'enthalpy'. Default is 'temperature'. Note: Two-phase liquid-vapor
        % flow requires enthalpy formulation.
        thermalFormulation = 'temperature';

        % Temporary storage for current temperature field (used to pass to wells)
        currentTemperature = [];

        % Surface temperature for geothermal gradient (K)
        tsurf

        % Geothermal gradient (K/km)
        tgrad        

        % dynamicFlowTrans = false;
        % dynamicHeatTransRock = false;
        % dynamicHeatTransFluid = false;
    end
    
    % ============================================================================
    methods

        % ------------------------------------------------------------------------
        function model = TwoPhaseWaterGasThermalModel(G, rock, fluid, tsurf, tgrad, varargin)
        % Two-phase thermal model constructor
        %
        % SYNOPSIS:
        %   model = TwoPhaseWaterGasThermalModel(G, rock, fluid)
        %   model = TwoPhaseWaterGasThermalModel(G, rock, fluid, tsurf, tgrad)
        %   model = TwoPhaseWaterGasThermalModel(..., 'pn1', vn1, ...)
        %
        % REQUIRED PARAMETERS:
        %   G     - Grid structure
        %   rock  - Rock structure with thermal properties (lambdaR, CpR, rhoR)
        %   fluid - Fluid structure with thermal properties (lambdaF, Cp)
        %
        % OPTIONAL PARAMETERS:
        %   tsurf - Surface temperature (K). If not provided, uses NaN
        %   tgrad - Geothermal gradient (K/km). If not provided, uses NaN
        %
        % RETURNS:
        %   model - Initialized TwoPhaseWaterGasThermalModel instance
        
            % Handle optional arguments for temperature field
            if nargin < 5
              tgrad = nan;
            end
            if nargin < 4
              tsurf = nan;
            end
            
            % Validate that rock has required thermal properties
            assert(isfield(rock, 'lambdaR'), ...
              'Rock must have thermal conductivity (lambdaR). Use addMyThermalRockProps()');
            assert(isfield(rock, 'CpR'), ...
              'Rock must have heat capacity (CpR). Use addMyThermalRockProps()');
            assert(isfield(rock, 'rhoR'), ...
              'Rock must have density (rhoR). Use addMyThermalRockProps()');
            
            % Validate that fluid has required thermal properties
            assert(isfield(fluid, 'lambdaF'), ...
              'Fluid must have thermal conductivity (lambdaF). Use addMyThermalFluidProps()');

            % Call parent constructor
            model = model@TwoPhaseWaterGasModel(G, rock, fluid, tsurf, tgrad); 

            % Store surface temperature and geothermal gradient
            model.tsurf = tsurf;
            model.tgrad = tgrad;            

            % Set model name
            model.name  = 'GasWater_2ph_thermal';

            % Validate thermal formulation
            assert(any(strcmpi(model.thermalFormulation, {'temperature', 'enthalpy'})), ...
                ['TwoPhaseWaterGasThermalModel only supports ''temperature'' or ', ...
                '''enthalpy'' formulation. Current value: %s'], model.thermalFormulation);
            
            % Set output state functions to include thermal energy
            model.OutputStateFunctions = {'ComponentTotalMass', 'TotalThermalEnergy'};

            % Set up operators including heat transmissibilities
            model = model.setupOperators(G, rock);

        end


        function model = setupOperators(model, G, rock, varargin)
            % Set up operators including heat transmissibilities

            % Set rock and grid from model if not provided
            if nargin < 3, rock = model.rock; end
            if nargin < 2, G = model.G;       end

            % Call parent class to set up standard flow operators
            model = setupOperators@TwoPhaseWaterGasModel(model, G, rock, varargin{:});

            % Get pore volume and cell volumes
            pv  = model.operators.pv;
            vol = G.cells.volumes;

            % Store cell volumes in operators (needed for energy equation)
            model.operators.vol = vol;
            
            % Compute heat transmissibility for ROCK (conduction through solid)
            % lambdaR weighted by solid volume fraction
            lambdaR = rock.lambdaR .* (vol - pv) ./ vol;
            r_rock  = struct('perm', lambdaR);
            Thr     = getFaceTransmissibility(G, r_rock);
            
            % Store in operators (internal connections only)
            if numel(Thr) < G.faces.num
                Thr_all = zeros(G.faces.num, 1);
                Thr_all(model.operators.internalConn) = Thr;
                Thr = Thr_all;
            end
            model.operators.Thr     = Thr(model.operators.internalConn);
            model.operators.Thr_all = Thr;
            
            % Compute heat transmissibility for FLUID (conduction through pores)
            % lambdaF weighted by pore volume fraction
            lambdaF = repmat(model.fluid.lambdaF, G.cells.num, 1) .* pv ./ vol;
            r_fluid = struct('perm', lambdaF);
            Thf     = getFaceTransmissibility(G, r_fluid);
            
            % Store in operators
            if numel(Thf) < G.faces.num
                Thf_all = zeros(G.faces.num, 1);
                Thf_all(model.operators.internalConn) = Thf;
                Thf = Thf_all;
            end
            model.operators.Thf     = Thf(model.operators.internalConn);
            model.operators.Thf_all = Thf;
        
        end
        
        %-----------------------------------------------------------------%
        function model = validateModel(model, varargin)
        % Validate model to see if it is ready for simulation
        
            % % Check that we have a facility model
            % if isempty(model.FacilityModel) ...
            %         || ~isa(model.FacilityModel, 'GeothermalGenericFacilityModel')
            %     model.FacilityModel = GeothermalGenericFacilityModel(model);
            % end
            % % Set up components
            % if isempty(model.Components)
            %     names = model.getComponentNames();
            %     nc = numel(names);
            %     for i = 1:nc
            %         name        = names{i};
            %         molarMass   = model.compFluid.molarMass(i);
            %         diffusivity = model.compFluid.molecularDiffusivity(i);
            %         c = BrineComponent(name, molarMass, diffusivity, i);
            %         model.Components{i} = c;
            %     end
            % end
            % Call parent model validation
            model = validateModel@ReservoirModel(model, varargin{:});
            
        end        

        %-----------------------------------------------------------------%

        function [problem, state] = getEquations(model, state0, state, dt, drivingForces, varargin)
        % Get model equations including mass and energy conservation
        %
        % SYNOPSIS:
        %   [problem, state] = model.getEquations(state0, state, dt, drivingForces)
        %
        % DESCRIPTION:
        %   This function assembles the system of equations for two-phase thermal flow:
        %   1. Water mass conservation
        %   2. Gas (CO2) mass conservation
        %   3. Energy conservation (if model.thermal = true)
        %
        % PARAMETERS:
        %   model         - TwoPhaseWaterGasThermalModel instance
        %   state0        - State at previous time step
        %   state         - Current state
        %   dt            - Time step
        %   drivingForces - Struct with wells (W), boundary conditions (bc), sources (src)
        %
        % RETURNS:
        %   problem - LinearizedProblem for the nonlinear solver
        %   state   - Updated state with computed fluxes
            
        
            opt = struct('Verbose'     , mrstVerbose , ...
                       'reverseMode' , false       , ...
                       'resOnly'     , false       , ...
                       'iteration'   , -1          , ...
                       'stepOptions' , []); % compatibility only
            opt = merge_options(opt, varargin{:});
            
            W  = drivingForces.W;
            bc = drivingForces.bc;
            s  = model.operators;
            f  = model.fluid;
            G  = model.G;
            t  = model.t;  % Static temperature field (for isothermal density eval if needed)
            
            % Extract current and previous values of all variables to solve for
            [p, sG, wellSol] = model.getProps(state, 'pressure', 'sg', 'wellsol');
            [p0, sG0, wellSol0] = model.getProps(state0, 'pressure', 'sg', 'wellsol');
            
            % Extract temperature (thermal primary variable)
            switch model.thermalFormulation
                case 'temperature'
                    T = model.getProps(state, 'T');
                    T0 = model.getProps(state0, 'T');
                case 'enthalpy'
                    error('Enthalpy as primary variable not implemented!')
                    %[T, T0] = model.getProps(state, state0, 'enthalpy');
            end

            
            [wellVars, wellVarNames, wellMap] = model.FacilityModel.getAllPrimaryVariables(wellSol);
            
            % ------------------ Initialization of independent variables ------------------
            
            if ~opt.resOnly
                if ~opt.reverseMode
                    % Forward mode: initialize AD variables                
                    [p, sG, T, wellVars{:}] = model.AutoDiffBackend.initVariablesAD(p, sG, T, wellVars{:});                
                else
                    % Reverse mode (for adjoint)
                    wellVars0 = model.FacilityModel.getAllPrimaryVariables(wellSol0);                
                    [p0, sG0, T0, wellVars0{:}] = model.AutoDiffBackend.initVariablesAD(p0, sG0, T0, wellVars0{:});                
                end
            end
            
            % Update state with AD variables (needed for state functions) NA: these 2 lines not present in isothermal equationsWaterGas from co2lab-ve
            state = model.setProp(state, 'pressure', p);
            state = model.setProp(state, 's', {1-sG, sG});

            switch model.thermalFormulation
                case 'temperature'
                    state = model.setProp(state, 'T', T);
                case 'enthalpy'
                    state = model.setProp(state, 'enthalpy', T);  % T is actually h
            end

            
            % ----------------------------------------------------------------------------
            
            % Check for p-dependent tran mult:
            trMult = 1;
            if isfield(f, 'tranMultR'), trMult = f.tranMultR(p); end
            
            % Check for p-dependent porv mult:
            pvMult = 1; pvMult0 = 1;
            if isfield(f, 'pvMultR')
              pvMult  = f.pvMultR(p);
              pvMult0 = f.pvMultR(p0);
            end
            transMult = 1;
            if isfield(f, 'transMult')
              transMult = f.transMult(p);
            end
            
            trans = s.T .* transMult;
            
            % Check for capillary pressure
            pcWG = 0;
            if isfield(f, 'pcWG')
              pcWG = f.pcWG(sG);
            end
            
            % ----------------------------------------------------------------------------
            % Evaluate fluid properties at current temperature
            sW = 1-sG;
            sW0 = 1-sG0;
            
            % Get current temperature for property evaluation
            switch model.thermalFormulation
                case 'temperature'
                    Tcur = T;
                case 'enthalpy'
                    % Would need flash to get T from h - for now assume T available
                    Tcur = model.getProps(state, 'T');
            end
            T0cur = T0;  % Previous temperature

            % Relative permeability            
            [krW, krG] = model.evaluateRelPerm({sW, sG});
            
            % Computing densities, mobilities and upstream indices
            [bW, mobW, fluxW, vW, upcw] = compMFlux(p       , Tcur, f.bW, f.muW, f.rhoWS, trMult, krW, s, trans, model);
            [bG, mobG, fluxG, vG, upcg] = compMFlux(p + pcWG, Tcur, f.bG, f.muG, f.rhoGS, trMult, krG, s, trans, model);
            
            % Properties at previous time step
            % (evaluate capillary pressure at the PREVIOUS saturation;
            % using the current pcWG with p0 mixes time levels)
            pcWG0 = 0;
            if isfield(f, 'pcWG')
                pcWG0 = f.pcWG(sG0);
            end
            bW0 = f.bW(p0, T0cur);
            bG0 = f.bG(p0 + pcWG0, T0cur);
            
            % --------------------------- Continuity equations ---------------------------
            
            % Water mass conservation
            eqs{1} = (s.pv/dt) .* (pvMult .* bW .* sW - pvMult0 .* bW0 .* sW0) + s.Div(fluxW);
            
            % Gas mass conservation
            eqs{2} = (s.pv/dt) .* (pvMult .* bG .* sG - pvMult0 .* bG0 .* sG0) + s.Div(fluxG);
            
            names = {'water', 'gas'};
            types = {'cell' , 'cell'};
            
            % ---------------------------- Energy equation -------------------------------
            

            % % Compute energy equation using FlowDiscretization if available
            % if ~isempty(model.FlowDiscretization) && isa(model.FlowDiscretization, 'GeothermalFlowDiscretization')
            %     % Use the GeothermalFlowDiscretization energy equation
            %     [eeqs, eflux, enames, etypes] = model.FlowDiscretization.energyConservationEquation(model, state, state0, dt);
            % 
            %     % Assemble with divergence
            %     eeqs{1} = s.AccDiv(eeqs{1}, eflux{1});
            % 
            %     % Add radiogenic heat if present
            %     if any(model.radiogenicHeatFluxDensity > 0)
            %         qh = model.radiogenicHeatFluxDensity * s.vol;
            %         eeqs{1} = eeqs{1} - qh;
            %     end
            % 
            %     % Add to equations
            %     eqs   = [eqs  , eeqs  ];
            %     names = [names, enames];
            %     types = [types, etypes];
            % else
            %     % Manual energy equation (if FlowDiscretization not available)
            %     warning('GeothermalFlowDiscretization not found. Using simplified energy equation.');
            % 
            %     % Get thermal energy
            %     energy  = model.getProp(state , 'TotalThermalEnergy');
            %     energy0 = model.getProp(state0, 'TotalThermalEnergy');
            % 
            %     % Get heat flux
            %     flux = model.getProp(state, 'HeatFlux');
            % 
            %     % Assemble energy equation
            %     eqs{end+1} = (energy - energy0)/dt + s.Div(flux);
            %     names{end+1} = 'energy';
            %     types{end+1} = 'cell';
            % end

            % Fluid properties at current state
            bW = f.bW(p, T);
            bG = f.bG(p, T);
            rhoW = bW .* f.rhoWS;
            rhoG = bG .* f.rhoGS;

            % Fluid properties at previous state
            bW0 = f.bW(p0, T0);
            bG0 = f.bG(p0, T0);
            rhoW0 = bW0 .* f.rhoWS;
            rhoG0 = bG0 .* f.rhoGS;

            % ---------------------------- Energy equation (full) ----------------------------
            % d/dt[ pv*(sW*rhoW*uW + sG*rhoG*uG) + (V-pv)*rhoR*CpR*T ]
            %   + div( (rhoW*hW)_up * vW + (rhoG*hG)_up * vG )
            %   + div( -(Thr + Thf) * grad(T) ) = q_heat(wells)
            %
            % uX/hX are taken from the fluid object. If sampled (p,T) tables
            % were added (addSampledFluidProperties with enthalpy enabled),
            % they contain the real-gas departure enthalpy, so Joule-Thomson
            % cooling on expansion is captured. Otherwise the Cp*T-based
            % fallbacks from addMyThermalFluidProps are used (no JT).

            % Water heat capacity, used for equation scaling below
            CpW = f.CpW();

            % Rock volumetric heat capacity per cell [J/K] (solid fraction)
            rockHeat = (s.vol - s.pv) .* model.rock.rhoR .* model.rock.CpR;

            % Phase specific internal energies and enthalpies [J/kg]
            % (gas evaluated at p; capillary shift pcWG neglected here)
            uWc  = f.uW(p , T );    uGc  = f.uG(p , T );
            uW0c = f.uW(p0, T0cur); uG0c = f.uG(p0, T0cur);
            hWc  = f.hW(p , T );    hGc  = f.hG(p , T );

            % 1. Accumulation: fluid internal energy + rock thermal energy
            energy  = s.pv .* pvMult  .* (sW  .* rhoW  .* uWc  + sG  .* rhoG  .* uGc ) + rockHeat .* T;
            energy0 = s.pv .* pvMult0 .* (sW0 .* rhoW0 .* uW0c + sG0 .* rhoG0 .* uG0c) + rockHeat .* T0;
            accumulation_E = (energy - energy0) / dt;

            % 2. Advection: enthalpy carried by the phase mass fluxes,
            %    upwinded with the same direction as the mass equations
            qAdv_W = s.faceUpstr(upcw, rhoW .* hWc) .* vW;
            qAdv_G = s.faceUpstr(upcg, rhoG .* hGc) .* vG;

            advection_E = s.Div(qAdv_W + qAdv_G);

            % 3. Conduction: Fourier flux through rock and fluid, using the
            %    heat transmissibilities precomputed in setupOperators.
            %    (Thf is based on full lambdaF; saturation-weighting neglected.)
            conduction_E = s.Div(-(s.Thr + s.Thf) .* s.Grad(T));

            % Energy equation: accumulation + advection + conduction = 0
            energyEq = accumulation_E + advection_E + conduction_E;

            % Scale the energy equation so its Jacobian rows are comparable in
            % magnitude to the mass conservation rows. The energy accumulation is
            % O(rhoW * CpW * T) larger than the mass accumulation; dividing by
            % rhoWS * CpW * T_ref normalises this. Must match the well-source
            % scaling in insertWellEquations.
            T_ref_energy = 300;  % K
            E_scale_res  = f.rhoWS * CpW * T_ref_energy;
            energyEq     = energyEq / E_scale_res;

            eqs{end+1} = energyEq;
            names{end+1} = 'energy';
            types{end+1} = 'cell';

            
            % ---------------------------- Boundary conditions ----------------------------
            
            if model.outputFluxes
              state = model.storeFluxes(state, vW, [], vG);
            end
            if model.extraStateOutput
              state = model.storebfactors(state, bW, [], bG);
              state = model.storeMobilities(state, mobW, [], mobG);
              state = model.storeUpstreamIndices(state, upcw, [], upcg);
            end
            
            % Prepare for boundary conditions and sources
            rho = {bW.*f.rhoWS, bG.*f.rhoGS};
            mob = {mobW, mobG};
            sat = {sW, sG};
            
            % Default BC saturation if not specified
            if ~isempty(bc) && isempty(bc.sat)
              bc.sat = repmat([1 0], numel(bc.face), 1);
            end
            
            % Add boundary conditions and sources to mass equations
            pressures = {p, p + pcWG};
            [eqs, state] = addBoundaryConditionsAndSources(model, eqs, names, types, state, ...
                                                         pressures, sat, mob, rho, ...
                                                         {}, {}, ...
                                                         drivingForces);
            
            % ------------------------------ Well equations ------------------------------

            % Store reservoir temperature temporarily in well solution(s), in 
            % order to be used in well equations
            for i = 1:numel(wellSol)
                wellSol(i).currentResTemperature = T;
            end

            % Set up primary variables for the problem
            primaryVars = {'pressure', 'sG', model.thermalFormulation, wellVarNames{:}};

            [eqs, names, types, state.wellSol] = model.insertWellEquations(eqs, names, types, ...
                                                                          wellSol0, wellSol, ...
                                                                          wellVars, wellMap, ...
                                                                          p, mob, rho, ...
                                                                          {}, {}, ...
                                                                          dt, opt);
            
            % ----------------------------------------------------------------------------
            
            problem = LinearizedProblem(eqs, types, names, primaryVars, state, dt);
        
        end

        %-----------------------------------------------------------------%

        function [fn, index] = getVariableField(model, name, varargin)
        % Map known variable by name to field and column index in state
        %
        % SYNOPSIS:
        %   [fn, index] = model.getVariableField('T')
        %   [fn, index] = model.getVariableField('enthalpy')
        %
        % PARAMETERS:
        %   name - String with variable name
        %
        % RETURNS:
        %   fn    - Field name in state structure
        %   index - Index/column (typically ':' for all)
        
            % Handle thermal variables
            switch lower(name)
                case {'temperature', 't'}
                    % Temperature field
                    fn    = 'T';
                    index = ':';
                case {'enthalpy', 'h'}
                    % Enthalpy field (for enthalpy formulation)
                    fn    = 'enthalpy';
                    index = ':';
                otherwise
                    % Let parent class handle pressure, saturation, etc.
                    [fn, index] = getVariableField@TwoPhaseWaterGasModel(model, name, varargin{:});
            end        
        end


        function [eqs, names, types, wellSol, src] = insertWellEquations(model, eqs, names, ...
                                                     types, wellSol0, wellSol, ...
                                                     wellVars, wellMap, ...
                                                     p, mob, rho, ...
                                                     dissolved, components, ...
                                                     dt, opt)
        % Override to add energy sources from wells to reservoir energy equation
        %
        % Standard insertWellEquations only adds mass sources to phase equations.
        % For thermal models, we also need to add heat flux from wells to the
        % energy equation.

            % Call parent to handle standard mass coupling
            [eqs, names, types, wellSol, src] = insertWellEquations@ReservoirModel(model, eqs, names, ...
                                                     types, wellSol0, wellSol, ...
                                                     wellVars, wellMap, ...
                                                     p, mob, rho, ...
                                                     dissolved, components, ...
                                                     dt, opt);

            %return
            
            % Add energy source from wells
            eix = strcmpi(names, 'energy');
            if ~any(eix)
                % No energy equation present
                return
            end

            % Get well source cells (perforated cells)
            wc = src.sourceCells;
            if isempty(wc)
                return
            end

            % Compute enthalpy flux from wells
            % For each phase: q_phase * h_phase
            % Use upwinding: if injecting (q>0), use well enthalpy; if producing (q<0), use reservoir enthalpy

            f = model.fluid;
            nph = nnz(model.getActivePhases);

            actWellIx = model.FacilityModel.getIndicesOfActiveWells(wellSol);

            % Total mass source per perforation (sum over phases). The src
            % vectors are concatenations over ALL active wells, in the order
            % given by actWellIx.
            q_total_mass = 0;
            for ph = 1:nph
                q_total_mass = q_total_mass + src.phaseMass{ph};
            end

            % Perforation index offsets for each active well, so that each
            % well only applies the heat source of its OWN perforations.
            % (Previously the full source vector was applied once per well,
            % double-counting it when more than one well is active.)
            nPerf = arrayfun(@(ix) numel(model.FacilityModel.WellModels{ix}.W.cells), ...
                             actWellIx(:));
            perfOffset = [0; cumsum(nPerf(1:end-1))];

            for n = 1:numel(actWellIx)

                i = actWellIx(n);

                % This well's structure and perforation slice
                Wn   = model.FacilityModel.WellModels{i}.W;
                pix  = perfOffset(n) + (1:numel(Wn.cells))';
                wc_n = wc(pix);
                q_n  = q_total_mass(pix);
    
                % Get reservoir temperature at well cells
                % Temperature is stored in p cell array (passed as argument)
                % For thermal models, state should have been passed with temperature
                % We need to extract from wellSol which has currentResTemperature
                if isfield(wellSol(i), 'currentResTemperature') && ~isempty(wellSol(i).currentResTemperature)
                    T_res = wellSol(i).currentResTemperature;
                    T_res_wc = T_res(wc_n);
                else
                    warning('Reservoir temperature not available for well energy coupling. Using geothermal gradient.');
                    % Fallback: use geothermal gradient
                    depths = model.G.cells.centroids(wc_n, 3);
                    T_res_wc = model.tsurf + depths * model.tgrad / 1000;
                end
    
                % Get well temperature at perforations (from wellbore model)
                try
                    if isfield(wellSol(i), 't') && ~isempty(wellSol(i).t)
                        % MSW: temperature at nodes (nodes 2:nn stored in wellSol(i).t)
                        % Map this well's perforation cells to well nodes

                        % cell2node is a sparse matrix: [num_nodes x num_perfs]
                        % cell2node(node_idx, perf_idx) = 1 if perforation connects to node
                        cell2node = Wn.cell2node;

                        % For each of this well's cells, find its node temperature
                        T_well_wc = zeros(numel(wc_n), 1);
                        for k = 1:numel(wc_n)
                            % Find which perforation index corresponds to this reservoir cell
                            % Wn.cells contains reservoir cell indices for each perforation
                            perf_idx = find(Wn.cells == wc_n(k));

                            if isempty(perf_idx)
                                % Cell not found in well perforations - use tsurf
                                T_well_wc(k) = model.tsurf;
                            else
                                % Find which node this perforation connects to
                                [node_idx, ~] = find(cell2node(:, perf_idx));
                                if isempty(node_idx) || node_idx == 1
                                    % Node 1 (surface) or not found - use tsurf
                                    T_well_wc(k) = model.tsurf;
                                else
                                    % Nodes 2:nn - get from wellSol(i).t
                                    T_well_wc(k) = wellSol(i).t(node_idx - 1);
                                end
                            end
                        end
                    else
                        % Simple well: assume injection at surface temperature
                        T_well_wc = model.tsurf * ones(numel(wc_n), 1);
                    end
                catch ME
                    warning('Failed to extract well temperature: %s. Using surface temperature.', ME.message);
                    T_well_wc = model.tsurf * ones(numel(wc_n), 1);
                end
    
                % Enthalpy-based perforation coupling, consistent with the full
                % energy equation in getEquations: each phase carries h_ph(p,T)
                % per unit mass. Upwinding: injecting perforations carry the
                % well temperature, producing perforations the reservoir
                % temperature (kept as AD so the Jacobian sees the coupling).
                % Enthalpy is evaluated at the reservoir cell pressure, i.e.
                % the perforation throttling is treated as isenthalpic; with
                % sampled h(p,T) tables this captures Joule-Thomson cooling
                % of the injected CO2.
                %
                % Sign: positive q = injection -> heat enters reservoir ->
                % subtract from residual (eq = accum + div - source = 0).
                injecting = value(q_n) > 0;
                T_upwind_wc = injecting .* T_well_wc + (~injecting) .* T_res_wc;

                f_ins = model.fluid;
                p_wc  = p(wc_n);  % reservoir pressure at this well's cells
                hPerf = {f_ins.hW(p_wc, T_upwind_wc), ...
                         f_ins.hG(p_wc, T_upwind_wc)};  % active phase order: W, G

                qHeat_well = 0;
                for ph = 1:nph
                    qHeat_well = qHeat_well + ...
                        src.phaseMass{ph}(pix) .* hPerf{ph};
                end

                % Scale with same factor as reservoir energy equation (getEquations)
                T_ref_energy_ins = 300;  % K  (must match value in getEquations)
                E_scale_res_ins  = f_ins.rhoWS * f_ins.CpW() * T_ref_energy_ins;
                qHeat_well = qHeat_well / E_scale_res_ins;

                eqs{eix}(wc_n) = eqs{eix}(wc_n) - qHeat_well;
    
            end

        end


        % ------------------------------------------------------------------------
        
        function [state, report] = updateState(model, state, problem, dx, drivingForces)
            
           [state, report] = updateState@ThreePhaseBlackOilModel(model, state, problem, dx, ...
                                                        drivingForces);
           sG = model.getProp(state, 'sG');
           if isfield(state, 'sGmax')
               state.sGmax = max(state.sGmax, sG);
           else
               state.sGmax = sG;
           end
           state.sGmax = min(1,state.sGmax);
           state.sGmax = max(0,state.sGmax);
        end
    end
    
end


% ========================= LOCAL HELPER FUNCTIONS =======================%

function [b, mob, fluxS, fluxR, upc] = compMFlux(p, T, bfun, mufun, rhoS, trMult, kr, s, trans, model)
% Compute mass flux for a phase accounting for temperature-dependent properties
%
% PARAMETERS:
%   p       - Pressure (cell array with AD)
%   T       - Temperature (cell array with AD)
%   bfun    - Formation volume factor function: b = bfun(p, T)
%   mufun   - Viscosity function: mu = mufun(p, T)
%   rhoS    - Surface density (constant)
%   trMult  - Transmissibility multiplier
%   kr      - Relative permeability
%   s       - Operators structure
%   trans   - Transmissibility
%   model   - Model instance
%
% RETURNS:
%   b     - Formation volume factor
%   mob   - Mobility
%   fluxS - Surface volumetric flux
%   fluxR - Reservoir volumetric flux
%   upc   - Upstream indices

% Evaluate formation volume factor and viscosity at (p, T)
b   = bfun(p, T);
mu  = mufun(p, T);

mob = trMult .* kr ./ mu;

% Face density (for gravity term)
rhoFace = s.faceAvg(b * rhoS);

% Pressure gradient with gravity
dp  = s.Grad(p) - rhoFace .* model.getGravityGradient();

% Upwind direction
upc = (value(dp) <= 0);

% Reservoir volumetric flux
fluxR = -s.faceUpstr(upc, mob) .* trans .* dp;

% Surface volumetric flux
fluxS = s.faceUpstr(upc, b) .* fluxR;

end



