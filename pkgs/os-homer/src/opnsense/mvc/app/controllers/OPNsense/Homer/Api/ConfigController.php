<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

/**
 * Config API for the Homer dashboard's config.yml.
 *
 * getAction returns the current content of /usr/local/www/homer/config.yml
 * (empty content plus an `exists` flag when the file is missing, so the
 * editor can show a create-on-first-save notice).
 *
 * saveAction stages the submitted content and hands it to the configd
 * `homer config-save` action (script /usr/local/opnsense/scripts/OPNsense/
 * Homer/config_save.php), which YAML-parses and validates the content BEFORE
 * writing anything, then applies it atomically (temp + rename, mode 0644)
 * and never writes invalid YAML. The script persists its JSON result to the
 * status file first, so the controller can fall back to it when configd
 * reports "Execute error" on a non-zero exit. No service reload happens —
 * Homer re-reads config.yml in the browser.
 */
class ConfigController extends ApiControllerBase
{
    const CONFIG_FILE = '/usr/local/www/homer/config.yml';
    const STAGING_DIR = '/var/db/os-homer/config_staging';
    const STAGING_FILE = self::STAGING_DIR . '/config.yml';
    const STATUS_FILE = '/var/db/os-homer/config_status.json';

    /**
     * Content of the Homer config file. A missing file is reported with
     * `exists` = false and empty content (it will be created on first save).
     * @return array
     */
    public function getAction()
    {
        if (!is_file(self::CONFIG_FILE)) {
            return array('status' => 'ok', 'exists' => false, 'content' => '');
        }
        $content = file_get_contents(self::CONFIG_FILE);
        if ($content === false) {
            return array('status' => 'failure', 'message' => 'cannot read ' . self::CONFIG_FILE);
        }
        return array('status' => 'ok', 'exists' => true, 'content' => $content);
    }

    /**
     * Stage the submitted content and run the validated atomic save through
     * the configd `homer config-save` action. The result of the save script
     * (status, message, parser used, possible best-effort-validation warning)
     * is passed through to the WebUI.
     * @return array
     */
    public function saveAction()
    {
        $content = $this->request->get('content');
        if (!is_string($content)) {
            return array('status' => 'failure', 'message' => 'missing content');
        }

        // No-op save: the live file already holds exactly this content. Skip
        // the whole validate/apply cycle — a re-validation would just
        // re-report the same result (mirrors caddy-advanced's editor save).
        if (is_file(self::CONFIG_FILE) && file_get_contents(self::CONFIG_FILE) === $content) {
            $noop = array(
                'status' => 'ok',
                'message' => 'no changes to save',
                'parser' => 'none',
                'parser_warning' => false,
            );
            // Mirror the save script's status side effect so a status read
            // cannot contradict the just-shown result; ensure the state dir
            // exists like config_out() does.
            $statusDir = dirname(self::STATUS_FILE);
            if (!is_dir($statusDir)) {
                @mkdir($statusDir, 0755, true);
            }
            @file_put_contents(self::STATUS_FILE, json_encode($noop));
            return $noop;
        }

        if (!is_dir(self::STAGING_DIR) && !mkdir(self::STAGING_DIR, 0755, true)) {
            return array('status' => 'failure', 'message' => 'cannot create ' . self::STAGING_DIR);
        }

        $tmp = self::STAGING_FILE . '.tmp';
        if (file_put_contents($tmp, $content) === false) {
            return array('status' => 'failure', 'message' => 'cannot stage content');
        }
        if (!rename($tmp, self::STAGING_FILE)) {
            @unlink($tmp);
            return array('status' => 'failure', 'message' => 'cannot stage content');
        }

        // The configd action runs the save script against the staged file;
        // real saves are audited in configd.log (no-op saves above return
        // before reaching configd).
        $backend = new Backend();
        $result = $backend->configdRun('homer config-save');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            // configd reports 'Execute error' on non-zero exits and swallows
            // the script output — fall back to the status file for the real
            // error message the save script wrote.
            if (is_file(self::STATUS_FILE)) {
                $data = json_decode(file_get_contents(self::STATUS_FILE), true);
            }
            if (!is_array($data)) {
                return array('status' => 'failure', 'message' => trim($result));
            }
        }
        return $data;
    }
}
