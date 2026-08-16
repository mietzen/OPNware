<?php

namespace OPNsense\Homer;

use OPNsense\Base\IndexController;
use OPNsense\Core\Config;

class GeneralController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Homer/general');

        // The Server name field's hint shows the box's real hostname (a
        // sensible value the user can copy) instead of a static example.
        $form = $this->getForm("general");
        $this->applyServerNameHint($form);
        $this->view->generalForm = $form;

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
     * Override the Server name field hint with the real system hostname
     * (config.xml → system.hostname), falling back to the static example
     * when unset.
     */
    private function applyServerNameHint(&$form)
    {
        $config = Config::getInstance()->object();
        $hostname = isset($config->system->hostname) ? (string)$config->system->hostname : '';
        $hint = $hostname !== '' ? $hostname : 'homer.lan';

        // Plain foreach (no `??`): a null-coalescing expression creates a
        // temporary that reference iteration would mutate without touching
        // the form array.
        if (!isset($form['tabs']) || !is_array($form['tabs'])) {
            return;
        }
        foreach ($form['tabs'] as &$tab) {
            foreach ($tab['sections'] as &$section) {
                foreach ($section['children'] as &$field) {
                    if (($field['id'] ?? '') === 'homer.general.ServerName') {
                        $field['hint'] = $hint;
                    }
                }
                unset($field);
            }
            unset($section);
        }
        unset($tab);
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
