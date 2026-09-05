<?php

/* Shared flat Caddy editor tree policy.
 *
 * The user-owned tree is exactly:
 *   /usr/local/etc/caddy/Caddyfile
 *   /usr/local/etc/caddy/conf.d/*.caddy
 *
 * The Caddyfile contains the single line `import conf.d/*.caddy`. Caddy's
 * import glob is non-recursive, so the tree is flat by construction — no
 * subdirectories, no generated import index.
 */

const EDITOR_TREE_BASE = '/usr/local/etc/caddy';
const EDITOR_TREE_ROOT = EDITOR_TREE_BASE . '/conf.d';

function editor_tree_name_safe($name)
{
    return is_string($name)
        && preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $name) === 1
        && $name !== '.'
        && $name !== '..'
        && strpos($name, "\0") === false;
}

/**
 * Safe relative path: "Caddyfile" or a single-component *.caddy file directly
 * inside "conf.d". Nested paths ("conf.d/sub/file.caddy") are rejected — the
 * import glob is non-recursive, so anything deeper would never be loaded.
 */
function editor_tree_rel_safe($rel)
{
    if (!is_string($rel) || $rel === '' || strpos($rel, "\0") !== false) {
        return false;
    }
    if ($rel === 'Caddyfile') {
        return true;
    }
    if (strpos($rel, 'conf.d/') !== 0 || strpos($rel, '/', 7) !== false) {
        return false;
    }
    $name = substr($rel, 7);
    return editor_tree_name_safe($name)
        && $name[0] !== '.'
        && substr($name, -6) === '.caddy';
}

function editor_tree_real_under($path, $base = EDITOR_TREE_BASE)
{
    $real = realpath($path);
    $root = realpath($base);
    return $real !== false && $root !== false
        && ($real === $root || strpos($real, $root . '/') === 0);
}

/**
 * Relative paths of the flat tree files under $base: Caddyfile plus
 * conf.d/*.caddy. Files only, no subdirectories.
 */
function editor_tree_walk_files($base = EDITOR_TREE_BASE)
{
    $files = array();
    if (is_file($base . '/Caddyfile')) {
        $files[] = 'Caddyfile';
    }
    $confd = $base . '/conf.d';
    if (is_dir($confd)) {
        foreach (scandir($confd) ?: array() as $name) {
            if ($name[0] === '.' || !editor_tree_name_safe($name)) {
                continue;
            }
            $rel = 'conf.d/' . $name;
            if (substr($name, -6) !== '.caddy' || !is_file($confd . '/' . $name)) {
                continue;
            }
            if (is_link($confd . '/' . $name)) {
                continue;
            }
            $files[] = $rel;
        }
    }
    sort($files, SORT_STRING);
    return $files;
}

/**
 * Tree node for the UI: the conf.d directory with its flat *.caddy files.
 */
function editor_tree_node($base = EDITOR_TREE_BASE)
{
    $node = array(
        'type' => 'directory',
        'name' => 'conf.d',
        'path' => 'conf.d',
        'children' => array(),
    );
    $confd = $base . '/conf.d';
    if (!is_dir($confd)) {
        return $node;
    }
    foreach (scandir($confd) ?: array() as $name) {
        if ($name[0] === '.' || !editor_tree_name_safe($name)) {
            continue;
        }
        $childAbsolute = $confd . '/' . $name;
        if (is_link($childAbsolute) || !is_file($childAbsolute)) {
            continue;
        }
        if (substr($name, -6) !== '.caddy') {
            continue;
        }
        $node['children'][] = array(
            'type' => 'file',
            'name' => $name,
            'path' => 'conf.d/' . $name,
            'editable' => true,
        );
    }
    usort($node['children'], function ($a, $b) {
        return strcmp($a['name'], $b['name']);
    });
    return $node;
}

function editor_tree_relative($path, $base = EDITOR_TREE_BASE)
{
    $root = rtrim(realpath($base) ?: $base, '/');
    $real = realpath($path);
    if ($real === false || ($real !== $root && strpos($real, $root . '/') !== 0)) {
        return null;
    }
    $rel = ltrim(substr($real, strlen($root)), '/');
    return $rel === '' ? null : $rel;
}

/**
 * Seed the user-owned tree on first access: create Caddyfile (with the
 * conf.d import) and conf.d when missing, and migrate a legacy
 * .opnware/imports.caddy Caddyfile to the flat glob.
 *
 * @return string|null error message or null on success
 */
function editor_tree_seed($base = EDITOR_TREE_BASE)
{
    if (!is_dir($base) && !mkdir($base, 0755, true)) {
        return 'cannot create ' . $base;
    }
    if (!is_dir($base . '/conf.d') && !mkdir($base . '/conf.d', 0755, true)) {
        return 'cannot create ' . $base . '/conf.d';
    }
    $caddyfile = $base . '/Caddyfile';
    $importPath = $base . '/conf.d/*.caddy';
    if (!is_file($caddyfile)) {
        $seedContent = "import " . $importPath . "\n";
        if (file_put_contents($caddyfile, $seedContent) === false) {
            return 'cannot create Caddyfile';
        }
        $exampleFile = $base . '/conf.d/example.caddy';
        if (!is_file($exampleFile)) {
            $exampleContent = "# Example site configuration on port 8080\n# Modify or delete this file in Services: Caddy Advanced: Editor\n\n:8080 {\n\trespond \"Hello from Caddy Advanced on OPNsense!\" 200\n}\n";
            file_put_contents($exampleFile, $exampleContent);
        }
        $envfile = $base . '/env';
        if (!is_file($envfile)) {
            touch($envfile);
            chmod($envfile, 0600);
        }
    } else {
        $content = file_get_contents($caddyfile);
        if ($content !== false && strpos($content, $importPath) === false) {
            // Replace relative import or legacy generated-import with the absolute glob.
            $migrated = preg_replace(
                '/^import (?:conf\.d\/\*\.caddy|\.opnware\/imports\.caddy)\s*$/m',
                'import ' . $importPath,
                $content,
                -1,
                $count
            );
            $content = $count > 0 ? $migrated : rtrim($content, "\n") . "\n\nimport " . $importPath . "\n";
            if (file_put_contents($caddyfile, $content) === false) {
                return 'cannot update Caddyfile import';
            }
        }
    }

    if (file_exists('/usr/local/opnsense/version/homer') && !is_file($base . '/conf.d/homer.caddy')) {
        @shell_exec('/usr/local/bin/php /usr/local/opnsense/scripts/OPNsense/Homer/sync_caddy.php >/dev/null 2>&1 || true');
    }

    return null;
}
