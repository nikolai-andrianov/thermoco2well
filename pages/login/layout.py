from dash import html, Input, Output, State, callback, no_update, dcc
import dash_bootstrap_components as dbc
import os
import sqlite3
import bcrypt
import shutil

# Persistent storage for user session
dcc.Store(id='user-store', storage_type='local')

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
                    dbc.Alert("", id='login-email-alert', is_open=False, color="danger"),
                    dbc.Row([ 
                        dbc.Col(dbc.Label("Password", html_for="login-password")),
                        dbc.Col(html.A("Forgot password?", href='https://plot.ly'), 
                                style={'display': 'flex', 'justifyContent': 'right',}),
                    ]),                        
                    dbc.Input(type="password", id="login-password", required=True, autocomplete='current-password', className='mb-3'),
                    dbc.Alert("", id='login-password-alert', is_open=False, color="danger"),
                    dbc.Row(
                        dbc.Button('Sign in', id='login-button'),  
                    )
                ],
            ),
            style={'width': '400px'},
            className='mb-3',
        ),
        dbc.Row([ 
            dbc.Col([ 
                dbc.Label('No account?', style={"margin-right": "10px"}), 
                html.A("Open one!", href='/signup') 
            ], style={'display': 'flex', 'justifyContent': 'center',}), 
        ], style={'width': '400px',}),
        
        # Placeholder for redirect link after login
        dbc.Row([
            html.Div(id='redirect-link', style={'textAlign': 'center'})  
        ]),

        # Add a "Proceed to Projects" button here, initially hidden
        dbc.Row([
            dbc.Col(
                dbc.Button('Proceed to Projects', id='proceed-to-projects', color='primary', style={'display': 'none'}),
                width={"size": 6, "offset": 3}
            )
        ])
    ],
    style={
        'height': '80vh',
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
                    dbc.Alert("", id='email-alert', is_open=False, color="danger"),
                    html.Div([
                        dbc.Label("Password", html_for="signup-password"),                     
                        dbc.Input(type="password", id="signup-password", required=True, autocomplete='current-password'),
                        dbc.FormText("Password should be at least 3 characters", id='password-hint'),
                        dbc.Alert("", id='password-alert', is_open=False, color="danger"),
                    ], className='mb-3'),
                    dbc.Label("Name", html_for="signup-name"),                       
                    dbc.Input(type="text", id="signup-name", required=True, className='mb-3'),
                    dbc.Row(
                        dbc.Button('Sign up', id='signup-button',),  
                    )                        
                ],
            ),
            style={'width': '400px'},  
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
    ],
    style={
        'height': '80vh',
        'display': 'flex',
        'justifyContent': 'center',
        'alignItems': 'center',
        'flex-direction': 'column'
    },
    fluid=True,
)

# Signup user function
@callback(
    Output('email-alert', 'is_open', allow_duplicate=True),
    Output('email-alert', 'children', allow_duplicate=True),
    Output('signup-email', 'className', allow_duplicate=True),
    Output('password-alert', 'is_open', allow_duplicate=True),
    Output('password-alert', 'children', allow_duplicate=True),
    Output('signup-password', 'className', allow_duplicate=True),
    Output('user-store', 'data', allow_duplicate=True),
    Output('navbar', 'style', allow_duplicate=True),
    Output('url', 'href', allow_duplicate=True),
    State('signup-name', 'value'),
    State('signup-email', 'value'),
    State('signup-password', 'value'),
    State('user-store', 'data'),
    Input('signup-button', 'n_clicks'),
    prevent_initial_call=True,
)
def signup_user(name, email, password, user_store, n_clicks):
    if not all([name, email, password]):
        return no_update, no_update, no_update, no_update, no_update, no_update, no_update, no_update, no_update

    alert_open_email = False
    alert_open_password = False
    msg_email = ''
    msg_password = ''

    if '@gmail.com' in email or '@hotmail.com' in email:
        alert_open_email = True
        msg_email = 'Invalid email, Gmail and Hotmail not permitted'
        email_class = 'is-invalid'
    else:
        email_class = 'is-valid'

    if len(password) < 3:
        alert_open_password = True
        msg_password = 'Password too short'
        password_class = 'is-invalid'
    else:
        password_class = 'is-valid'

    if alert_open_email or alert_open_password:
        return alert_open_email, msg_email, email_class, alert_open_password, msg_password, password_class, no_update, no_update, no_update

    DB_PATH = os.path.join('pages/accounts/users.db')
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

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM users WHERE username = ?', (email,))
    if cursor.fetchone() is not None:
        conn.close()
        alert_open_email = True
        msg_email = 'Email already taken'
        return alert_open_email, msg_email, email_class, alert_open_password, msg_password, password_class, no_update, no_update, no_update

    hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    cursor.execute('INSERT INTO users (username, password) VALUES (?, ?)', (email, hashed_password.decode('utf-8')))
    conn.commit()
    conn.close()

    user_folder = os.path.join('pages/accounts', email)
    print(f"Created user directory: {user_folder}")
    os.makedirs(user_folder, exist_ok=True)

    defaults_folder = os.path.join(user_folder, 'defaults')
    os.makedirs(defaults_folder, exist_ok=True)

    template_folder = os.path.join('pages/accounts/Template')
    for item in os.listdir(template_folder):
        source_file = os.path.join(template_folder, item)
        shutil.copy(source_file, defaults_folder)

    user_data = {'username': email, 'logged_in': True}
    return False, '', '', False, '', '', user_data, {'display': 'block'}, '/management'


# Login user function
# Upon successful login, user redirected to /management
@callback(
    Output('login-email-alert', 'is_open', allow_duplicate=True),
    Output('login-email-alert', 'children', allow_duplicate=True),
    Output('login-password-alert', 'is_open', allow_duplicate=True),
    Output('login-password-alert', 'children', allow_duplicate=True),
    Output('user-store', 'data', allow_duplicate=True),  # Store user data
    Output('navbar', 'style', allow_duplicate=True),
    Output('url', 'href', allow_duplicate=True),  # Update the URL for redirection
    State('login-email', 'value'),
    State('login-password', 'value'),
    Input('login-button', 'n_clicks'),
    prevent_initial_call=True,
)
def login_user(email, password, n_clicks):
    if n_clicks is None or n_clicks == 0:
        return False, '', False, '', no_update, no_update, no_update  # No alerts and no redirection

    alert_open_email = False
    alert_open_password = False
    msg_email = ''
    msg_password = ''

    DB_PATH = os.path.join('pages/accounts/users.db')
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT password FROM users WHERE username = ?', (email,))
    user = cursor.fetchone()

    if user is None:
        alert_open_email = True
        msg_email = 'Username not found'
    elif password is None or password == '':
        alert_open_password = True
        msg_password = 'Please enter a password'
    elif not bcrypt.checkpw(password.encode('utf-8'), user[0].encode('utf-8')):
        alert_open_password = True
        msg_password = 'Invalid password'
    else:
        # Successfully logged in
        user_folder = os.path.join('pages/accounts', email)
        projects = []

        if os.path.exists(user_folder):
            projects = [f for f in os.listdir(user_folder) if os.path.isdir(os.path.join(user_folder, f))]

        # Store user data here if needed (using dcc.Store or session management)
        user_data = {'username': email, 'logged_in': True}

        # Return the redirection to '/management'
        return False, '', False, '', user_data, {'display': 'block'}, '/management'

    conn.close()
    return alert_open_email, msg_email, alert_open_password, msg_password, no_update, no_update, no_update  # No redirection if login fails
