import dash
from dash import html, Input, Output, State, callback, dcc, DiskcacheManager, CeleryManager
import dash_ag_grid as dag
import dash_bootstrap_components as dbc
from dash.exceptions import PreventUpdate
import os, platform, shutil
import pandas as pd
from .backend.backend import run_backend

# Need to specify the run folder for the production system
if platform.system() == 'Linux':
    folder = '/var/www/FlaskDash/pages/project/backend'
elif platform.system() == 'Windows':
    folder = './pages/project/backend'
else:
    raise Exception
    
if 'REDIS_URL' in os.environ:
    # Use Redis & Celery if REDIS_URL set as an env variable
    from celery import Celery
    celery_app = Celery(__name__, broker=os.environ['REDIS_URL'], backend=os.environ['REDIS_URL'])
    background_callback_manager = CeleryManager(celery_app)

else:
    # Diskcache for non-production apps when developing locally
    import diskcache
    cache = diskcache.Cache(os.path.join(folder, "cache"))
    background_callback_manager = DiskcacheManager(cache)
  

# The defalt input data is unchanged, input data can be changed by the user
default_input_filename = os.path.join(folder, "input_default.csv")
input_filename = os.path.join(folder, "input.csv")

# Import the default input data
default_data = pd.read_csv(default_input_filename)

# Initialize the input file with default values
# The trick is to define a dummy div with a callback, which is called just at page load, 
# and copy the default input parameters to the ones, used in the simulation input inside of the callback.
init = html.Div(id="init-div")
@callback(
    Input("init-div", "id"),
)
def initialize(id):
    shutil.copyfile(default_input_filename, input_filename)


# Create a grid table with editable values of parameters
grid = dag.AgGrid(
    id = "input-grid",
    rowData = default_data.to_dict("records"),
    columnSize="autoSize",
    columnDefs = [{"field": col, 'sortable': False, 'editable': True} if col == 'Value' 
                  else {"field": col, 'sortable': False} for col in default_data.columns if col != 'Variable'],
    style={"width": 700}
)

buttons = html.Div(
    [
        dbc.Button("Save", id="save-button", color="secondary", className="me-1", n_clicks=0, disabled=True),  
        dbc.Tooltip('Save modified input parameters', target='save-button'),
        dbc.Button("Run", id="run-button", color="primary", className="me-1", n_clicks=0, disabled=False),   
        dbc.Tooltip('Run simulation using saved input parameters', target='run-button'),
        dbc.Button("Load defaults", id="load-button", color="info", className="me-1", n_clicks=0),   
        dbc.Tooltip('Load default input parameters', target='load-button'),  
        dbc.Alert(
            #"Modified input parameters saved in " + input_filename,
            "Modified input parameters saved",
            id="save-button-alert",
            is_open=False,
            dismissable=True,
            # duration=2000,
        ),    
        dbc.Alert(
            'Simulation results are available in the Results tab',
            id="run-button-alert",
            is_open=False,
            dismissable=True,
        ),          
    ]
)

# The tab with input data and buttons
tab_input = dbc.Container(
    [
        dbc.Row(grid),   
        html.Hr(),
        dbc.Row(buttons),
        html.Hr(),
        html.Span([
            html.Progress(id="progress_bar", style={"visibility": "hidden"}),
            html.Span(id='progress_status', children='Loading data..', style={"visibility": "hidden", "marginLeft": "15px"}),       # hidden
        ]),
        html.Div(id="editing-grid-output"),
    ],     
    fluid=True
)

# The results tab is initially disabled
#disabled_results = True
tab_results = dbc.Container(
    [
        html.Div(id="results_div"),
    ],     
    fluid=True
)

# If some value(s) are changed in the input table, activate Save button and deactivate Run button.
# Make sure that nothing is updated if nothing is changed in the table.
# Need to use allow_duplicate=True and prevent_initial_call=True to enable status change from the 2 callbacks
@callback(
    Output("save-button", "disabled", allow_duplicate=True), 
    Output("run-button", "disabled", allow_duplicate=True), 
    Input("input-grid", "cellValueChanged"),
    prevent_initial_call=True
)
def on_modified_input(cell_changed):
    if cell_changed is None:
        raise PreventUpdate
    return False, True


