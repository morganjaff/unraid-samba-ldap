<?php
// Active les modules Samba dans un lam.conf existant (JSON), sans toucher au reste.
// Usage : php lam-enable-samba.php <lam.conf> <base DN>
if ($argc < 3) { fwrite(STDERR, "usage: lam-enable-samba.php <lam.conf> <baseDN>\n"); exit(2); }
[$file, $base] = [$argv[1], $argv[2]];
$conf = json_decode(file_get_contents($file), true);
if (!is_array($conf)) { fwrite(STDERR, "lam.conf illisible\n"); exit(1); }

$conf['activeTypes'] = 'user,group,smbDomain';
$ts = $conf['typeSettings'] ?? [];
$ts['modules_user']  = 'inetOrgPerson,posixAccount,shadowAccount,sambaSamAccount';
$ts['modules_group'] = 'posixGroup,sambaGroupMapping';
$ts['suffix_smbDomain']      = $base;
$ts['attr_smbDomain']        = '#sambaDomainName;#sambaSID';
$ts['modules_smbDomain']     = 'sambaDomain,generalInformation';
$ts['customLabel_smbDomain'] = '';
$ts['filter_smbDomain']      = '';
$ts['hidden_smbDomain']      = false;
$conf['typeSettings'] = $ts;

// Secret propre à chaque installation (valeur par défaut identique pour tous sinon).
$conf['twoFactorRememberDevicePassword'] = bin2hex(random_bytes(16));

file_put_contents($file, json_encode($conf, JSON_PRETTY_PRINT));
echo "[lam-enable-samba] modules Samba activés dans $file\n";
