import dash
from dash import Dash, dcc, html, Input, Output, State, callback
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
import os, platform
import pandas as pd
import datetime
from flask import request


# Need to specify the run folder for the production system
if platform.system() == 'Linux':
    folder = '/var/www/FlaskDash'
elif platform.system() == 'Windows':
    folder = '.'
else:
    raise Exception

# Initialize the app - incorporate a Dash Bootstrap theme
# Use the dash pages functionality
external_stylesheets = [dbc.themes.CERULEAN, dbc.icons.FONT_AWESOME]
app = Dash(__name__, 
           use_pages=True,
           external_stylesheets=external_stylesheets,
           suppress_callback_exceptions=True)
app.title = "THERMOCO2WELL"

# Items for the navigation bar
nav_project = dbc.NavItem(dbc.NavLink("Project", href="/project", active="exact"))
nav_blog = dbc.NavItem(dbc.NavLink("Blog", href="/blog", active="exact"))
nav_about = dbc.NavItem(dbc.NavLink("About", href="/about", active="exact"))
nav_login = dbc.NavItem(dbc.NavLink("Sign in", href="/login", active="exact", 
                                    style={"border":"2px grey solid", 'borderRadius': '5px'},
                                    id="nav-login"
                                    ))

nav_logout = dbc.NavItem(
    dbc.Button("Logout", id="logout-button", color="danger", className="ms-2", n_clicks=0, style={'display': 'none'})
)

navbar = dbc.Navbar(
    dbc.Container(
        [
            html.A(
                dbc.Row(
                    [
                        dbc.Col(html.Img(src=os.path.join(folder, '/assets/kirsch.png'), height="30px")),
                        dbc.Col(dbc.NavbarBrand("THERMOCO2WELL", className="ms-2")),
                    ],
                    className="g-0",
                ),
                href="/",
                style={"textDecoration": "none"},
            ),
            dbc.NavbarToggler(id="navbar-toggler", n_clicks=0),
            dbc.Collapse(
                dbc.Nav(
                    [nav_project, nav_blog, nav_about, nav_login, nav_logout],
                    className="ms-auto",
                    navbar=True,
                ),
                id="navbar-collapse",
                navbar=True,
            ),
        ],
        fluid=True,
    ),
    id="navbar", 
    className="mb-0",   
    style={'display': 'block'},
)

# Callback to update the navbar links based on login status
@app.callback(
    [
        Output('nav-login', 'style'),
        Output('logout-button', 'style', allow_duplicate=True)
    ],
    Input('user-store', 'data'),  # Get user data to check login status
    prevent_initial_call=True  # Prevent the initial callback when the app starts
)
def update_navbar(user_data):
    if user_data and user_data.get('logged_in', False):
        # If logged in, show the "Management" link and "Logout" button, hide "Sign in"
        nav_login_style = {'display': 'none'}
        logout_style = {'display': 'block'}
    else:
        # If not logged in, hide the "Management" link, show "Sign in" link and "Logout" button hidden
        nav_login_style = {'display': 'block'}
        logout_style = {'display': 'none'}

    # Return updated navbar with the correct visibility of the links
    return nav_login_style, logout_style

# Define the project page
from pages.project.layout import tab_input, tab_results
project = dbc.Tabs(
    [
        dbc.Tab(tab_input, label="Input"), 
        dbc.Tab(tab_results, id='id_tab_results', label="Results", disabled=True),
    ]
)

# Format the blog output
from pages.blog.layout import article_cards, article_pages

blog = dbc.Row([
        dbc.Col(
            item,
            md=4,
            align='stretch'
        ) for item in article_cards
        ],
        class_name='g-3'
)

# Read the contents of the About section
about = ''
with open(os.path.join(folder, 'pages/about.md'), 'r') as file:
   about = file.read()

# Define the login and signup pages
from pages.login.layout import *

# Padding to match the one in the navbar
CONTENT_STYLE = {
    "padding": "0.8rem 0.8rem",
}

# Initialize the store with the folder and empty user data
data = {
    'folder': folder,
    'logged_in': False,  # Initialize as False
    'username': ''
}

# Display the pages in the content div
content = html.Div(dash.page_container, id="page-content", style=CONTENT_STYLE)

dash.register_page(__name__, path='/management')  # Register management page
from pages.management import layout as management

# The layout consists of the navigation bar at the top, and the pages' content below 
app.layout = html.Div([
    dcc.Store(id='user-store', data=data, storage_type="local"),  # Initialize user store
    dcc.Location(id="url", refresh=True),
    navbar, 
    content,
    html.Div(id='user-status', style={'textAlign': 'right', 'padding': '10px'}),
])

