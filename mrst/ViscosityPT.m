classdef ViscosityPT < Viscosity
    % Viscosity that depends on both pressure and temperature
    % Extends standard Viscosity to pass temperature from model.t

    methods
        function mu = ViscosityPT(model, varargin)
            mu@Viscosity(model, varargin{:});
        end

        function mu_phase = evaluatePhaseViscosity(prop, model, state, name, p)
            % Override to pass temperature as second argument
            if isprop(model, 't') && all(isfinite(model.t))
                % Model has temperature field - pass it to fluid function
                mu_phase = prop.evaluateFluid(model, ['mu', name], p, model.t);
            else
                % Fall back to pressure-only (standard behavior)
                mu_phase = prop.evaluateFluid(model, ['mu', name], p);
            end
        end
    end
end
