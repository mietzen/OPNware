<?php

namespace OPNsense\Terminal\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Config;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\Terminal\Terminal';
    protected static $internalModelName = 'terminal';
    protected static $internalModelPath = 'general';



    public function setAction()
    {
        $result = parent::setAction();
        if (is_array($result) && ($result['result'] ?? '') === 'saved') {
            $this->syncUserShell();
        }
        return $result;
    }

    private function syncUserShell()
    {
        $model = $this->getModel();
        $defaultShell = (string)$model->general->default_shell;
        if (empty($defaultShell) || $defaultShell === 'auto') {
            return;
        }

        $shellMap = [
            'csh' => '/bin/csh',
            'sh' => '/bin/sh',
            'bash' => '/usr/local/bin/bash',
            'zsh' => '/usr/local/bin/zsh',
            'opnsense_menu' => '/usr/local/sbin/opnsense-shell',
        ];
        $targetShell = $shellMap[$defaultShell] ?? $defaultShell;

        $username = (string)$this->session->get('Username') ?: 'root';

        $config = Config::getInstance()->object();
        if (isset($config->system->user)) {
            foreach ($config->system->user as $user) {
                if ((string)$user->name === $username) {
                    $user->shell = $targetShell;
                    Config::getInstance()->save();
                    if (file_exists('/usr/local/etc/inc/auth.inc')) {
                        require_once('auth.inc');
                        $userArr = json_decode(json_encode($user), true);
                        local_user_set($userArr);
                    }
                    break;
                }
            }
        }
    }
}
