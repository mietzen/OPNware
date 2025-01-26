import os
from jinja2 import Environment, FileSystemLoader
import yaml

src_folder = os.environ.get('PKG_NAME')
workspace = os.environ.get('GITHUB_WORKSPACE')

config_path = os.path.join(
    workspace, "repo", "pkg-src", src_folder, "config.yml")
with open(config_path, "r") as f:
    pkg_config = yaml.safe_load(f)

if pkg_config['pkg_service']['template']:
    env = Environment(
        loader=FileSystemLoader(os.path.join(workspace, "repo", 'service_templates')))
    template = env.get_template(pkg_config['pkg_service']['template'] + ".jinja")
    service = template.render(
        pkg_config['pkg_service']['vars'] |
        {'NAME': pkg_config['pkg_manifest']['name']})
else:
    service = pkg_config['pkg_service']['service']

with open(f"{pkg_config['pkg_manifest']['name']}", 'w') as file:
    file.write(service)
