classdef ShrinkageFactorsPT < ShrinkageFactors
    % Shrinkage factors that depend on both pressure and temperature
    % Extends standard ShrinkageFactors to pass temperature from model.t

    methods
        function b = ShrinkageFactorsPT(model, varargin)
            b@ShrinkageFactors(model, varargin{:});
        end

        function b_phase = evaluatePhaseShrinkageFactor(prop, model, state, name, p)
            % Override to pass temperature as second argument
            if isprop(model, 't') && all(isfinite(model.t))
                % Model has temperature field - pass it to fluid function
                b_phase = prop.evaluateFluid(model, ['b', name], p, model.t);
            else
                % Fall back to pressure-only (standard behavior)
                b_phase = prop.evaluateFluid(model, ['b', name], p);
            end
        end
    end
end