# we use a callback to toggle the collapse on small screens
def toggle_navbar_collapse(n, is_open):
    if n:
        return not is_open
    return is_open

app.callback(
    Output(f"navbar-collapse", "is_open"),
    [Input(f"navbar-toggler", "n_clicks")],
    [State(f"navbar-collapse", "is_open")],
)(toggle_navbar_collapse)

@app.callback(
    Output("logout-button", "style"),
    Input("user-store", "data")
)
def toggle_logout_button(user_data):
    if user_data.get("logged_in", False):
        return {'display': 'inline-block'}
    return {'display': 'none'}

@app.callback(
    Output("user-store", "data", allow_duplicate=True),
    Output("url", "pathname"),
    Input("logout-button", "n_clicks"),
    State("user-store", "data"),
    prevent_initial_call=True
)
def logout(n_clicks, user_data):
    user_data["logged_in"] = False
    user_data["username"] = ""
    return user_data, "/login"

@app.callback(
    Output("navbar", "style"), 
    Output("page-content", "children"), 
    Input("url", "pathname"),
    Input('user-store', 'data'),  # Check user status
)
def render_page_content(pathname, user_data):
    print(f"Pathname: {pathname}")  # Debugging print
    print(f"User data: {user_data}")  # Debugging print
    
    navbar_visible = {'display': 'block'}
    navbar_non_visible = {'display': 'none'}

    # Check if user is logged in
    logged_in = user_data.get('logged_in', False)
    print(f"Is user logged in? {logged_in}")  # Debugging print

    # Always show navbar except on login and signup pages
    if pathname in ["/login", "/signup"]:
        navbar_style = navbar_non_visible
    else:
        navbar_style = navbar_visible

    # If the pathname is '/management', we want to print the username
    if pathname == "/management":
        # Print the user's name to the terminal
        username = user_data.get('username', 'Not logged in')  # Get username or a default
        print(f"Loading management page for user: {username}")  # This should print now!
        
    # Render the appropriate page content based on the pathname
    if pathname == "/":
        return navbar_style, blog
    elif pathname == "/project":
        return navbar_style, project    
    elif pathname == "/blog":
        return navbar_style, blog    
    elif "blog/" in pathname:
        return navbar_style, article_pages[pathname]       
    elif pathname == "/about":
        return navbar_style, dcc.Markdown(about, dangerously_allow_html=True)
    elif pathname == "/login":
        return navbar_non_visible, login  # Keep login page rendering
    elif pathname == "/signup":
        return navbar_non_visible, signup  # Keep signup page rendering
    elif pathname == "/management":
        # Render management page layout here
        return navbar_style, management

    # If the user tries to reach a different page, return a 404 message
    return navbar_style, html.Div(
        [
            html.H1("404: Not found", className="text-danger"),
            html.Hr(),
            html.P(f"The pathname {pathname} was not recognised..."),
        ],
        className="p-3 bg-light rounded-3",
    )

# Callback to update the user status display and print user directory
@app.callback(
    Output('user-status', 'children'),
    Input('user-store', 'data')
)
def update_user_status(user_data):
    username = user_data.get('username', '')
    
    if username:
        # Correct path to the user directory under 'accounts' folder
        user_directory = os.path.join(os.path.dirname(__file__), '..', 'accounts', username)
        
        # Ensure the path is absolute
        user_directory = os.path.abspath(user_directory)
        
        print(f"User Directory for {username}: {user_directory}")  # Print user directory in terminal
        return f'Logged in as: {username}'
    
    print("No user logged in.")  # Print if no user is logged in
    return 'Not logged in'


# server is referred to in app.wsgi    
server = app.server


@app.callback(Input('url', 'href'))
def display_page(href):
    if href is None:
        raise PreventUpdate
        
    # Store the user access data in CSV
    timestamp = datetime.datetime.now()
    data = [timestamp.strftime("%Y-%m-%d %H:%M:%S"), request.remote_addr]
    columns = ['Timestamp', 'IP']
    df = pd.DataFrame([data], columns=columns)
    fname = os.path.join(folder, 'sessions/sessions.csv')
    if os.path.exists(fname):
        df.to_csv(fname, mode='a', index=False, header=False)
    else:
        df.to_csv(fname, mode='a', index=False, header=True)

if __name__ == '__main__':
    app.run(debug=True)
