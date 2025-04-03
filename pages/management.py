import dash
from dash import html, dcc, callback, Input, Output, State
import dash_bootstrap_components as dbc
import os
import shutil

# Define base accounts folder
ACCOUNTS_FOLDER = "./pages/accounts"
TEMPLATE_FOLDER = os.path.join(ACCOUNTS_FOLDER, "Template")

# Function to get logged-in user email dynamically from user-store
def get_logged_in_user(user_data):
    """Retrieve the currently logged-in user's email from user-store."""
    return user_data.get('username', None)  # Dynamic fetching from user-store

layout = html.Div([  
    # Store for the selected project name
    html.H1("Project Management", style={"color": "black"}),  # Changed title to "Project Management" with black color
    html.P("Here you can manage your projects and other settings."),

    # Centered buttons for project management
    html.Div([
        html.Button(
            [html.I(className="fa-solid fa-eye"), " See My Projects"], 
            id="see-my-projects-button", 
            n_clicks=0, 
            className="btn btn-outline-dark btn-lg rounded-3 mx-2"
        ),
        html.Button(
            [html.I(className="fa-solid fa-square-plus"), " Add New Project"], 
            id="add-new-project-button", 
            n_clicks=0, 
            className="btn btn-outline-dark btn-lg rounded-3 mx-2"
        ),
    ], style={"textAlign": "center"}),  # Center the buttons

    # Project list container
    html.Div(id="projects-list", className="mt-3"),
    
    # Modal for adding a new project
    dbc.Modal([
        dbc.ModalHeader(
            html.H4("Add New Project", style={"font-weight": "bold", "color": "black", "textAlign": "center"})
        ),
        dbc.ModalBody([ 
            # Input box centered
            dcc.Input(
                id="new-project-name", 
                type="text", 
                placeholder="Enter new project name", 
                style={"display": "block", "margin": "0 auto", "width": "80%", "textAlign": "center"}
            ),
            # Red message for empty input
            html.Div(id="input-error-message", children="", style={"color": "red", "textAlign": "center", "marginTop": "10px"}),
        ]),
        dbc.ModalFooter([ 
            dbc.Button(
                "Confirm", 
                id="confirm-new-project", 
                n_clicks=0, 
                style={"background-color": "black", "color": "white", "border": "none", "font-weight": "bold"},
                className="ml-auto"
            ),
        ]),
    ], id="new-project-modal", is_open=False),
])

# Callback to manage project actions (add, see, delete)
@callback(
    Output("projects-list", "children"),
    Output("new-project-modal", "is_open"),
    Output("input-error-message", "children"),  # Error message for empty project name
    Input("see-my-projects-button", "n_clicks"),
    Input("add-new-project-button", "n_clicks"),
    Input("confirm-new-project", "n_clicks"),
    Input({"type": "project-delete-button", "index": dash.ALL}, "n_clicks"),  # Listen for delete button clicks
    State("new-project-name", "value"),
    State("new-project-modal", "is_open"),
    State("user-store", "data"),
    prevent_initial_call=True,
)
def manage_projects(see_clicks, add_clicks, confirm_clicks, delete_clicks, new_project_name, modal_open, user_data):
    ctx = dash.callback_context
    if not ctx.triggered:
        return dash.no_update, dash.no_update, dash.no_update

    button_id = ctx.triggered[0]["prop_id"].split(".")[0]
    user_email = get_logged_in_user(user_data)  # Get the logged-in user's email
    if not user_email:
        return html.Div("You must be logged in to manage projects."), dash.no_update, dash.no_update  # Handle not logged in

    user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)

    if button_id == "see-my-projects-button":
        projects = get_user_projects(user_folder)
        project_cards = []

        for i, project in enumerate(projects):
            project_card = dbc.Card(
                dbc.CardBody([ 
                    html.H5(project, className="card-title", style={"font-weight": "bold", "text-decoration": "underline"}),

                    # Wrap the buttons in a div with Flexbox classes
                    html.Div(
                        [
                            # Open Button (Left aligned)
                            dbc.Button(
                                [html.I(className="fa-solid fa-door-open"), " Open"],
                                id={"type": "project-open-button", "index": project},
                                color="dark",
                                outline=False,
                                className="text-white",
                                style={"background-color": "black", "border-color": "black", "font-weight": "bold"},
                                href=f"/project?name={project}",
                                n_clicks=0
                            ),
                            
                            # Delete Button (Right aligned)
                            dbc.Button(
                                [html.I(className="fa-solid fa-trash", style={"color": "red"}), " Delete"],
                                id={"type": "project-delete-button", "index": project},
                                color="secondary",  # Grey button color
                                outline=True,
                                style={"color": "black", "border": "1px solid black", "font-weight": "bold"},
                                n_clicks=0
                            ),
                        ],
                        className="d-flex justify-content-between"  # Align buttons on opposite sides
                    ),
                ]),
                style={"background-color": "white", "border": "1px solid black", "cursor": "pointer"},
            )
            project_cards.append(dbc.Col(project_card, width=4))

        rows = [dbc.Row(project_cards[i:i+3], className="mb-3") for i in range(0, len(project_cards), 3)]
        return rows, modal_open, dash.no_update

    if button_id == "add-new-project-button":
        return dash.no_update, True, dash.no_update

    if button_id == "confirm-new-project":
        if not new_project_name:
            return dash.no_update, True, "Please enter a name for your project"
        
        create_project(user_folder, new_project_name)
        return dash.no_update, False, dash.no_update

    # Handle Delete button clicks
    if "project-delete-button" in button_id:
        try:
            # Correctly extract the project name from the button ID using the 'index' key, as we do for the "Open" button
            project_name = ctx.triggered[0]["prop_id"].split(":")[1].strip('"')  # This correctly extracts the project name

            # Ensure the project name is extracted from the right part of the button's ID
            if isinstance(project_name, dict):
                project_name = project_name.get('index')

            project_path = os.path.join(user_folder, project_name)

            # Check if the folder exists before attempting to delete
            if os.path.exists(project_path):
                shutil.rmtree(project_path)  # Delete the project folder and its contents
                print(f"Project Deleted: {project_name} at {project_path}")
            else:
                print(f"Project folder not found: {project_path}")

        except Exception as e:
            print(f"Error while deleting project: {str(e)}")

        # Refresh the project list after deletion
        return dash.no_update, dash.no_update, dash.no_update

    return dash.no_update, dash.no_update, dash.no_update



