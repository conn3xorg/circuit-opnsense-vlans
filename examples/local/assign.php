<?php
// Assigns a VLAN device to an interface, turns it on and gives it an
// address, as Interfaces > Assignments and the interface's own page do in
// the GUI. The provider can't do this part. Usage:
//   php assign.php opt2 vlan0.20 IOT 10.20.0.1 24
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';

use OPNsense\Core\Config;

[, $if, $dev, $descr, $ip, $bits] = $argv;
$config = Config::getInstance();
$config->lock();
$interfaces = $config->object()->interfaces;
if (!isset($interfaces->$if)) {
    $interfaces->addChild($if);
}
foreach (['if' => $dev, 'descr' => $descr, 'enable' => '1', 'ipaddr' => $ip, 'subnet' => $bits] as $key => $value) {
    $interfaces->$if->$key = $value;
}
$config->save();
