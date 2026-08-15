<?php

/* Shared recursive Caddy editor tree policy. */

const EDITOR_TREE_BASE = '/usr/local/etc/caddy';
const EDITOR_TREE_ROOT = EDITOR_TREE_BASE . '/conf.d';
const EDITOR_TREE_INTERNAL = EDITOR_TREE_BASE . '/.opnware';
const EDITOR_TREE_IMPORTS = EDITOR_TREE_INTERNAL . '/imports.caddy';

function editor_tree_name_safe($name)
{
    return is_string($name)
        && preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $name) === 1
        && $name !== '.'
        && $name !== '..'
        && strpos($name, "\0") === false;
}

function editor_tree_rel_safe($rel, $allow_directory = false)
{
    if (!is_string($rel) || $rel === '' || $rel[0] === '/' || strpos($rel, "\0") !== false) {
        return false;
    }
    $parts = explode('/', $rel);
    if (count($parts) < 2 || $parts[0] !== 'conf.d') {
        return false;
    }
    array_shift($parts);
    foreach ($parts as $index => $part) {
        if (!editor_tree_name_safe($part) || $part[0] === '.') {
            return false;
        }
        if ($index === count($parts) - 1 && !$allow_directory
                && substr($part, -6) !== '.caddy') {
            return false;
        }
    }
    return true;
}

function editor_tree_real_under($path, $base = EDITOR_TREE_BASE)
{
    $real = realpath($path);
    $root = realpath($base);
    return $real !== false && $root !== false
        && ($real === $root || strpos($real, $root . '/') === 0);
}

function editor_tree_walk_files($base = EDITOR_TREE_BASE)
{
    $files = array();
    if (!is_dir($base)) {
        return $files;
    }
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iterator as $file) {
        if (!$file->isFile() || $file->isLink()) {
            continue;
        }
        $editor_rel = editor_tree_relative($file->getPathname(), $base);
        if ($editor_rel === null) {
            continue;
        }
        if ($editor_rel === 'Caddyfile' || editor_tree_rel_safe($editor_rel)) {
            $files[] = $editor_rel;
        }
    }
    sort($files, SORT_STRING);
    return $files;
}

function editor_tree_walk_dirs($base = EDITOR_TREE_BASE)
{
    $dirs = array();
    if (!is_dir($base)) {
        return $dirs;
    }
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST
    );
    foreach ($iterator as $dir) {
        if (!$dir->isDir() || $dir->isLink()) {
            continue;
        }
        $editor_rel = editor_tree_relative($dir->getPathname(), $base);
        if ($editor_rel === null) {
            continue;
        }
        if ($editor_rel !== 'conf.d' && editor_tree_rel_safe($editor_rel, true)) {
            $dirs[] = $editor_rel;
        }
    }
    sort($dirs, SORT_STRING);
    return $dirs;
}

function editor_tree_node($base = EDITOR_TREE_BASE, $relative = 'conf.d')
{
    $node = array('type' => 'directory', 'name' => basename($relative), 'path' => $relative, 'children' => array());
    $absolute = $base . '/' . $relative;
    if (!is_dir($absolute)) {
        return $node;
    }
    foreach (scandir($absolute) ?: array() as $name) {
        if ($name === '.' || $name === '..' || $name[0] === '.' || !editor_tree_name_safe($name)) {
            continue;
        }
        $childRelative = $relative . '/' . $name;
        $childAbsolute = $base . '/' . $childRelative;
        if (is_link($childAbsolute)) {
            continue;
        }
        if (is_dir($childAbsolute)) {
            $node['children'][] = editor_tree_node($base, $childRelative);
        } elseif (is_file($childAbsolute) && substr($name, -6) === '.caddy') {
            $node['children'][] = array('type' => 'file', 'name' => $name, 'path' => $childRelative, 'editable' => true);
        }
    }
    usort($node['children'], function ($a, $b) {
        return [$a['type'] === 'file', $a['name']] <=> [$b['type'] === 'file', $b['name']];
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

function editor_tree_import_content($base = EDITOR_TREE_BASE)
{
    $lines = array();
    foreach (editor_tree_walk_files($base) as $rel) {
        if ($rel === 'Caddyfile') {
            continue;
        }
        $lines[] = 'import ' . $rel;
    }
    return implode("\n", $lines) . (empty($lines) ? '' : "\n");
}

function editor_tree_seed($base = EDITOR_TREE_BASE)
{
    if (!is_dir($base) && !mkdir($base, 0755, true)) {
        return 'cannot create ' . $base;
    }
    if (!is_dir($base . '/conf.d') && !mkdir($base . '/conf.d', 0755, true)) {
        return 'cannot create ' . $base . '/conf.d';
    }
    $internal = $base . '/.opnware';
    if (!is_dir($internal) && !mkdir($internal, 0700, true)) {
        return 'cannot create ' . $internal;
    }
    $caddyfile = $base . '/Caddyfile';
    if (!is_file($caddyfile)) {
        $seed = "{\n    log {\n        level {\$CADDY_LOG_LEVEL}\n    }\n}\n\nimport .opnware/imports.caddy\n";
        if (file_put_contents($caddyfile, $seed) === false) {
            return 'cannot create Caddyfile';
        }
    } else {
        $content = file_get_contents($caddyfile);
        if ($content !== false && strpos($content, 'import .opnware/imports.caddy') === false) {
            $legacy = preg_replace('/^\s*import conf\.d\/\*\.caddy\s*$/m', 'import .opnware/imports.caddy', $content, -1, $count);
            $content = $count > 0 ? $legacy : rtrim($content, "\n") . "\n\nimport .opnware/imports.caddy\n";
            if (file_put_contents($caddyfile, $content) === false) {
                return 'cannot update Caddyfile import';
            }
        }
    }
    return editor_tree_write_imports($base);
}

function editor_tree_write_imports($base = EDITOR_TREE_BASE)
{
    $internal = $base . '/.opnware';
    $imports = $internal . '/imports.caddy';
    if (!is_dir($internal) && !mkdir($internal, 0700, true)) {
        return 'cannot create generated tree directory';
    }
    $tmp = $imports . '.tmp';
    if (file_put_contents($tmp, editor_tree_import_content($base)) === false || !rename($tmp, $imports)) {
        @unlink($tmp);
        return 'cannot write generated imports';
    }
    chmod($imports, 0600);
    return null;
}
