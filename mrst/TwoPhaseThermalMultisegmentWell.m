classdef TwoPhaseThermalMultisegmentWell < MultisegmentWell
    % Adds an energy equation to TwoPhaseMultisegmentWell for two-phase water-gas systems
    % Overrides computeWellEquations, getVariableField, and validateWellSol 
    % to handle two-phase saturations correctly
    % Uses mass fractions as primary variables.
    % Gas phase properties calculated as function of both P & T. 

    properties
        % Surface temperature (K) for geothermal model
        tsurf
        % Geothermal gradient (deg°C/km)
        tgrad
    end    

    methods
        function well = TwoPhaseThermalMultisegmentWell(W, t_surf, t_grad, varargin)
            % Constructor - calls parent constructor
            well = well@MultisegmentWell(W, varargin{:});
            well.tsurf = t_surf;
            well.tgrad = t_grad;            
        end

        function [weqs, ctrlEq, weqsMS, extraNames, qMass, qSurf, wellSol] = computeWellEquations(well, wellSol0, wellSol, resmodel, q_s, bh, packed, dt, iteration)
            % Override the MultisegmentWell method to handle two-phase systems
            % Remove reference to dissolved to avoid indexing error

            % Node pressures for the well
            pN = packed.extravars{strcmpi(packed.extravars_names, 'pN')};
            % Extract node temperatures for thermal wellbore model
            tN = packed.extravars{strcmpi(packed.extravars_names, 'tN')};
            % Mass fraction for the phases
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

            % Extract reservoir temperature at perforated cells
            % Get perforated cell indices
            wc = well.W.cells;
            % Get temperature from reservoir model (stored temporarily during equation assembly)
            if isfield(wellSol, 'currentResTemperature')
                T_res = wellSol.currentResTemperature;
                resProps.T = T_res(wc);  % Temperature at perforated cells
            else
                error('wellSol does not have currentResTemperature field!');
            end
            rhoS = resmodel.getSurfaceDensities();
            for i = 1:numel(resProps.b)
                % We store both b-factors and the density. This is a bit
                % redundant, but it makes it easier to write equations both
                % in terms of mass and surface volumes.
                den = rhoS(i);
                resProps.b{i} = resProps.b{i}./den; 
            end
            
            % % setup all well equations using a customized analogue of
            % % setupMSWellEquationSingleWell() to handle two-phase thermal flows
            % [weqs, weqsMS, qSurf, wellSol, alpha_s, status, cstatus, qRes] = ...
            %     setupMSWellEquationsThermal(well, resmodel, wellSol0, wellSol, q_s, bh, pN, wN, vmS, tN, resProps, dt, iteration);

            % % DEBUG
            % [weqs, weqsMS, qSurf, wellSol, alpha_s, status, cstatus, qRes] = ...
            %     setupMSWellEquationsThermal_working_step_0(well, resmodel, wellSol0, wellSol, q_s, bh, pN, wN, vmS, tN, resProps, dt, iteration);  

            % % explodes temperature at the entrance to the reservoir
            % [weqs, weqsMS, qSurf, wellSol, alpha_s, status, cstatus, qRes] = ...
            %     setupMSWellEquationsThermal_exp1(well, resmodel, wellSol0, wellSol, q_s, bh, pN, wN, vmS, tN, resProps, dt, iteration);

            % [weqs, weqsMS, qSurf, wellSol, alpha_s, status, cstatus, qRes] = ...
            %     setupMSWellEquationsThermal_advection(well, resmodel, wellSol0, wellSol, q_s, bh, pN, wN, vmS, tN, resProps, dt, iteration);
            % 


            % Test 
            [weqs, weqsMS, qSurf, wellSol, alpha_s, status, cstatus, qRes] = ...
                setupMSWellEquationsThermal_exp2(well, resmodel, wellSol0, wellSol, q_s, bh, pN, wN, vmS, tN, resProps, dt, iteration);


            extraNames = well.getExtraEquationNames(resmodel);
            qMass = qSurf;
            for i = 1:numel(qMass)
                % Mass source terms
                qMass{i} = qSurf{i}.*rhoS(i);   % FIX
            end
            
            % finally setup single well control equation
            ctrlEq =  setupWellControlEquationsSingleWell(well, wellSol0, wellSol, bh, q_s, status, alpha_s, resmodel);
            
            % Update well properties which are not primary variables
            toDouble = @(x)cellfun(@value, x, 'UniformOutput', false);
            cq_sDb = cell2mat(toDouble(qSurf));
            
            wellSol.cqs     = cq_sDb;
            wellSol.cstatus = cstatus;
            wellSol.status  = status;
        end 

        function [names, fromResModel] = getExtraPrimaryVariableNames(well, resmodel)
            % Override to add temperature node variable 'tN' for thermal wellbore
            % Get base MSW primary variables (pN, rW/rG, vmix)
            [names, fromResModel] = getExtraPrimaryVariableNames@MultisegmentWell(well, resmodel);

            % Add temperature nodes as additional primary variable
            names = [names, 'tN'];
            fromResModel = [fromResModel, false];  % Temperature is from well, not reservoir
        end

        function [names, types] = getExtraEquationNames(well, resmodel)
            % CLAUDE: Override to add energy equation name for thermal wellbore
            % Get base MSW equation names (phase nodes, pressure drop, composition closure)
            [names, types] = getExtraEquationNames@MultisegmentWell(well, resmodel);

            % Add energy equation name
            % Insert before the last equation (composition closure)
            % Order: [phaseNodes, pDropSeg, energyNode, segMassClosure]
            names = [names(1:end-1), 'energyNode', names(end)];

            if nargout > 1
                types = [types(1:end-1), 'node', types(end)];
            end
        end

        function counts = getVariableCounts(wm, fld)
        % Override to specify that tN has nn-1 values (nodes 2:nn)
            switch lower(fld)
                case {'tn', 'nodetemperature', 'temperature'}
                    % Temperature has same count as node pressure (nn-1)
                    counts = numel(wm.W.nodes.depth) - 1;
                otherwise
                    % Use parent implementation for other variables
                    counts = getVariableCounts@MultisegmentWell(wm, fld);
            end
        end

        function [fn, index] = getVariableField(model, name, varargin)
            % Override the MultisegmentWell method to handle two-phase systems
            % Set max index to 2
            index = 1;
            switch(lower(name))
                case {'pn', 'nodepressure'}
                    fn = 'nodePressure';
                % CLAUDE: Add temperature variable mapping for thermal wellbore
                case {'tn', 'nodetemperature', 'temperature'}
                    fn = 't';
                    % Temperature stored for nodes 2:nn (consistent with nodePressure)
                    index = 1;
                case {'rw', 'watermassfraction'}
                    fn = 'nodeComp';
                    index = 1;
                case {'rg', 'gasmassfraction'}
                    fn = 'nodeComp';
                    index = 2;
                case {'vmix', 'segmentflux'}
                    fn = 'segmentFlux';
                    index = 1;
                otherwise
                    [fn, index] = getVariableField@SimpleWell(model, name, varargin{:});
            end
        end     

        function wellSol = validateWellSol(well, resmodel, wellSol, state)
            % Override the MultisegmentWell method to handle two-phase systems

            % Cumulative injection time for the transient formation heat
            % exchange (wellboreFormationHeat). Must be initialized HERE:
            % fields added in validateWellSol are propagated to the whole
            % wellSol struct array by FacilityModel.validateState, whereas
            % fields first created during equation assembly break the
            % wellSol(wellNo) = ws assignment in getWellContributions
            % ("dissimilar structures") when other wells lack them.
            if ~isfield(wellSol, 'injTime') || isempty(wellSol.injTime)
                wellSol.injTime = 0;
            end

            if isfield(wellSol, 'nodePressure') && ~isempty(wellSol.nodePressure)
                return
            end

            W = well.W;
            nn  = numel(W.nodes.depth);

            % Set initial node pressures equal to initial bhp
            wellSol.nodePressure = rldecode(wellSol.bhp, nn(:)-1);

            % For a water-filled injector, replace the uniform pressure
            % guess with a hydrostatic profile anchored at the reservoir
            % pressure of the first perforated cell. The uniform guess
            % puts the wellhead ~140 bar too high; the first-step
            % "settling" of that error bakes an artificial isenthalpic
            % (Joule-Thomson) cooling into the wellbore enthalpy and can
            % push node temperatures below the sampled-table range.
            if wellSol.sign > 0 && isfield(W, 'init') && strcmp(W.init, 'water')
                g_grav   = norm(gravity());
                rho_init = resmodel.fluid.rhoWS;
                p_anchor = state.pressure(W.cells(1));
                d_anchor = resmodel.G.cells.centroids(W.cells(1), 3);
                pn = p_anchor + rho_init*g_grav*(W.nodes.depth - d_anchor);
                wellSol.bhp = pn(1);
                wellSol.nodePressure = pn(2:end);
            end

            % Initialize volumetric rate field for segments
            ns = numel(well.W.segments.length);
            wellSol.volRate = zeros(ns, 1);

            % Initial temperature in the wellbore (nodes 2:nn only, consistent with nodePressure)
            wellSol.t = well.tsurf + W.nodes.depth(2:end) * well.tgrad / 1000;

            % Initialize energy scale factor (will be computed in well equations)
            wellSol.E_scale = 1.0;

            if wellSol.sign < 0 
                % Initialize the PRODUCER's node pressures, phase compositions, 
                % and rates using reservoir properties in perforated cells
                
                wc = W.cells;
                % get saturation and pressure from connecting cells
                sc = state.s(wc,:);
                pc = state.pressure(wc);
                % compute connecting cells props:
                %[krw, kro, krg] = resmodel.relPermWOG(sc(:,1), sc(:,2), sc(:,3), resmodel.fluid);
                [krw, krg] = resmodel.relPermWG(sc(:,1), sc(:,2), resmodel.fluid);
                muw = resmodel.fluid.muW(pc);
                bw = resmodel.fluid.bW(pc);
                mug = resmodel.fluid.muG(pc);
                bg = resmodel.fluid.bG(pc);
                
                % phase mobilities
                [mw, mg] = deal(krw./muw, krg./mug);

                % compute components weights for a unit volume rate  
                dens = resmodel.getSurfaceDensities();
                fwm = dens(1)*bw.*mw;   % FIX
                fgm = dens(2)*bg.*mg;   % FIX
                
                % devide by total to get component fractions in nodes
                % connected to reservoir grid cells
                nodemix = W.cell2node*bsxfun(@rdivide, [fwm, fgm], fwm + fgm) ;
       
                % set a small rate and compute a "plausible" mass conservative mixture rate
                % by solving least square problem 
                cq = -10*ones(numel(W.cells), 1)/day;
                cn = W.cell2node*cq;
                M = well.operators.C(:, 2:end);
                wellSol.segmentFlux =  -M*((M'*M)\cn(2:end));
                
                % set component mass fraction in undefined nodes equal to
                % average upstream node mass fractions
                nodemix_seg = -M*((M'*M)\nodemix(2:end,:));
                tp = W.segments.topo(:,2)-1;
                while any(sum(nodemix,2)==0)
                    nodemix(tp, :) = nodemix_seg;
                end
                nodemix = bsxfun(@rdivide, nodemix, sum(nodemix,2));
                nodemix = nodemix(2:end,:);
                
                wellSol.nodeComp = nodemix;
                % adjust total rates
                q_top = full(abs(well.operators.C(:,1)'*wellSol.segmentFlux));
                wellSol.qWs  = -q_top*nodemix(1,1)*dens(1); % FIX
                wellSol.qGs  = -q_top*nodemix(1,2)*dens(2); % FIX
            else
                % INJECTOR
                if strcmp(W.init, 'water') 
                    % Water-filled wellbore
                    wellSol.nodeComp = repmat([1, 0], nn-1, 1);
                    % Set the top node composition to injected gas (need
                    % for convergence)
                    wellSol.nodeComp(1, :) = W.compi;
                elseif strcmp(W.init, 'gas') 
                    % Gas-filled wellbore (all nodes have injection composition)                    
                    wellSol.nodeComp = repmat(W.compi, nn-1, 1);
                else
                    error('MSW initialization not defined!!')
                end

                % Initialize segment fluxes based on injection rate
                dens = resmodel.getSurfaceDensities();

                if strcmpi(W.type, 'rate')
                    % Rate-controlled injector: use specified rate
                    q_total = W.val;  % Total volumetric rate at surface conditions

                    % Distribute equally across perforations
                    cq = (q_total / numel(W.cells)) * ones(numel(W.cells), 1);
                else
                    % BHP-controlled injector: use small initial rate
                    cq = 10*ones(numel(W.cells), 1)/day;
                end

                % segmentFlux (vmix) is a MASS flux in this formulation:
                % convert the volumetric rate with the injection mixture
                % density. An inconsistent initial guess here is NOT just
                % cosmetic: it left an O(1e3) residual in the surface rate
                % equation, and Newton's first correction kicked bhp by
                % ~140 bar through the weakly-determined well-pressure
                % mode, driving (p, T) outside the sampled property tables.
                rho_mix_inj = W.compi(1)*dens(1) + W.compi(2)*dens(2);
                cq_mass = cq * rho_mix_inj;

                % Compute segment fluxes (mass conservative)
                cn = W.cell2node*cq_mass;
                M = well.operators.C(:, 2:end);
                wellSol.segmentFlux = -M*((M'*M)\cn(2:end));

                % Surface rates in VOLUMETRIC units, consistent with the
                % rate control equation sum(q_s) = W.val and the surface
                % coupling eqs{ph} = q_s*rho_s
                q_top = full(abs(well.operators.C(:,1)'*wellSol.segmentFlux)) / rho_mix_inj;
                wellSol.qWs = q_top * W.compi(1);
                wellSol.qGs = q_top * W.compi(2);


                % % Convert volumetric to mass flux
                % % Compute mixture density at injection composition
                % rho_mix_inj = W.compi(1)*dens(1) + W.compi(2)*dens(2);
                % cq_mass = cq * rho_mix_inj;  % [m³/s] * [kg/m³] = [kg/s]
                % 
                % % Compute segment fluxes (mass conservative)
                % cn = W.cell2node*cq_mass;  % Changed from cq to cq_mass
                % M = well.operators.C(:, 2:end);
                % wellSol.segmentFlux = -M*((M'*M)\cn(2:end));  % Now [kg/s]
                % 
                % % Compute surface rates based on injection composition
                % q_top = full(abs(well.operators.C(:,1)'*wellSol.segmentFlux));
                % % q_top is mass flux [kg/s], decompose by phase and convert to volumetric
                % wellSol.qWs = (q_top * W.compi(1)) / dens(1);  % [kg/s] / [kg/m³] = [m³/s]
                % wellSol.qGs = (q_top * W.compi(2)) / dens(2);
                % 

            end
        end
      
    end
end
