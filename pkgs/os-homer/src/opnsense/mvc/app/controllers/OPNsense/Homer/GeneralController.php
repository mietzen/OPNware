<?php

namespace OPNsense\Homer;

use OPNsense\Base\IndexController;
use OPNsense\Core\Config;

class GeneralController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Homer/general');
        $this->view->generalForm = $this->getForm("general");

        $model = new Homer();
        $port = (string)$model->general->Port;
        $interface = (string)$model->general->Interface;
        $tlsEnabled = (string)$model->general->TlsEnabled == '1';

        $lanIp = $this->resolveLanIp();
        $requestHost = $this->resolveRequestHost();

        $this->view->lanIp = $lanIp;
        $this->view->requestHost = $requestHost;
        $this->view->effectiveUrl = sprintf(
            '%s://%s:%s/',
            $tlsEnabled ? 'https' : 'http',
            $this->formatHost($this->resolveHost($interface, $lanIp, $requestHost)),
            $port
        );
    }

    /**
     * Format an address for use in a URL (IPv6 literals need brackets).
     */
    private function formatHost($host)
    {
        return strpos($host, ':') !== false ? '[' . $host . ']' : $host;
    }

    /**
     * Resolve the host shown for the "LAN IP" listen mode.
     */
    private function resolveLanIp()
    {
        $config = Config::getInstance()->object();
        if (isset($config->interfaces->lan->ipaddr)) {
            return (string)$config->interfaces->lan->ipaddr;
        }
        return '0.0.0.0';
    }

    /**
     * Resolve the host shown for the "All interfaces" listen mode from the
     * address the admin used to reach the WebUI (falls back to a hint).
     */
    private function resolveRequestHost()
    {
        if (isset($_SERVER['HTTP_HOST'])) {
            $host = preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST']);
            if (!empty($host)) {
                return $host;
            }
        }
        return '0.0.0.0';
    }

    /**
     * Map a listen mode to the address used in the effective URL.
     */
    private function resolveHost($interface, $lanIp, $requestHost)
    {
        switch ($interface) {
            case 'lan':
                return $lanIp;
            case 'localhost':
                return '127.0.0.1';
            case 'all':
            default:
                return $requestHost;
        }
    }
}
