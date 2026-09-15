# Call Octave to run the backend simulation of a steady-state flow
# during injection of CO2 in an inclined well.  

import os, sys, platform
import subprocess
from pathlib import Path

def run_backend(folder):

    converged = True

    # Set up the name of the executable, depending on the platform
    if platform.system() == 'Linux':
        exe = 'octave'
    elif platform.system() == 'Windows':
        exe = 'octave-cli.exe'
    else:
        raise Exception

    out_file = os.path.join(folder, "results.csv")

    # Remove the old results file
    if os.path.isfile(out_file):
        print('Removing the old ' + out_file)
        os.remove(out_file)
        
    # Run the backend simulation using octave 
    try:

        subprocess.run([exe, '-f', 'backend.m'], cwd=folder)

        # Stop if errors are found in the .out file
        if not os.path.isfile(out_file):
            #print(str(out_file) + ' is not available, stopping..')
            #sys.exit(1)
            return not converged

    except:
        # Flag that the error has occured
        Path(os.path.join(folder, 'RunTimeError.txt')).touch()
        return not converged
        
    # Return no errors
    return converged
        
        
if __name__ == "__main__":
    run_backend()