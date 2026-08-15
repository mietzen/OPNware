<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

/**
 * Editor API for the user-owned Caddy file tree.
 *
 * The tree is flat by design: the import glob `conf.d/*.caddy` is
 * non-recursive, so only Caddyfile plus *.caddy files directly inside
 * conf.d exist. ACME storage, autosave, certs and keys are invisible. The
 * API never touches the live tree except through the configd editor-save
 * action (saveAction) or the plain add/delete operations on conf.d entries.
 */
class EditorController extends ApiControllerBase
{
    const BASE = '/usr/local/etc/caddy';
    const STAGING_DIR = '/var/db/os-caddy/editor_staging';
    const STATUS_FILE = '/var/db/os-caddy/editor_status.json';

    /**
     * Seeded Caddyfile: the plugin-managed log level env reference plus the
     * conf.d import glob. The file is user-owned after seeding.
     */
    const SEED = "{\n" .
        "    log {\n" .
        "        level {\$CADDY_LOG_LEVEL}\n" .
        "    }\n" .
        "}\n" .
        "\n" .
        "import conf.d/*.caddy\n";

    /**
     * Seed the user-owned Caddyfile on first access: create it with the
     * import line plus the log-level env reference, or append the import
     * line once when it is missing from an existing file. After that the
     * plugin never touches the file again.
     *
     * @return array|null failure array or null on success
     */
    private function seedIfMissing()
    {
        if (!is_dir(self::BASE) && !mkdir(self::BASE, 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create ' . self::BASE);
        }
        $confd = self::BASE . '/conf.d';
        if (!is_dir($confd) && !mkdir($confd, 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create ' . $confd);
        }

        $caddyfile = self::BASE . '/Caddyfile';
        if (!is_file($caddyfile)) {
            if (file_put_contents($caddyfile, self::SEED) === false) {
                return array('status' => 'failure', 'message' => 'cannot write ' . $caddyfile);
            }
            return null;
        }

        $content = file_get_contents($caddyfile);
        if ($content === false) {
            return array('status' => 'failure', 'message' => 'cannot read ' . $caddyfile);
        }
        if (preg_match('/^import conf\.d\/\*\.caddy$/m', $content)) {
            return null;
        }
        $content = rtrim($content, "\n") . "\n\nimport conf.d/*.caddy\n";
        if (file_put_contents($caddyfile, $content) === false) {
            return array('status' => 'failure', 'message' => 'cannot write ' . $caddyfile);
        }
        return null;
    }

    /**
     * Map a client-supplied path to a safe relative tree path. Accepts the
     * absolute tree paths returned by listAction() as well as their relative
     * forms. Rejects anything outside the flat tree, traversal ("..") and
     * any nesting.
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
        $name = null;
        if (preg_match('#^conf\.d/([A-Za-z0-9._-]+\.caddy)$#', $path, $m)) {
            $name = $m[1];
        } elseif (preg_match('#^' . preg_quote(self::BASE, '#') . '/conf\.d/([A-Za-z0-9._-]+\.caddy)$#', $path, $m)) {
            $name = $m[1];
        }
        if ($name === null || strpos($name, '/') !== false || $name === '.' || $name === '..') {
            return null;
        }
        return 'conf.d/' . $name;
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
     * The flat file tree: Caddyfile plus conf.d/*.caddy with name, absolute
     * path and existence flag.
     * @return array
     */
    public function listAction()
    {
        $seed = $this->seedIfMissing();
        if (is_array($seed)) {
            return $seed;
        }

        $files = array();
        $caddyfile = self::BASE . '/Caddyfile';
        $files[] = array(
            'name' => 'Caddyfile',
            'path' => $caddyfile,
            'exists' => is_file($caddyfile),
        );
        $glob = glob(self::BASE . '/conf.d/*.caddy');
        if ($glob !== false) {
            foreach ($glob as $file) {
                if (!is_file($file) || !$this->underBase($file)) {
                    continue;
                }
                $files[] = array(
                    'name' => basename($file),
                    'path' => $file,
                    'exists' => true,
                );
            }
        }
        return array('status' => 'ok', 'files' => $files);
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
        $result = $backend->configdRun('caddy editor-save');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            return array('status' => 'failure', 'message' => trim($result));
        }
        return $data;
    }

    /**
     * Create a new empty *.caddy file inside conf.d.
     * @return array
     */
    public function addAction()
    {
        $name = $this->request->get('name');
        if (!is_string($name) || !preg_match('/^[A-Za-z0-9._-]+\.caddy$/', $name)) {
            return array(
                'status' => 'failure',
                'message' => 'invalid file name (must be *.caddy inside conf.d)',
            );
        }
        $file = self::BASE . '/conf.d/' . $name;
        if (file_exists($file)) {
            return array('status' => 'failure', 'message' => 'file already exists');
        }
        if (!is_dir(self::BASE . '/conf.d') && !mkdir(self::BASE . '/conf.d', 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create conf.d');
        }
        if (file_put_contents($file, '') === false) {
            return array('status' => 'failure', 'message' => 'cannot create file');
        }
        return array('status' => 'ok', 'message' => 'created');
    }

    /**
     * Delete a conf.d/*.caddy file. Caddyfile itself is never deleted.
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
        $file = self::BASE . '/' . $rel;
        if (!$this->underBase($file)) {
            return array('status' => 'failure', 'message' => 'invalid path');
        }
        if (!is_file($file)) {
            return array('status' => 'failure', 'message' => 'file does not exist');
        }
        if (!unlink($file)) {
            return array('status' => 'failure', 'message' => 'cannot delete file');
        }
        return array('status' => 'ok', 'message' => 'deleted');
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
