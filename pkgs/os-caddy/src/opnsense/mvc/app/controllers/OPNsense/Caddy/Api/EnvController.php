<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Caddy\Caddy;

/**
 * Envfile API for the plugin-owned caddy environment file.
 *
 * The envfile (settings general.EnvFile, default /usr/local/etc/caddy/env) is
 * a plain KEY=VALUE file consumed by caddy via --envfile. It is managed from
 * the editor page as a structured grid (variable name · value · secret
 * checkbox). It is NOT part of the flat file tree and never appears in any
 * config-display surface.
 *
 * Secret handling: the list endpoint never ships secret values — every row
 * except the plugin-owned CADDY_LOG_LEVEL comes back masked as '********'.
 * The real value of a single row is fetched on demand via revealEnvAction.
 * Because the envfile format has no place for a secret flag, every row
 * defaults to secret on load; the flag only controls masking in the UI.
 *
 * The plugin-owned CADDY_LOG_LEVEL row (written by setup.php on every
 * reconfigure) is exposed read-only: its real value is shown by the list
 * endpoint but it can neither be revealed nor edited nor deleted through the
 * grid, and the save cycle preserves its current value.
 */
class EnvController extends ApiControllerBase
{
    const DEFAULT_ENVFILE = '/usr/local/etc/caddy/env';
    const MASK = '********';
    const PLUGIN_ROW = 'CADDY_LOG_LEVEL';

    /**
     * The envfile path from the plugin settings (general.EnvFile).
     * @return string
     */
    private function envfilePath()
    {
        $mdl = new Caddy();
        $path = (string)$mdl->general->EnvFile;
        if ($path === '') {
            $path = self::DEFAULT_ENVFILE;
        }
        return $path;
    }

    /**
     * Parse the envfile into ordered rows. Only well-formed KEY=VALUE lines
     * with POSIX variable names are grid rows; blank and malformed lines are
     * skipped. Order is the file order; for duplicated names the last
     * occurrence wins on the value while the first occurrence keeps its
     * position (mirrors the serialization rule of saveEnvAction).
     *
     * @param string $envfile
     * @return array list of ['name' => string, 'value' => string]
     */
    private function readRows($envfile)
    {
        $rows = array();
        if (!is_file($envfile)) {
            return $rows;
        }
        $lines = file($envfile, FILE_IGNORE_NEW_LINES);
        if ($lines === false) {
            return $rows;
        }
        foreach ($lines as $line) {
            if (!preg_match('/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/', $line, $m)) {
                continue;
            }
            $name = $m[1];
            $value = $m[2];
            $found = false;
            foreach ($rows as &$row) {
                if ($row['name'] === $name) {
                    $row['value'] = $value;
                    $found = true;
                    break;
                }
            }
            unset($row);
            if (!$found) {
                $rows[] = array('name' => $name, 'value' => $value);
            }
        }
        return $rows;
    }

    /**
     * The grid rows: name, masked-or-real value, secret flag and read-only
     * marker. Secret values are always masked ('********'); only the
     * plugin-owned CADDY_LOG_LEVEL row is non-secret and it is shown
     * read-only with its real value. The plugin row is always present, even
     * before setup.php has written it.
     *
     * @return array
     */
    public function getEnvAction()
    {
        $envfile = $this->envfilePath();
        $rows = array();
        $pluginFound = false;
        foreach ($this->readRows($envfile) as $row) {
            $readonly = ($row['name'] === self::PLUGIN_ROW);
            $secret = !$readonly;
            if ($readonly) {
                $pluginFound = true;
            }
            $rows[] = array(
                'name' => $row['name'],
                'value' => $secret ? self::MASK : $row['value'],
                'secret' => $secret,
                'readonly' => $readonly,
            );
        }
        if (!$pluginFound) {
            array_unshift($rows, array(
                'name' => self::PLUGIN_ROW,
                'value' => '',
                'secret' => false,
                'readonly' => true,
            ));
        }
        return array('status' => 'ok', 'rows' => $rows);
    }

