import dash
from dash import html, Input, Output, State, callback, dcc, DiskcacheManager, CeleryManager
import dash_ag_grid as dag
import dash_bootstrap_components as dbc
from dash.exceptions import PreventUpdate
import os, platform, shutil
import pandas as pd
from urllib.parse import urlparse, parse_qs
from dash.dcc import send_file
import base64
import io
from .backend.backend import run_backend # Needs updating if the backend folder is removed

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
  
    
# Constants for accounts
# Present so that each function can correctly identify the user and project folders
ACCOUNTS_FOLDER = "./pages/accounts"

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


# Upload component
# Button located separately from the other buttons
file_upload = dcc.Upload(
    id='upload-data',
    children=html.Button(
        html.Div([
            html.I(className="fa-solid fa-arrow-up-from-bracket"),  # Upload icon
            " Upload CSV File"
        ]),
        className="btn btn-warning"  # Button styling to match other buttons
    ),
    multiple=False
)



buttons = html.Div(
    [
        dbc.Button("Save", id="save-button", color="secondary", className="me-1", n_clicks=0, disabled=True),  
        dbc.Tooltip("Save modified input parameters", target="save-button"),
        dbc.Button("Run", id="run-button", color="primary", className="me-1", n_clicks=0, disabled=False),
        dbc.Tooltip("Run simulation using saved input parameters", target="run-button"),
        dbc.Button(html.Div([html.I(className="fa-solid fa-arrows-rotate"), " Refresh Project Inputs"]), id="load-button", color="info", className="me-1", n_clicks=0),
        dbc.Tooltip("Load project input parameters", target="load-button"),
        dbc.Button(html.Div([html.I(className="fa-solid fa-download"), " Download Results"]), id="download-button", color="success", className="me-1", n_clicks=0),  
        dbc.Tooltip("Download the results.csv file", target="download-button"),
        dcc.Download(id="download-results"),
        dbc.Alert("Modified input parameters saved", id="save-button-alert", is_open=False, dismissable=True),
        dbc.Alert("Simulation results are available in the Results tab", id="run-button-alert", is_open=False, dismissable=True),
    ]
)


