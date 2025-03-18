import dash
from dash import Dash, dcc, html, Input, Output, callback
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
import os, platform
import pandas as pd
import datetime
from flask import request, copy_current_request_context

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

# Initialize user data store
data = {
    'folder': folder,
    'logged_in': False, 
    'username': ''
}

# Create the layout for the app
app.layout = html.Div([
    dcc.Store(id='user-store', data=data),  # Store for user data
    dcc.Location(id="url"), 
    html.Div(id="navbar"),  # Placeholder for the navbar
    html.Div(id="page-content", style={"padding": "0.8rem 0.8rem"})  # Content area
])

# Function to create the navigation bar based on user login status
def create_navbar(user_data):
    nav_items = [
        dbc.NavItem(dbc.NavLink("Project", href="/project", active="exact")),
        dbc.NavItem(dbc.NavLink("Blog", href="/blog", active="exact")),
        dbc.NavItem(dbc.NavLink("About", href="/about", active="exact")),
    ]
    
    if user_data['logged_in']:
        username = user_data['username']
        nav_items.append(dbc.NavItem(
            dbc.DropdownMenu(
                children=[
                    dbc.DropdownMenuItem("Logout", href="/login", style={"color": "red"}),
                ],
                nav=True,
                in_navbar=True,
                label=f"Logged in as: {username}",
            )
        ))
    else:
        nav_items.append(dbc.NavItem(dbc.NavLink("Sign in", href="/login", active="exact", 
            style={"border": "2px grey solid", 'borderRadius': '5px'})))

    return dbc.Navbar(
        dbc.Container(
            [
                html.A(
                    dbc.Row(
                        [
                            dbc.Col(html.Img(src=os.path.join(folder, '/assets/kirsch.png'), height="30px")),
                            dbc.Col(dbc.NavbarBrand("THERMOCO2WELL", className="ms-2")),
                        ],
                    #align='center',
                        className="g-0",
                    ),
                    href="/",
                    style={"textDecoration": "none"},
                ),
                dbc.NavbarToggler(id="navbar-toggler", n_clicks=0),
                dbc.Collapse(
                    dbc.Nav(nav_items, className="ms-auto", navbar=True),
                    id="navbar-collapse",
                    navbar=True,
                ),
            ],
            fluid=True,
        ),
        id="navbar", 
        className="mb-0"
    )

# Update the navbar based on user being logged in or not
@app.callback(
    Output('navbar', 'children'),
    Input('user-store', 'data'),
)
def update_navbar(user_data):
    # Handle case when user_data is None
    if user_data is None:
        user_data = {'logged_in': False, 'username': ''}  # Default values
    return create_navbar(user_data)

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
    dbc.Col(item, md=4, align='stretch') for item in article_cards
], className='g-3')

# Read the contents of the About section
about = ''
with open(os.path.join(folder, 'pages/about.md'), 'r') as file:
   about = file.read()

# Define the login and signup pages
from pages.login.layout import *

# Callback to render the page content based on URL
@app.callback(
    Output("page-content", "children"), 
    Input("url", "pathname"),
    Input('user-store', 'data')  # Add user data as input
)
def render_page_content(pathname, user_data):
    navbar_visible = {'display': 'block'}
    navbar_non_visible = {'display': 'none'}    

    if pathname == "/":
        return blog
    elif pathname == "/project":
        return project    
    elif pathname == "/blog":
        return blog    
    elif "blog/" in pathname:
        return article_pages[pathname]       
    elif pathname == "/about":
        return dcc.Markdown(about, dangerously_allow_html=True)
    # Navbar made visible upon logging in and signing up
    elif pathname == "/login":
        return login  # Login page
    elif pathname == "/signup":
        return signup  # Signup page
        
    # If the user tries to reach a different page, return a 404 message
    return html.Div(
        [
            html.H1("404: Not found", className="text-danger"),
            html.Hr(),
            html.P(f"The pathname {pathname} was not recognised..."),
        ],
        className="p-3 bg-light rounded-3",
    )

# server is referred to in app.wsgi    
server = app.server

# Callback to log user access data
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

# Run the server
if __name__ == '__main__':
    app.run(debug=True)