# Callback to handle "Open" button click and print project name and folder path in terminal
@callback(
    Output("projects-list", "children", allow_duplicate=True),
    Input({"type": "project-open-button", "index": dash.ALL}, "n_clicks"),
    State("user-store", "data"),  # Added state to get user info from user-store
    prevent_initial_call=True,
)
def handle_project_click(n_clicks, user_data):
    if n_clicks:
        # Get the ID of the button that was clicked
        triggered_id = dash.callback_context.triggered[0]["prop_id"]
        
        try:
            # Extract only the part of the ID that corresponds to the project name
            # The format is {"type": "project-open-button", "index": "p1"} (or similar)
            # We're only interested in the "index" part, so we'll split the string appropriately
            project_name = triggered_id.split('"')[3].strip()  # This extracts the value of the "index" field

            # Get the logged-in user email
            user_email = get_logged_in_user(user_data)
            if not user_email:
                print("Error: User not logged in.")
                return dash.no_update

            # Construct the full path to the user folder
            user_folder = os.path.join(ACCOUNTS_FOLDER, user_email)

            # Construct the full path to the project folder
            project_path = os.path.join(user_folder, project_name)

            # Normalize the project path to ensure correct formatting of slashes
            project_path = os.path.normpath(project_path)

            # Print project name and folder path
            print(f"Project {project_name} opened.")
            print(f"Project folder path: {project_path}")  # Print the full path to the project folder

            # Check if 'input.csv' exists in the project folder
            input_csv_path = os.path.join(project_path, 'input.csv')

            # Normalize the input CSV path
            input_csv_path = os.path.normpath(input_csv_path)

            print(f"Looking for input.csv at: {input_csv_path}")  # Debugging

            # Check if input.csv exists at the resolved path
            if os.path.exists(input_csv_path):
                print(f"'input.csv' exists in {project_path}")  # Print message if input.csv exists
            else:
                print(f"'input.csv' does not exist in {project_path}")  # Print message if input.csv does not exist

        except Exception as e:
            print(f"Error while handling project: {str(e)}")

    return dash.no_update


def get_user_projects(user_folder):
    """Retrieve project names from the user's specific folder."""
    if not os.path.exists(user_folder):
        os.makedirs(user_folder)
    projects = [f for f in os.listdir(user_folder) if os.path.isdir(os.path.join(user_folder, f))]
    print(f"Existing Projects for {user_folder}: {projects}")  # Debugging
    return projects

def create_project(user_folder, project_name):
    """Create a new project directory in the logged-in user's folder and copy template files."""
    project_path = os.path.join(user_folder, project_name)
    if not os.path.exists(project_path):
        os.makedirs(project_path)
        print(f"Created Project Folder: {project_path}")  # Debugging
        
        # Copy template files
        if os.path.exists(TEMPLATE_FOLDER):
            for item in os.listdir(TEMPLATE_FOLDER):
                src_path = os.path.join(TEMPLATE_FOLDER, item)
                dest_path = os.path.join(project_path, item)
                if os.path.isdir(src_path):
                    shutil.copytree(src_path, dest_path)
                else:
                    shutil.copy2(src_path, dest_path)
            print(f"Copied template files to: {project_path}")  # Debugging