# The tab with input data and buttons
tab_input = dbc.Container(
    [
        dbc.Row(grid),   
        html.Hr(),
        dbc.Row(buttons),
        html.Hr(),
        html.Span([file_upload,  # Display the upload button
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
# Modified to update the input.csv in the specific project folder for the logged in user
@callback(
    Output("save-button-alert", "is_open"), 
    Output("save-button", "disabled"), 
    Output("run-button", "disabled"),
    Input("input-grid", "rowData"), 
    Input("save-button", "n_clicks"),
    State("save-button-alert", "is_open"),
    State("url", "search"),  # Added to get project details from URL
    State("user-store", "data"),  # Added to get logged-in user's details
    prevent_initial_call=True
)
def on_save_button_click(data, n, is_open, search, user_data):
    if n is not None:
        # Retrieve project name and user email from the URL and session data
        query_params = parse_qs(urlparse(search).query)
        project_name = query_params.get("name", [None])[0]
        user_email = user_data.get("username")

        if not project_name or not user_email:
            print("Missing project name or user not logged in.")
            raise PreventUpdate

        # Construct the project folder path
        user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)
        project_folder = os.path.join(user_folder, project_name)
        input_csv_path = os.path.join(project_folder, "input.csv")

        # Convert the dict with the modified input to a DataFrame
        updated_input = pd.DataFrame.from_dict(data)

        # Save the updated input to the specific project's input.csv file
        updated_input.to_csv(input_csv_path, index=False) 

        # Return alert visibility and button states
        return not is_open, True, False  # Close alert, disable Save, enable Run button
       


# Callback for the Load defaults button modified
# Button now aims to 'refresh' the input grid, loading in the project-specific input data if automatic loading does not work
@callback(
    Output("input-grid", "rowData", allow_duplicate=True),  
    Output("save-button", "disabled", allow_duplicate=True), 
    Output("run-button", "disabled", allow_duplicate=True),
    Input("load-button", "n_clicks"),
    State("url", "search"),  # Get the URL parameters to identify the project
    State("user-store", "data"),  # Get logged-in user's details
    prevent_initial_call=True
)
def on_load_button_click(n, search, user_data):
    if n is not None:
        # Check if the URL has the required parameters (project name and user email)
        if not search:
            print("No search parameters found in the URL.")
            return default_data.to_dict("records"), True, False

        query_params = parse_qs(urlparse(search).query)
        project_name = query_params.get("name", [None])[0]
        user_email = user_data.get("username")

        if not project_name or not user_email:
            print("Missing project name or user not logged in.")
            return default_data.to_dict("records"), True, False

        # Construct the path to the project folder
        user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)
        project_folder = os.path.join(user_folder, project_name)
        input_csv_path = os.path.join(project_folder, "input.csv")

        try:
            if os.path.exists(input_csv_path):
                # Load the project-specific input.csv
                df = pd.read_csv(input_csv_path)
                print(f"Successfully loaded {input_csv_path} with {len(df)} rows.")
                return df.to_dict("records"), True, False  # Update grid data
            else:
                print(f"Warning: input.csv not found in {project_folder}. Returning default data.")
                return default_data.to_dict("records"), True, False  # Return default data if file is not found
        except Exception as e:
            print(f"Error loading input data from {input_csv_path}: {e}")
            return default_data.to_dict("records"), True, False  # Return default data on error
       


# Callback for the Run button
# Now modified to identify the project folder and run the necessary files in that folder for simulation instead of the backend
@callback(
    Output("id_tab_results", "children"),
    Output("run-button-alert", "is_open"),
    Output("id_tab_results", "disabled"), 
    Input("run-button", "n_clicks"),
    State("run-button-alert", "is_open"),
    State("url", "search"),  # Get project details from URL
    State("user-store", "data"),  # Get logged-in user's details
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
def on_run_button_click(set_progress, n, is_open, search, user_data):
    # Total number of steps in the progress bar
    total = 3
    
    if n is not None:
        # Get project and user details from the URL and session
        query_params = parse_qs(urlparse(search).query)
        project_name = query_params.get("name", [None])[0]
        user_email = user_data.get("username")

        if not project_name or not user_email:
            print("Missing project name or user not logged in.")
            raise PreventUpdate

        # Step #2: Construct the project folder path
        user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)
        project_folder = os.path.join(user_folder, project_name)

        # Step #3: Update the progress bar and run the simulation
        set_progress((str(1), str(total), 'Running simulation..'))

        # Run the simulation using the project folder
        run_backend(project_folder)
        
        # Step #4: Update progress for plot creation
        set_progress((str(2), str(total), 'Creating plots..'))
        
        # Read the results and remove units from column names
        data = pd.read_csv(os.path.join(project_folder, "results.csv"))
        cols_units = data.columns.to_list()
        cols = [c.split()[0] for c in cols_units]
        data.rename(columns=dict(zip(cols_units, cols)), inplace=True)
        
        # Create graphs with the simulation results
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
                            "xaxis": {"title": cols_units[2]},
                            "yaxis": {"title": cols_units[0], 'autorange': "reversed"},
                        },
                    },
                    style={'display': 'inline-block'},
                )]
        )      
        
        # Step #5: Update progress to indicate completion
        set_progress((str(3), str(total), 'Done!'))
    
        # Return the generated graphs, show the alert, and activate the Results tab        
        return graphs, not is_open, False