    /**
     * The real value of a single row. Only non-plugin rows can be revealed;
     * CADDY_LOG_LEVEL and unknown names are refused.
     *
     * @return array
     */
    public function revealEnvAction()
    {
        $name = $this->request->get('name');
        if (!is_string($name) || !preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $name)) {
            return array('status' => 'failure', 'message' => 'invalid variable name');
        }
        if ($name === self::PLUGIN_ROW) {
            return array('status' => 'failure', 'message' => self::PLUGIN_ROW . ' is plugin-managed');
        }
        $value = null;
        foreach ($this->readRows($this->envfilePath()) as $row) {
            if ($row['name'] === $name) {
                $value = $row['value'];
            }
        }
        if ($value === null) {
            return array('status' => 'failure', 'message' => 'variable not found');
        }
        return array('status' => 'ok', 'name' => $name, 'value' => $value);
    }

    /**
     * Validate and write the grid as KEY=VALUE lines, atomically.
     *
     * Every row is validated (POSIX variable name, value without newlines,
     * empty names rejected); any invalid row aborts the whole save with
     * per-row errors so the UI can surface them inline. Masked values
     * ('********') are preserved from the current file, so an un-revealed
     * secret is never overwritten with the mask literal. The plugin-owned
     * CADDY_LOG_LEVEL row is excluded from the grid; its current value is
     * preserved at the top of the written file.
     *
     * @return array
     */
    public function saveEnvAction()
    {
        $rows = $this->request->get('rows');
        if (!is_array($rows)) {
            return array('status' => 'failure', 'message' => 'missing rows');
        }

        $errors = array();
        $clean = array();
        foreach ($rows as $index => $row) {
            if (!is_array($row)) {
                $errors[] = array('index' => $index, 'error' => 'invalid row');
                continue;
            }
            $name = array_key_exists('name', $row) ? (string)$row['name'] : '';
            $value = array_key_exists('value', $row) ? (string)$row['value'] : '';
            if ($name === '') {
                $errors[] = array('index' => $index, 'error' => 'empty variable name');
                continue;
            }
            if ($name === self::PLUGIN_ROW) {
                $errors[] = array(
                    'index' => $index,
                    'error' => self::PLUGIN_ROW . ' is managed by the plugin',
                );
                continue;
            }
            if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $name)) {
                $errors[] = array(
                    'index' => $index,
                    'error' => 'invalid variable name (must start with a letter or underscore and contain only letters, digits and underscores)',
                );
                continue;
            }
            if (preg_match('/[\r\n]/', $value)) {
                $errors[] = array('index' => $index, 'error' => 'value must not contain newlines');
                continue;
            }
            $clean[] = array('name' => $name, 'value' => $value);
        }

        if (!empty($errors)) {
            return array(
                'status' => 'failure',
                'message' => 'environment rows are invalid',
                'errors' => $errors,
            );
        }

        $envfile = $this->envfilePath();
        $current = $this->readRows($envfile);
        $currentValue = array();
        foreach ($current as $row) {
            $currentValue[$row['name']] = $row['value'];
        }
        $pluginValue = array_key_exists(self::PLUGIN_ROW, $currentValue)
            ? $currentValue[self::PLUGIN_ROW]
            : '';

        // Serialize in list order; later duplicates win on the value while
        // the first occurrence keeps its position (PHP arrays are ordered).
        $map = array();
        foreach ($clean as $row) {
            $name = $row['name'];
            $value = $row['value'];
            if ($value === self::MASK && array_key_exists($name, $currentValue)) {
                // Preserve the un-revealed secret instead of the mask literal.
                $value = $currentValue[$name];
            }
            $map[$name] = $value;
        }

        $lines = array();
        if (array_key_exists(self::PLUGIN_ROW, $currentValue)) {
            $lines[] = self::PLUGIN_ROW . '=' . $pluginValue;
        }
        foreach ($map as $name => $value) {
            $lines[] = $name . '=' . $value;
        }
        $content = implode("\n", $lines) . "\n";

        if (!$this->writeAtomic($envfile, $content)) {
            return array('status' => 'failure', 'message' => 'cannot write ' . $envfile);
        }

        return array(
            'status' => 'ok',
            'message' => 'environment saved',
            'rows' => count($lines),
        );
    }

    /**
     * Atomic write: a temp file in the same directory with 0600 permissions,
     * then rename over the target. The directory is created when missing;
     * the target file is never truncated in place.
     *
     * @param string $envfile
     * @param string $content
     * @return bool
     */
    private function writeAtomic($envfile, $content)
    {
        $dir = dirname($envfile);
        if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
            return false;
        }
        $tmp = $dir . '/.env-' . uniqid() . '.tmp';
        $fh = @fopen($tmp, 'w');
        if ($fh === false) {
            return false;
        }
        if (fwrite($fh, $content) === false || !fflush($fh)) {
            fclose($fh);
            @unlink($tmp);
            return false;
        }
        if (!fclose($fh)) {
            @unlink($tmp);
            return false;
        }
        if (!chmod($tmp, 0600)) {
            @unlink($tmp);
            return false;
        }
        if (!rename($tmp, $envfile)) {
            @unlink($tmp);
            return false;
        }
        return true;
    }
}
