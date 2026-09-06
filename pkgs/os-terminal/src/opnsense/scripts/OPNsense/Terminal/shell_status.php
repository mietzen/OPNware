<?php

header('Content-Type: application/json');

$shells = [
    'csh' => [
        'name' => 'csh',
        'display' => 'C Shell (/bin/csh)',
        'path' => '/bin/csh',
        'installed' => file_exists('/bin/csh') && is_executable('/bin/csh'),
        'pkg' => null
    ],
    'sh' => [
        'name' => 'sh',
        'display' => 'Bourne Shell (/bin/sh)',
        'path' => '/bin/sh',
        'installed' => file_exists('/bin/sh') && is_executable('/bin/sh'),
        'pkg' => null
    ],
    'bash' => [
        'name' => 'bash',
        'display' => 'Bourne Again Shell (/usr/local/bin/bash)',
        'path' => '/usr/local/bin/bash',
        'installed' => file_exists('/usr/local/bin/bash') && is_executable('/usr/local/bin/bash'),
        'pkg' => 'bash'
    ],
    'zsh' => [
        'name' => 'zsh',
        'display' => 'Z Shell (/usr/local/bin/zsh)',
        'path' => '/usr/local/bin/zsh',
        'installed' => file_exists('/usr/local/bin/zsh') && is_executable('/usr/local/bin/zsh'),
        'pkg' => 'zsh'
    ]
];

$result = [
    'status' => 'ok',
    'shells' => $shells
];

echo json_encode($result);
