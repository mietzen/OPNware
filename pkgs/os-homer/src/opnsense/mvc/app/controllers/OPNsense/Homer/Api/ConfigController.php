<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiControllerBase;

/**
 * Config API for the Homer dashboard's config.yml.
 *
 * getAction returns the current content of /usr/local/www/homer/config.yml
 * (empty content plus an `exists` flag when the file is missing, so the
 * editor can show a create-on-first-save notice).
 *
 * saveAction stages the submitted content and hands it to the configd-style
 * save script /usr/local/opnsense/scripts/OPNsense/Homer/config_save.php,
 * which YAML-parses and validates the content BEFORE writing anything, then
 * applies it atomically (temp + rename, mode 0644) and never writes invalid
 * YAML. No service reload happens — Homer re-reads config.yml in the browser.
 */
class ConfigController extends ApiControllerBase
{
    const CONFIG_FILE = '/usr/local/www/homer/config.yml';
    const STAGING_DIR = '/var/db/os-homer/config_staging';
    const STAGING_FILE = self::STAGING_DIR . '/config.yml';
    const SAVE_SCRIPT = '/usr/local/opnsense/scripts/OPNsense/Homer/config_save.php';

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
     * Stage the submitted content and run the validated atomic save. The
     * result of the save script (status, message, parser used, possible
     * best-effort-validation warning) is passed through to the WebUI.
     * @return array
     */
    public function saveAction()
    {
        $content = $this->request->get('content');
        if (!is_string($content)) {
            return array('status' => 'failure', 'message' => 'missing content');
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

        // Both paths are internal constants; the staged file path is the only
        // argument, so no user input reaches the command line. The script is
        // invoked through the php interpreter explicitly.
        $cmd = escapeshellarg('/usr/local/bin/php')
            . ' ' . escapeshellarg(self::SAVE_SCRIPT)
            . ' ' . escapeshellarg(self::STAGING_FILE);
        exec($cmd . ' 2>&1', $output, $code);
        $data = json_decode(implode("\n", $output), true);
        if (!is_array($data)) {
            $message = trim(implode("\n", $output));
            return array(
                'status' => 'failure',
                'message' => $message !== '' ? $message : 'save script failed (exit ' . $code . ')',
            );
        }
        return $data;
    }
}
