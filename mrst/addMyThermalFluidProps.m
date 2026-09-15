function fluid = addMyThermalFluidProps(fluid, varargin)
% Add thermal properties to an existing fluid structure
% Inspired by modules\geothermal\utils\addThermalFluidProps.m
% Density and viscosity as functions of (p, T) already added via addSampledFluidProperties
%
% SYNOPSIS:
%  fluid = addThermalFluidProps(fluid,'pn1', pv1, ...);
%  fluid = addThermalFluidProps(fluid,'pn1', pv1, 'useEOS', true, 'brine', true, ...);
%
% PARAMETERS:
%   fluid   - fluid structure created with initSimpleADIFluid (or other).
%
%   cp      - fluid heat capacity in J kg-1 K-1. typically 4.2e3. Used for
%             the evaluation of the internal energy and enthalpy.
%
%   lambdaF - fluid heat conductivity in W m-1 K-1. typically 0.6.
%
%   useEOS  - logical. By default the density/viscosity formulation
%              of Spivey is used.
%
%   brine   - logical. Used for the EOS and p,T,c dependency of properties
%             if salt is present or not.
%
%   dNaCl   - salt molecular diffusivity in m2s-1.
% 
% 
%   rho     - density at reservoir condition. Can be given as an handle 
%             function.
% 
%   useBFactor - logical. Used if we want bW definition factor instead 
%                of rhoW 
% 
% RETURNS:
%   fluid - updated fluid structure containing the following functions
%           and properties.
%             * bX(p,T,c)  - inverse formation volume factor
%             * muX(p,T,c) - viscosity functions (constant)
%             * uW(p,T,c)  - internal energy
%             * hW(p,T,c)  - enthalpy
%             * lambdaF    - fluid conductivity
%             * dNaCl      - Salt molecular diffusivity
%
%
% SEE ALSO:
%
% 'initSimpleADIFluid', 'initSimpleThermalADIFluid'


    Watt = joule/second;
    opt = struct('Cp'     , 4.2*joule/(Kelvin*gram), ...
                 'lambdaF', 0.6*Watt/(meter*Kelvin), ...
                 'useEOS' , false                  , ...
                 'rho'    , fluid.rhoWS            , ...
                 'cT'     , []                     , ...
                 'TRef'   , (273.15 + 20)*Kelvin   , ...
                 'cX'     , []                     );
    opt = merge_options(opt, varargin{:});

    % Set thermal conductivity
    fluid.lambdaF = opt.lambdaF;

    % Get phase names
    fNames = fieldnames(fluid);
    phases = '';
    for fNo = 1:numel(fNames)
        fn = fNames{fNo};
        if strcmpi(fn(1:2), 'mu')
            phases = [phases, fn(3)];
        end
    end   
    nPh = numel(phases);

    % Set specific heat capacity, internal energy and enthalpy.
    % Do NOT overwrite uX/hX if they already exist: sampled h(p,T)/u(p,T)
    % tables from addSampledFluidProperties include real-gas departure
    % effects (Joule-Thomson) and take precedence over the Cp*T fallback.
    names = upper(phases);
    Cp    = opt.Cp;
    for phNo = 1:nPh
        n = names(phNo);
        fluid.(['Cp', n]) = @(varargin) Cp(phNo);
        if ~isfield(fluid, ['u', n])
            fluid.(['u', n]) = @(varargin) computeInternalEnergy(fluid, n, varargin{:});
        end
        if ~isfield(fluid, ['h', n])
            fluid.(['h', n]) = @(varargin) computeEnthalpy(fluid, n, varargin{:});
        end
    end
end


%-------------------------------------------------------------------------%
function u = computeInternalEnergy(fluid, phase, varargin)
    Cp = feval(fluid.(['Cp', phase]), varargin{:});
    T  = varargin{2};
    u  = Cp*T;
end

%-------------------------------------------------------------------------%
function h = computeEnthalpy(fluid, phase, varargin)
    rho = feval(fluid.(['rho', phase]), varargin{:});
    u   = feval(fluid.(['u', phase]), varargin{:});
    p   = varargin{1};
    h   = u + p./rho;
end