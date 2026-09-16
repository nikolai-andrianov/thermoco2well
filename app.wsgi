import sys

sys.path.insert(0, '/var/www/FlaskDash')

activate_this = '/var/www/FlaskDash/.venv/bin/activate_this.py'

with open(activate_this) as file_:
    exec(file_.read(), dict(__file__=activate_this))

from app import server as application

