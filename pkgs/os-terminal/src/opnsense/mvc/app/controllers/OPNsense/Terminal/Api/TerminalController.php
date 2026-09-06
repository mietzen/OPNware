<?php

namespace OPNsense\Terminal\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

class TerminalController extends ApiControllerBase
{
    public function shellStatusAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('terminal shell_status');
        $decoded = json_decode($response, true);
        if (is_array($decoded)) {
            return $decoded;
        }
        return ['status' => 'error', 'message' => 'Unable to fetch shell status'];
    }

    public function installShellAction()
    {
        if ($this->request->isPost()) {
            $shell = $this->request->getPost('shell', 'string', '');
            $backend = new Backend();
            if ($shell === 'bash') {
                $output = $backend->configdRun('terminal install_bash');
                return ['status' => 'ok', 'output' => $output];
            } elseif ($shell === 'zsh') {
                $output = $backend->configdRun('terminal install_zsh');
                return ['status' => 'ok', 'output' => $output];
            }
            return ['status' => 'error', 'message' => 'Invalid shell specified'];
        }
        return ['status' => 'error', 'message' => 'POST method required'];
    }
}
