<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

require_once 'plugins.inc.d/homer.inc';

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'homer';
    protected static $internalModelClass = 'OPNsense\Homer\Homer';

    public function getAction()
    {
        $result = parent::getAction();

        if (!homer_caddy_is_present()) {
            $result['caddy_managed'] = false;
            return $result;
        }

        $result['caddy_managed'] = true;
        /** @var \OPNsense\Homer\Homer $mdl */
        $mdl = $this->getModel();
        $parsed = $mdl->getCaddyManagedConfig();

        foreach ($parsed as $key => $val) {
            if (!isset($result[static::$internalModelName]['general'][$key])) {
                continue;
            }

            if (is_array($result[static::$internalModelName]['general'][$key])) {
                foreach ($result[static::$internalModelName]['general'][$key] as $optKey => $optData) {
                    $result[static::$internalModelName]['general'][$key][$optKey]['selected'] = ($optKey === $val) ? 1 : 0;
                }
            } else {
                $result[static::$internalModelName]['general'][$key] = $val;
            }
        }

        return $result;
    }

    public function setAction()
    {
        if (homer_caddy_is_present()) {
            return array(
                'result' => 'failed',
                'message' => gettext('Settings are managed by Caddy Advanced via /usr/local/etc/caddy/conf.d/homer.caddy and cannot be modified from this form.'),
            );
        }

        if ($this->request->isPost()) {
            $post = $this->request->getPost(static::$internalModelName);
            $general = is_array($post) && isset($post['general']) ? $post['general'] : array();

            // Merge with the current model so partial updates validate against
            // the effective (already-stored) values of untouched fields.
            $mdl = $this->getModel();
            $tls = array_key_exists('TlsEnabled', $general)
                ? ((string)$general['TlsEnabled'] === '1' || $general['TlsEnabled'] === true)
                : (string)$mdl->general->TlsEnabled === '1';
            $interface = array_key_exists('Interface', $general)
                ? (string)$general['Interface']
                : (string)$mdl->general->Interface;
            $servername = array_key_exists('ServerName', $general)
                ? trim((string)$general['ServerName'])
                : trim((string)$mdl->general->ServerName);

            if ($tls && $interface !== 'all' && $servername === '') {
                return array(
                    'result' => 'failed',
                    'status' => 'failure',
                    'validations' => array(
                        // Key must match the form field's DOM id (dotted).
                        'homer.general.ServerName' => gettext('A Server name (hostname) is required when TLS is enabled and the dashboard does not listen on all interfaces.'),
                    ),
                );
            }
        }

        return parent::setAction();
    }
}
