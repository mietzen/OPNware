<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'homer';
    protected static $internalModelClass = 'OPNsense\Homer\Homer';

    /**
     * Save settings with the TLS binding rule enforced: when TLS is enabled
     * the dashboard must either listen on all interfaces or carry a server
     * name (hostname) — the internal CA can only mint a certificate for a
     * hostname, never for a bare bound address. The incoming post data is
     * checked before the parent persists anything.
     * @return array
     */
    public function setAction()
    {
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
