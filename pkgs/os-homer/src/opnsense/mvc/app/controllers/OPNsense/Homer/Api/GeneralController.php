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
     * hostname, never for a bare bound address.
     * @return array
     */
    public function setAction()
    {
        $result = parent::setAction();
        if (($result['result'] ?? '') !== 'saved') {
            return $result;
        }

        $general = $this->getModel()->general;
        $tls = (string)$general->TlsEnabled === '1';
        $interface = (string)$general->Interface;
        $servername = trim((string)$general->ServerName);

        if ($tls && $interface !== 'all' && $servername === '') {
            // Roll the model back so the invalid combination is not stored.
            $this->getModel()->rollback();
            return array(
                'result' => 'failed',
                'status' => 'failure',
                'message' => gettext('TLS requires listening on all interfaces or a Server name (hostname) when bound to a specific interface.'),
            );
        }

        return $result;
    }
}
