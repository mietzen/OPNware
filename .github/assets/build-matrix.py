import os
import json
import yaml

def main():
    packages = []
    for root, _, files in os.walk("pkgs"):
        if "build_pkg.yml" in files:
            packages.append(os.path.basename(root))

    with open("config.yml", "r") as f:
        config = yaml.safe_load(f)

    includes = []
    for pkg in packages:
        config_path = os.path.join("pkgs", pkg, "config.yml")
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                pkg_config = yaml.safe_load(f)
            include = pkg_config["build_config"]["include"]
            include["pkg_name"] = pkg
            includes.append(include)

    matrix = {
        "pkg_name": packages,
        "arch": config["pkg-repo"]["arch"],
        "abi": config["pkg-repo"]["abi"],
        "include": includes,
    }

    print(json.dumps(matrix,separators=(',', ':')))

if __name__ == '__main__':
    main()