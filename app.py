import dash
from dash import Dash, dcc, html, Input, Output, State, callback
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
      
# Read the text sections
about = ''
with open(os.path.join(folder, 'pages/about.md'), 'r') as file:
   about = file.read()
   

# Initialize the app - incorporate a Dash Bootstrap theme
# Use the dash pages functionality
external_stylesheets = [dbc.themes.CERULEAN, dbc.icons.FONT_AWESOME]
app = Dash(__name__, 
           use_pages=True,
           external_stylesheets=external_stylesheets,
           suppress_callback_exceptions=True)
app.title = "THERMOCO2WELL"

# Items for the navigation bar
nav_project = dbc.NavItem(dbc.NavLink("Project", href="/project", active="exact"),)
nav_about = dbc.NavItem(dbc.NavLink("About", href="/about", active="exact"),)
nav_blog = dbc.NavItem(dbc.NavLink("Blog", href="/blog", active="exact"),)

navbar = dbc.Navbar(
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
                dbc.Nav(
                    [nav_project, nav_blog, nav_about],
                    className="ms-auto",    # Decrease the space between logo and NavbarBrand
                    navbar=True,
                ),
                id="navbar-collapse",
                navbar=True,
            ),
        ],
        fluid=True,
    ),
    #color="dark",
    #dark=True,
    className="mb-0",   # Space between the navbar and the content
)

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

# Padding to match the one in the navbar
CONTENT_STYLE = {
    #"margin-left": "1rem",
    #"margin-right": "1rem",
    "padding": "0.8rem 0.8rem",
}

# Display the pages in the content div
content = html.Div(dash.page_container, id="page-content", style=CONTENT_STYLE)

app.layout = html.Div(
    [dcc.Location(id="url"), navbar, content]
)

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


@app.callback(Output("page-content", "children"), [Input("url", "pathname")])
def render_page_content(pathname):

    if pathname == "/":
        return blog
    elif pathname == "/project":
        return project    
    elif pathname == "/blog":
        return blog    
    elif "blog/" in pathname:
        return article_pages[pathname]       
    elif pathname == "/about":
        return dcc.Markdown(about, dangerously_allow_html=True) # parameter needed to get the subscripts 
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