# Callback to load project data into the grid based on URL change
@callback(
    Output("input-grid", "rowData", allow_duplicate=True),  
    Input("url", "search"),  # Triggered when the URL changes
    State("user-store", "data"),  # Ensure the user is logged in
    prevent_initial_call=True
)
def load_project_data_from_url(search, user_data):
    # Check if the URL has changed and print it for debugging
    print(f"Received URL search parameter: {search}")

    if not search:
        print("No search parameters found in the URL.")
        raise PreventUpdate  # Don't proceed if the search query is missing

    # Ensure that the user is logged in
    if not user_data or not user_data.get("logged_in", False):
        print("User is not logged in. Returning default data.")
        return default_data.to_dict("records")  # Return default data if not logged in

    # Parsing the project name from the URL
    query_params = parse_qs(urlparse(search).query)
    project_name = query_params.get("name", [None])[0]
    user_email = user_data.get("username")

    # Log the user info and project name
    print(f"User Email: {user_email}")
    print(f"Project Name from URL: {project_name}")

    # If project_name or user_email are missing, return default data and log the issue
    if not project_name or not user_email:
        print(f"Missing project name ({project_name}) or user not logged in ({user_email}). Returning default data.")
        return default_data.to_dict("records")

    # Construct the path to the user's project folder
    user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)
    project_folder = os.path.join(user_folder, project_name)
    input_csv_path = os.path.join(project_folder, "input.csv")

    # Print the path to the input.csv for debugging
    print(f"Attempting to load input.csv from: {input_csv_path}")

    try:
        if os.path.exists(input_csv_path):
            # Log that the file exists and attempt to load
            print(f"Found input.csv, attempting to load: {input_csv_path}")
            df = pd.read_csv(input_csv_path)
            print(f"Successfully loaded input.csv with {len(df)} rows.")
            return df.to_dict("records")
        else:
            # Log if the file doesn't exist
            print(f"Warning: input.csv not found in {project_folder}. Returning default data.")
            return default_data.to_dict("records")
    except Exception as e:
        # Log any exception during file reading
        print(f"Error loading input data from {input_csv_path}: {e}")
        return default_data.to_dict("records")  # Return default data on error

# Callback for the Download Button
# Looks for the results.csv file in the project folder and downloads it
@callback(
    Output("download-results", "data"),
    Input("download-button", "n_clicks"),
    State("url", "search"),  # Get the URL parameters to identify the project
    State("user-store", "data"),  # Get logged-in user's details
    prevent_initial_call=True
)
def download_results(n_clicks, search, user_data):
    if n_clicks is None:
        raise PreventUpdate

    # Parse project name from the URL
    query_params = parse_qs(urlparse(search).query)
    project_name = query_params.get("name", [None])[0]
    user_email = user_data.get("username")

    if not project_name or not user_email:
        print("Missing project name or user not logged in.")
        raise PreventUpdate

    # Construct the path to the results.csv file
    user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)
    project_folder = os.path.join(user_folder, project_name)
    results_csv_path = os.path.join(project_folder, "results.csv")

    # Check if the file exists and serve it for download
    if os.path.exists(results_csv_path):
        print(f"Preparing to download: {results_csv_path}")
        return send_file(results_csv_path)
    else:
        print(f"File not found: {results_csv_path}")
        raise PreventUpdate



# Callback to handle the file upload and process it
# An upload button so that a user can upload a file which is then saved to a project folder
@callback(
    Output("input-grid", "rowData"),  # Update the grid with the uploaded file data
    Input('upload-data', 'contents'),
    State('upload-data', 'filename'),
    State("url", "search"),
    State("user-store", "data"),
    prevent_initial_call=True
)
def handle_upload(contents, filename, search, user_data):
    if contents is None:
        raise PreventUpdate

    # Parse project name and user email
    query_params = parse_qs(urlparse(search).query)
    project_name = query_params.get("name", [None])[0]
    user_email = user_data.get("username")

    if not project_name or not user_email:
        print("Missing project name or user not logged in.")
        raise PreventUpdate

    # Decode the uploaded file
    content_type, content_string = contents.split(',')
    decoded = base64.b64decode(content_string)
    df = pd.read_csv(io.StringIO(decoded.decode('utf-8')))

    # Save the uploaded file in the user's project folder
    user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)
    project_folder = os.path.join(user_folder, project_name)
    os.makedirs(project_folder, exist_ok=True)

    uploaded_file_path = os.path.join(project_folder, filename)
    df.to_csv(uploaded_file_path, index=False)

    # Return the uploaded data to be displayed in the grid
    return df.to_dict("records")

layout = html.Div([
    dcc.Location(id="url", refresh=False),
    tab_input,
    tab_results
])


dash.register_page(
    __name__,
    path='/project',
)