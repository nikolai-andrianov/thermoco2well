% The main Octave file for the backend simulation of a steady-state flow
% during injection of CO2 in an inlined well. 

% Read input from CSV and set up the simulation parameters
param = stenlille_pipeline_mix('input.csv');

% Run the simulation and write output to results.csv
thermoco2well_ss_mix(param);