<?php

namespace OPNsense\CaddyAdvanced\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

require_once '/usr/local/opnsense/scripts/OPNsense/CaddyAdvanced/editor_tree.php';

/**
 * Editor API for the user-owned Caddy file tree.
 *
 * The tree is flat: Caddyfile plus conf.d/*.caddy (the import glob is
 * non-recursive). Mutations remain confined to managed .caddy files.
 */
class EditorController extends ApiControllerBase
{
    const BASE = '/usr/local/etc/caddy';
    const STAGING_DIR = '/var/db/os-caddy-advanced/editor_staging';
    const STATUS_FILE = '/var/db/os-caddy-advanced/editor_status.json';
    const STAGING_MARKER = self::STAGING_DIR . '/.complete';

    /**
     * Seed the user-owned Caddyfile on first access: create it with the
     * conf.d import, or migrate a legacy generated-import Caddyfile to the
     * flat glob. After that the plugin never touches the file again.
     *
     * @return array|null failure array or null on success
     */
    private function seedIfMissing()
    {
        $error = editor_tree_seed();
        return $error === null ? null : array('status' => 'failure', 'message' => $error);
    }

    /**
     * Map a client-supplied path to a safe relative tree path. Accepts the
     * absolute tree paths returned by listAction() as well as their relative
     * forms. Only managed flat .caddy paths are accepted.
     *
     * @param mixed $path
     * @return string|null
     */
    private function treeRelPath($path)
    {
        if (!is_string($path) || $path === '') {
            return null;
        }
        if ($path === 'Caddyfile' || $path === self::BASE . '/Caddyfile') {
            return 'Caddyfile';
        }
        $relative = str_starts_with($path, self::BASE . '/') ? substr($path, strlen(self::BASE) + 1) : $path;
        return editor_tree_rel_safe($relative) ? $relative : null;
    }

    /**
     * Whether $path resolves to a real location strictly under the tree base
     * (refuses symlink escapes).
     *
     * @param string $path
     * @return bool
     */
    private function underBase($path)
    {
        $real = realpath($path);
        if ($real === false) {
            return false;
        }
        $base = realpath(self::BASE);
        if ($base === false) {
            return false;
        }
        return strpos($real, $base . '/') === 0;
    }

    /**
     * Stage the whole current tree so the save cycle can validate it as one
     * set. The .complete marker tells the save script the staging area is a
     * full copy of the tree (so deletions apply); single-file saves drop the
     * marker so only the staged file is written.
     *
     * The staging dir is cleared first: a stale file from an aborted run
     * (failed validation, interrupted request) would otherwise join the next
     * staged tree and poison validation with phantom duplicates.
     *
     * @return string|null error message or null on success
     */
    private function prepareStaging()
    {
        if (!is_dir(self::STAGING_DIR)) {
            if (!mkdir(self::STAGING_DIR, 0755, true)) {
                return 'cannot create editor staging';
            }
        } else {
            $this->clearStaging();
        }
        foreach (editor_tree_walk_files() as $rel) {
            $target = self::STAGING_DIR . '/' . $rel;
            if (!is_dir(dirname($target)) && !mkdir(dirname($target), 0755, true)) {
                return 'cannot stage directory ' . dirname($target);
            }
            if (!copy(self::BASE . '/' . $rel, $target)) {
                return 'cannot stage ' . $rel;
            }
        }
        file_put_contents(self::STAGING_MARKER, '1');
        return null;
    }

    /**
     * Remove every entry under the staging dir (files, dirs, the marker).
     * @return void
     */
    private function clearStaging()
    {
        $items = scandir(self::STAGING_DIR);
        if ($items === false) {
            return;
        }
        foreach ($items as $item) {
            if ($item === '.' || $item === '..') {
                continue;
            }
            $path = self::STAGING_DIR . '/' . $item;
            if (is_dir($path) && !is_link($path)) {
                $this->clearStagingDir($path);
            } else {
                @unlink($path);
            }
        }
    }

    /**
     * Recursively remove a directory tree.
     * @param string $dir
     * @return void
     */
    private function clearStagingDir($dir)
    {
        $items = scandir($dir);
        if ($items === false) {
            return;
        }
        foreach ($items as $item) {
            if ($item === '.' || $item === '..') {
                continue;
            }
            $path = $dir . '/' . $item;
            if (is_dir($path) && !is_link($path)) {
                $this->clearStagingDir($path);
            } else {
                @unlink($path);
            }
        }
        @rmdir($dir);
    }

