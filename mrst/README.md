# THERMOCO2WELL MRST classes

MATLAB/MRST source developed in the THERMOCO2WELL project for thermal
CO2-injection well simulation: a two-phase (water/CO2) reservoir model with
pressure-temperature-dependent fluid properties, coupled to a multisegment
wellbore model that tracks enthalpy along the well (Joule-Thomson cooling,
phase transitions, heat exchange with the formation).

`stenlille_ecmor.m` is the runnable demo: a synthetic Cartesian model of the
Stenlille structure with a thermal multisegment injector and a
pressure-relief well, as presented at ECMOR 2026.

## Requirements

- [MRST](https://www.sintef.no/projectweb/mrst/) (tested with MRST 2025b)
  with these modules on the path: `ad-core`, `ad-props`, `co2lab-common`,
  `ad-blackoil`.
- MATLAB (no additional toolboxes beyond what MRST itself requires).

## Running

1. Install MRST and make sure `startup.m` has been run so `mrstModule` and
   `mrstPath` are on the MATLAB path.
2. Copy the files in this folder onto the MATLAB path (or `addpath` this
   folder directly).
3. Run `stenlille_ecmor.m`.

On first run, `addSampledFluidProperties` (a stock `co2lab-common`
function) samples CO2/water density, viscosity and enthalpy tables over the
pressure-temperature range used by the model; this is slow the first time
and cached afterwards.

## Contents

| File | Role |
|---|---|
| `stenlille_ecmor.m` | Demo driver / entry point |
| `addMyThermalRockProps.m` | Adds rock thermal properties (heat capacity, conductivity, density, tortuosity) |
| `addMyThermalFluidProps.m` | Adds fluid thermal properties (heat capacity, conductivity) |
| `TwoPhaseWaterGasThermalModel.m` | Reservoir model (extends MRST's `TwoPhaseWaterGasModel`) |
| `ShrinkageFactorsPT.m` | P-T-dependent shrinkage factors state function |
| `ViscosityPT.m` | P-T-dependent viscosity state function |
| `TwoPhaseThermalMultisegmentWell.m` | Multisegment well with temperature as a passive scalar (extends MRST's `MultisegmentWell`) |
| `TwoPhaseEnthalpyMultisegmentWell.m` | Multisegment well with enthalpy as the primary wellbore variable, including formation heat exchange (extends the above) |
| `setupMSWellEquationsEnthalpy.m` | Wellbore enthalpy balance equations |
| `invertMixtureEnthalpy.m` | Inverts mixture enthalpy to recover wellbore temperature/phase state |
| `wellboreFormationHeat.m` | Heat exchange between the wellbore and the surrounding formation |
| `wellboreFlow.m` | Wellbore friction/flow model |
| `rampupTimestepsExtended.m` | Timestep ramp-up schedule helper |
