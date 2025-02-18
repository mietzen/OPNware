import os
import sys
import datetime
from pathlib import Path
import argparse
import fnmatch

HEADER = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Directory Listing</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 10px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f4f4f4;
        }
        a {
            text-decoration: none;
            color: #007bff;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
"""

FOOTER = """</body>
</html>"""

initial_base_directory = None

def readable_size(size):
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']:
        if size < 1024 or unit == 'PiB':
            if unit == 'B':
                return f"{size} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024

def should_exclude(path, exclude_patterns, include_dot):
    if not include_dot and any(part.startswith('.') for part in Path(path).parts):
        return True

    for pattern in exclude_patterns:
        if fnmatch.fnmatch(path, pattern):
            return True
    return False

def generate_index(directory, exclude_patterns, include_dot):
    files = []
    dirs = []

    for entry in sorted(os.scandir(directory), key=lambda e: e.name):
        if should_exclude(entry.path, exclude_patterns, include_dot):
            continue
        if entry.is_dir():
            dirs.append(entry)
        elif entry.is_file():
            files.append(entry)

    index_path = Path(directory) / "index.html"
    with open(index_path, "w") as f:
        f.write(HEADER)
        if directory == '.':
            f.write("<h1>Index of /</h1>")
        elif str(directory).startswith('.'):
            f.write(f"<h1>Index of {str(directory)[1:]}</h1>")
        else:
            f.write(f"<h1>Index of {str(directory)}</h1>")

        f.write("<table>")
        f.write("<tr><th>Name</th><th>Size</th><th>Creation Date (UTC)</th></tr>")

        if directory != initial_base_directory:
            f.write("<tr><td><a href='../index.html'>..</a></td><td>-</td><td>-</td></tr>")

        for d in dirs:
            f.write(f"<tr><td><a href='./{d.name}/index.html'>{d.name}/</a></td><td>-</td>")
            creation_time = datetime.datetime.fromtimestamp(d.stat().st_ctime).strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"<td>{creation_time}</td></tr>")

        for file in files:
            size = file.stat().st_size
            creation_time = datetime.datetime.fromtimestamp(file.stat().st_ctime).strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"<tr><td><a href='{file.name}'>{file.name}</a></td><td>{readable_size(size)}</td><td>{creation_time}</td></tr>")

        f.write("</table>")
        f.write(FOOTER)

def traverse_and_generate(base_dir, exclude_patterns, include_dot):
    for root, dirs, files in os.walk(base_dir):
        if should_exclude(root, exclude_patterns, include_dot):
            continue
        generate_index(root, exclude_patterns, include_dot)

def main():
    global initial_base_directory

    parser = argparse.ArgumentParser(description="Generate index.html files for directories.")
    parser.add_argument("directory", type=str, help="The base directory to start from.")
    parser.add_argument("--exclude", action="append", default=[], help="Glob patterns to exclude (can be used multiple times).")
    parser.add_argument("--include-dot", action="store_true", help="Include directories starting with a dot (e.g., .git, .svn).")
    parser.add_argument("--not-relative", action="store_true", help="Don't create a relative tree.")

    args = parser.parse_args()
    exclude_patterns = args.exclude
    include_dot = args.include_dot
    not_relative = args.not_relative

    if not os.path.isdir(args.directory):
        print(f"Error: {args.directory} is not a valid directory.")
        sys.exit(1)

    if not_relative:
        initial_base_directory = args.directory
    else:
        os.chdir(args.directory)
        initial_base_directory = '.'

    traverse_and_generate(initial_base_directory, exclude_patterns, include_dot)
    print("Index files generated successfully.")

if __name__ == "__main__":
    main()