# Callback for the Save button: save the modified input data to input.csv, disable the Save button, and enable the Run button
@callback(Output("save-button-alert", "is_open"), Output("save-button", "disabled"), Output("run-button", "disabled"),
    Input("input-grid", "rowData"), Input("save-button", "n_clicks"),
    State("save-button-alert", "is_open"),
    prevent_initial_call=True
)
def on_save_button_click(data, n, is_open):

    if n is not None:
    
        # Convert the dict with the modified input to a dataframe
        updated_input = pd.DataFrame.from_dict(data)

        # Save the updated input to CSV
        updated_input.to_csv(input_filename, index=False) 

        # This prints the dict of modified input in the field (add Output("editing-grid-output", "children"))
        # return f"{data}"

        return not is_open, True, False        
    #return is_open        


# Callback for the Load defaults button: save the modified input data to input.csv, disable the Save button, and enable the Run button
@callback(
    Output("input-grid", "rowData", allow_duplicate=True), 
    Output("save-button", "disabled", allow_duplicate=True), 
    Output("run-button", "disabled", allow_duplicate=True),
    Input("load-button", "n_clicks"),
    prevent_initial_call=True
)
def on_load_button_click(n):
    if n is not None:   
        return default_data.to_dict("records"), True, False        


# Callback for the Run button
@callback(
    Output("id_tab_results", "children"),
    Output("run-button-alert", "is_open"),
    Output("id_tab_results", "disabled"), 
    Input("run-button", "n_clicks"),
    State("run-button-alert", "is_open"),
    background=True,
    manager=background_callback_manager,    
    prevent_initial_call=True,
    running=[
        (Output("run-button", "disabled"), True, False), 
        (Output("load-button", "disabled"), True, False),
        (
            Output("progress_bar", "style"),
            {"visibility": "visible"},
            {"visibility": "hidden"},
        ),
        (
            Output("progress_status", "style"),
            {"visibility": "visible", "marginLeft": "15px"},
            {"visibility": "hidden", "marginLeft": "15px"},
        ),        
    ],
    progress=[
        Output("progress_bar", "value"), 
        Output("progress_bar", "max"), 
        Output("progress_status", "children"),
    ],
)
def on_run_button_click(set_progress, n, is_open):

    # Tota number of steps in the progress bar
    total = 3
    
    if n is not None:   
    
        # Step #1: update the Output in the progress decorator
        set_progress((str(1), str(total), 'Running simulation..'))

        # Run the simulation
        run_backend(folder)
        
        # Step #2
        set_progress((str(2), str(total), 'Creating plots..'))
        
        # Read the results and remove units fom column names
        data = pd.read_csv(os.path.join(folder, "results.csv"))
        cols_units = data.columns.to_list()
        cols = [c.split()[0] for c in cols_units]
        data.rename(columns=dict(zip(cols_units, cols)), inplace=True)
        
        # Graphs with simulation results
        graphs = html.Div([
                dcc.Graph(
                    id='pressure',
                    figure={
                        "data": [
                            {
                                "x": data["Pressure"],
                                "y": data["MD"],
                            }
                        ],
                        "layout": {
                            #'title': 'Basic Dash Example',
                            "xaxis": {"title": cols_units[1]},
                            "yaxis": {"title": cols_units[0], 'autorange': "reversed"},
                        },
                    },
                    style={'display': 'inline-block'},
                ),
                dcc.Graph(
                    id='temperature',
                    figure={
                        "data": [
                            {
                                "x": data["Temperature"],
                                "y": data["MD"],
                            }
                        ],
                        "layout": {
                            #'title': 'Basic Dash Example',
                            "xaxis": {"title": cols_units[2]},
                            "yaxis": {"title": cols_units[0], 'autorange': "reversed"},
                        },
                    },
                    style={'display': 'inline-block'},
                )]
        )      

        # This updates the Output in the progress decorator
        set_progress((str(3), str(total), 'Done!'))        
    
        # Return graphs, show the alert, and activate the Results tab        
        return graphs, not is_open, False        



layout = html.Div()


dash.register_page(
    __name__,
    path='/project',
)