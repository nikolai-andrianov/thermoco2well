# Adapted from https://github.com/bradley-erickson/dash-blog-page
import dash
from dash import html, dcc
import dash_bootstrap_components as dbc
from datetime import date
import os
import frontmatter
import platform

# Need to specify the run folder for the production system
if platform.system() == 'Linux':
    cwd = '/var/www/FlaskDash'
elif platform.system() == 'Windows':
    cwd = '.'
else:
    raise Exception

file_path_in = os.path.join(cwd, 'pages', 'blog', 'articles')
date_format = '%B %#d, %G' if platform.system() == 'Windows' else '%B %-d, %G'


def create_article_card(post):
    '''Create clickable card to navigate to the article'''
    date_str = post.get('date').strftime(date_format)
    card = dbc.Card(
        html.A(
            [
                dbc.CardImg(src=f'{post.get("image")}', top=True),
                dbc.CardBody(
                    [
                        html.H4(
                            f'{post.get("title")}',
                            className='card-title'
                        ),
                        html.P(
                            f'{post.get("description")}',
                            className='card-text'
                        )
                    ]
                ),
                dbc.CardFooter(
                    f'{post.get("author")} - {date_str}',
                    class_name='mb-0'
                )
            ],
            href=post.get('permalink'),
            className='text-decoration-none text-body h-100 d-flex flex-column align-items-stretch'
        ),
        class_name='article-card h-100'
    )
    return card


def create_article_page(post):
    '''Create the layout of the article page'''
    date_str = post.get('date').strftime(date_format)

    image = post.get("image")
    layout = html.Div(
        dbc.Row(
            dbc.Col(
                [
                    html.Img(
                        src=f'{image}',
                        className='w-50'
                    ),
                    html.H1(f'{post.get("title")}'),
                    html.Hr(),
                    html.P(f'{post.get("author")} - {date_str}'),
                    html.Hr(),
                    dcc.Markdown(
                        post.content,
                        dangerously_allow_html=True,
                        className='markdown'
                    )
                ],
                lg=8,
                xl=6
            )
        ),
        className='mb-4'
    )
    return layout


# iterate over items in article page
article_cards = []
article_files = os.listdir(file_path_in)
article_files.sort()
article_files.reverse()  # reverse the list so the article show up properly

# A dictionary with the keys=permalink (defined in md posts), and value=layout of the post page
article_pages = {}

for article_name in article_files:
    # read in contents of a given article
    article_path = os.path.join(file_path_in, article_name)
    with open(article_path, 'r', encoding='utf-8') as f:
        post = frontmatter.load(f)

    publish_date = post.get('date')

    # skip articles that aren't published yet or are the sample files
    if publish_date > date.today() or article_name.startswith('sample'):
        continue

    # format image for proper sharing
    sharing_image = post.get('image').lstrip('/assets/')

    """
    # register the specific page for the article
    dash.register_page(
        post.get("title"),
        title=post.get("tab_title"),
        description=post.get("description"),
        image=sharing_image,
        path=post.get("permalink"),
        layout=create_article_page(post)
    )
    """
    
    # create the article card and add it to the list of cards
    article_cards.append(create_article_card(post))
    
    # Add the article page to the dict of pages
    article_pages[post.get("permalink")] = create_article_page(post) 


layout = html.Div()


dash.register_page(
    __name__,
    path='/blog',
)
