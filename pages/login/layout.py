from dash import html, Input, Output, State, callback
import dash_bootstrap_components as dbc
import os
import sqlite3
import bcrypt
import shutil

# Define the layout for the login page
login = dbc.Container(
    [
        html.Img(src=os.path.join('/assets/kirsch.png'), height="30px", className='mb-3'),
        html.H4('Sign in', className="card-title mb-3"),
        dbc.Card(
                dbc.CardBody(
                    [
                        dbc.Label("Email", html_for="login-email"),
                        dbc.Input(type="email", id="login-email", required=True, autocomplete='email', className='mb-3'), 
                        dbc.Row([
                            dbc.Col(dbc.Label("Password", html_for="login-password")),
                            dbc.Col(html.A("Forgot password?", href='https://plot.ly'), 
                                    style={'display': 'flex', 'justifyContent': 'right',}),
                        ]),                        
                        dbc.Input(type="password", id="login-password", required=True, autocomplete='current-password', className='mb-3'),
                        dbc.Row(
                            dbc.Button('Sign in', id='login-button',),  
                        )                        
                    ],
                    ),
            style={'width': '400px'},  # Set a specific width for the card
            className='mb-3',
        ),
        dbc.Row([
            dbc.Col([
                dbc.Label('No account?', style={"margin-right": "10px"}), 
                html.A("Open one!", href='/signup')
            ],
            style={'display': 'flex', 'justifyContent': 'center',}), 
        ],
        style={'width': '400px',}
        ),
    ],
    style={
        'height': '80vh',  # Full viewport height
        'display': 'flex',
        'justifyContent': 'center',
        'alignItems': 'center',
        'flex-direction': 'column'
    },
    fluid=True,
)

# Define the layout for the signup page
signup = dbc.Container(
    [
        html.Img(src=os.path.join('/assets/kirsch.png'), height="30px", className='mb-3'),
        html.H4('Sign up', className="card-title mb-3"),
        dbc.Card(
                dbc.CardBody(
                    [
                        dbc.Label("Email", html_for="signup-email"),
                        dbc.Input(type="email", id="signup-email", required=True, autocomplete='email', className='mb-3'),
                        html.Div([
                            dbc.Label("Password", html_for="signup-password"),                     
                            dbc.Input(type="password", id="signup-password", required=True, autocomplete='current-password'),
                            dbc.FormText("Password should be at least 8 characters"),
                        ], className='mb-3'
                        ),
                        dbc.Label("Name", html_for="signup-name"),                       
                        dbc.Input(type="text", id="signup-name", required=True, className='mb-3'),
                        dbc.Row(
                            dbc.Button('Sign up', id='signup-button',),  
                        )                        
                    ],
                    ),
            style={'width': '400px'},  # Set a specific width for the card
            className='mb-3',
        ),
        dbc.Row([
            dbc.Col([
                dbc.Label('Already have an account?', style={"margin-right": "10px"}),
                html.A(" Sign in!", href='/login')
            ],
                style={'display': 'flex', 'justifyContent': 'center', }),
        ],
            style={'width': '400px', }
        ),
        dbc.Alert("Template alert", id='template_alert', is_open=False, color="danger", style={'width': '400px'}),
    ],
    style={
        'height': '80vh',  # Full viewport height
        'display': 'flex',
        'justifyContent': 'center',
        'alignItems': 'center',
        'flex-direction': 'column'
    },
    fluid=True,
)


@callback(
    Output('template_alert', 'is_open', allow_duplicate=True),
    Output('template_alert', 'children', allow_duplicate=True),
    State('signup-name', 'value'),
    State('signup-email', 'value'),
    State('signup-password', 'value'),
    State('user-store', 'data'),
    Input('signup-button', 'n_clicks'),
    prevent_initial_call=True,
)
def signup_user(name, email, password, user_store, n_clicks):
    '''
    Once the Sign up button is clicked, the database with the user data 
    is initialized if not done previously, and the new user data are stored 
    in the database. any(elem is None for elem in list_1)
    '''

    alert_open = False
    msg = ''

    if any(elem is None for elem in [name, email, password]):
        msg = 'Please fill in the empty fields!'
        alert_open = True
        return alert_open, msg

    # Validate the email address
    # ...

    # Create the users' database if it does not exist
    DB_PATH = os.path.join(user_store['folder'], 'pages/accounts/users.db')
    if not os.path.isfile(DB_PATH):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL
            )
        ''')
        conn.commit()
        conn.close()

    # Check if the user already exists
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM users WHERE username = ?', (email,))
    if cursor.fetchone() is not None:
        conn.close()
        msg = 'The provided email is already associated with an account. Please sign in.'
        alert_open = True
        return alert_open, msg

    # Add a new user to the database
    hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    cursor.execute('INSERT INTO users (username, password) VALUES (?, ?)', (email, hashed_password.decode('utf-8')))
    conn.commit()
    conn.close()

    return alert_open, msg