    /**
     * Run the configd editor-save cycle against the staged tree and return
     * its JSON contract, falling back to the status file on "Execute error".
     * @return array
     */
    private function runStagedSave()
    {
        $result = (new Backend())->configdRun('caddyadvanced editor-save');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            $data = is_file(self::STATUS_FILE) ? json_decode(file_get_contents(self::STATUS_FILE), true) : null;
        }
        return is_array($data) ? $data : array('status' => 'failure', 'message' => trim($result));
    }

    /**
     * The flat file tree: Caddyfile plus conf.d/*.caddy.
     * @return array
     */
    public function listAction()
    {
        $seed = $this->seedIfMissing();
        if (is_array($seed)) {
            return $seed;
        }

        $files = array();
        foreach (editor_tree_walk_files() as $relative) {
            $files[] = array('name' => basename($relative), 'path' => $relative, 'exists' => true);
        }
        return array(
            'status' => 'ok',
            'caddyfile' => array('name' => 'Caddyfile', 'path' => 'Caddyfile', 'editable' => true),
            'tree' => editor_tree_node(),
            'files' => $files,
        );
    }

    /**
     * Content of one tree file; runs seed-if-missing first.
     * @return array
     */
    public function getAction()
    {
        $seed = $this->seedIfMissing();
        if (is_array($seed)) {
            return $seed;
        }

        $rel = $this->treeRelPath($this->request->get('path'));
        if ($rel === null) {
            return array('status' => 'failure', 'message' => 'invalid path');
        }
        $file = self::BASE . '/' . $rel;
        if (!$this->underBase($file)) {
            return array('status' => 'failure', 'message' => 'invalid path');
        }
        if (!is_file($file)) {
            return array('status' => 'failure', 'message' => 'file does not exist');
        }
        $content = file_get_contents($file);
        if ($content === false) {
            return array('status' => 'failure', 'message' => 'cannot read file');
        }
        return array(
            'status' => 'ok',
            'name' => basename($file),
            'path' => $file,
            'content' => $content,
        );
    }

    /**
     * Stage the new content of one tree file, then run the configd
     * editor-save cycle (validate, snapshot, atomic apply, reload).
     * @return array
     */
    public function saveAction()
    {
        $seed = $this->seedIfMissing();
        if (is_array($seed)) {
            return $seed;
        }

        $rel = $this->treeRelPath($this->request->get('path'));
        if ($rel === null) {
            return array('status' => 'failure', 'message' => 'invalid path');
        }
        $content = $this->request->get('content');
        if (!is_string($content)) {
            return array('status' => 'failure', 'message' => 'missing content');
        }

        // No-op save: the file already holds exactly this content. Skip the
        // whole validate/snapshot/apply/reload cycle — a re-validation would
        // just re-report the same result, and when the file was renamed via
        // the tree a stale-path save would stage a phantom duplicate and
        // fail validation (e.g. "ambiguous site definition").
        $liveFile = self::BASE . '/' . $rel;
        if (is_file($liveFile) && file_get_contents($liveFile) === $content) {
            return array(
                'status' => 'ok',
                'result' => 'ok',
                'message' => 'no changes to save',
                'rollback' => false,
                'last_save' => time(),
            );
        }

        // Stage the content; the configd editor-save action applies it.
        $staged = self::STAGING_DIR . '/' . $rel;
        $stagedDir = dirname($staged);
        if (!is_dir($stagedDir) && !mkdir($stagedDir, 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create ' . $stagedDir);
        }
        $tmp = $staged . '.tmp';
        if (file_put_contents($tmp, $content) === false) {
            return array('status' => 'failure', 'message' => 'cannot stage content');
        }
        if (!rename($tmp, $staged)) {
            @unlink($tmp);
            return array('status' => 'failure', 'message' => 'cannot stage content');
        }

        $backend = new Backend();
        $result = $backend->configdRun('caddyadvanced editor-save');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            // configd reports 'Execute error' on non-zero exits and swallows
            // the script output — fall back to the status file for the real
            // error message the save cycle wrote.
            $status = self::STATUS_FILE;
            if (is_file($status)) {
                $data = json_decode(file_get_contents($status), true);
            }
            if (!is_array($data)) {
                return array('status' => 'failure', 'message' => trim($result));
            }
        }
        return $data;
    }

    /**
     * Create a new empty *.caddy file inside conf.d (staged, then saved).
     * @return array
     */
    public function addAction()
    {
        $target = $this->request->get('path');
        if (!is_string($target) || $target === '') {
            $target = 'conf.d/' . $this->request->get('name');
        }
        if (!editor_tree_rel_safe($target)) {
            return array(
                'status' => 'failure',
                'message' => 'invalid file name (must be a relative *.caddy path inside conf.d)',
            );
        }
        $error = $this->prepareStaging();
        if ($error !== null) {
            return array('status' => 'failure', 'message' => $error);
        }
        $staged = self::STAGING_DIR . '/' . $target;
        if (file_exists($staged)) {
            return array('status' => 'failure', 'message' => 'file already exists');
        }
        if (is_link(self::STAGING_DIR . '/conf.d')) {
            return array('status' => 'failure', 'message' => 'conf.d must not be a symlink');
        }
        if (!is_dir(dirname($staged)) && !mkdir(dirname($staged), 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create directory');
        }
        if (file_put_contents($staged, '') === false) {
            return array('status' => 'failure', 'message' => 'cannot create file');
        }
        return $this->runStagedSave();
    }

    /** Copy one conf.d file to another whitelisted conf.d filename. */
    public function copyAction()
    {
        return $this->copyOrMove(false);
    }

    /** Move one conf.d file to another whitelisted conf.d filename. */
    public function moveAction()
    {
        return $this->copyOrMove(true);
    }

    private function copyOrMove($move)
    {
        $source = $this->treeRelPath($this->request->get('path'));
        $target = $this->treeRelPath($this->request->get('target') ?: $this->request->get('name'));
        if ($source === null || $source === 'Caddyfile' || $target === null || $target === 'Caddyfile') {
            return array('status' => 'failure', 'message' => 'only conf.d/*.caddy files can be copied or moved');
        }

        $error = $this->prepareStaging();
        if ($error !== null) {
            return array('status' => 'failure', 'message' => $error);
        }
        $sourcePath = self::STAGING_DIR . '/' . $source;
        $targetPath = self::STAGING_DIR . '/' . $target;
        if (!is_file($sourcePath) || is_link(self::STAGING_DIR . '/conf.d')) {
            return array('status' => 'failure', 'message' => 'invalid or symlinked file tree');
        }
        if (file_exists($targetPath)) {
            return array('status' => 'failure', 'message' => 'target file already exists');
        }
        if (!is_dir(dirname($targetPath)) && !mkdir(dirname($targetPath), 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create target directory');
        }
        if ($move ? !rename($sourcePath, $targetPath) : !copy($sourcePath, $targetPath)) {
            return array('status' => 'failure', 'message' => $move ? 'cannot move file' : 'cannot copy file');
        }
        return $this->runStagedSave();
    }

    /**
     * Delete a conf.d/*.caddy file (staged, then saved). Caddyfile is never
     * deleted.
     * @return array
     */
    public function deleteAction()
    {
        $rel = $this->treeRelPath($this->request->get('path'));
        if ($rel === null) {
            return array('status' => 'failure', 'message' => 'invalid path');
        }
        if ($rel === 'Caddyfile') {
            return array('status' => 'failure', 'message' => 'Caddyfile cannot be deleted');
        }
        $error = $this->prepareStaging();
        if ($error !== null) {
            return array('status' => 'failure', 'message' => $error);
        }
        $staged = self::STAGING_DIR . '/' . $rel;
        if (!is_file($staged)) {
            return array('status' => 'failure', 'message' => 'file does not exist');
        }
        if (!unlink($staged)) {
            return array('status' => 'failure', 'message' => 'cannot delete file');
        }
        return $this->runStagedSave();
    }

    /**
     * Last save/reload result as written by the editor-save script.
     * @return array
     */
    public function statusAction()
    {
        $data = null;
        if (is_file(self::STATUS_FILE)) {
            $decoded = json_decode(file_get_contents(self::STATUS_FILE), true);
            if (is_array($decoded)) {
                $data = $decoded;
            }
        }
        if ($data === null) {
            $data = array(
                'last_save' => 0,
                'result' => 'none',
                'message' => 'no save yet',
            );
        }
        $data['status'] = 'ok';
        return $data;
    }
}
