<?php
// Adds an API key to root, the way the GUI's "add API key" button does.
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';

use OPNsense\Core\Config;
use OPNsense\Auth\User;

Config::getInstance()->lock();
$model = new User();
$user = $model->getUserByName('root');
$pair = $user->apikeys->add();
$model->serializeToConfig(false, true);
Config::getInstance()->save();
echo json_encode($pair), "\n";
