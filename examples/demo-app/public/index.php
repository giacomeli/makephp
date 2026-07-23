<?php

/**
 * makephp demo-app
 *
 * Pagina de status usada pelo make smoke para validar a stack de ponta a
 * ponta: PHP rodando (proxy ou php-fpm), extensoes carregadas e, quando as
 * envs estao presentes, conectividade com MariaDB e Redis.
 *
 * Sem dependencias de Composer de proposito: o exemplo valida infraestrutura.
 */

declare(strict_types=1);

function checkService(string $name, callable $probe): array
{
    try {
        return ['service' => $name, 'status' => $probe() ? 'ok' : 'fail'];
    } catch (Throwable $e) {
        return ['service' => $name, 'status' => 'fail', 'error' => $e->getMessage()];
    }
}

$extensions = [];
foreach (['pdo_mysql', 'redis', 'mongodb', 'amqp', 'apcu', 'imagick', 'intl', 'gd'] as $ext) {
    $extensions[$ext] = extension_loaded($ext);
}

$services = [];

$dbHost = getenv('DB_HOST');
if ($dbHost !== false && $dbHost !== '' && extension_loaded('pdo_mysql')) {
    $services[] = checkService('mariadb', function () use ($dbHost): bool {
        $pdo = new PDO(
            sprintf('mysql:host=%s;port=%s', $dbHost, getenv('DB_PORT') ?: '3306'),
            getenv('DB_USERNAME') ?: 'root',
            getenv('DB_PASSWORD') ?: '',
            [PDO::ATTR_TIMEOUT => 2, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );

        return $pdo->query('SELECT 1')->fetchColumn() === '1'
            || $pdo->query('SELECT 1')->fetchColumn() === 1;
    });
}

$redisHost = getenv('REDIS_HOST');
if ($redisHost !== false && $redisHost !== '' && extension_loaded('redis')) {
    $services[] = checkService('redis', function () use ($redisHost): bool {
        $redis = new Redis();
        $redis->connect($redisHost, (int) (getenv('REDIS_PORT') ?: 6379), 2.0);
        $password = getenv('REDIS_PASSWORD');
        if ($password !== false && $password !== '') {
            $redis->auth($password);
        }

        return $redis->ping() !== false;
    });
}

$payload = [
    'status' => 'ok',
    'app' => 'makephp demo-app',
    'php_version' => PHP_VERSION,
    'sapi' => PHP_SAPI,
    'extensions' => $extensions,
    'services' => $services,
];

if (($_GET['format'] ?? '') === 'json') {
    header('Content-Type: application/json');
    echo json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    exit;
}

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>makephp demo-app</title>
    <style>
        body { font-family: ui-monospace, Menlo, monospace; margin: 3rem auto; max-width: 40rem; padding: 0 1rem; }
        h1 { font-size: 1.3rem; }
        table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
        td, th { border: 1px solid #8884; padding: .4rem .6rem; text-align: left; }
        .ok { color: #2e7d32; } .fail { color: #c62828; }
    </style>
</head>
<body>
    <h1>makephp demo-app</h1>
    <p>PHP <?= htmlspecialchars(PHP_VERSION) ?> via <?= htmlspecialchars(PHP_SAPI) ?></p>
    <table>
        <tr><th>Extensao</th><th>Status</th></tr>
        <?php foreach ($extensions as $name => $loaded): ?>
        <tr>
            <td><?= htmlspecialchars($name) ?></td>
            <td class="<?= $loaded ? 'ok' : 'fail' ?>"><?= $loaded ? 'carregada' : 'ausente' ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
    <?php if ($services !== []): ?>
    <table>
        <tr><th>Servico</th><th>Status</th></tr>
        <?php foreach ($services as $svc): ?>
        <tr>
            <td><?= htmlspecialchars($svc['service']) ?></td>
            <td class="<?= $svc['status'] === 'ok' ? 'ok' : 'fail' ?>"><?= htmlspecialchars($svc['status']) ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
    <?php endif; ?>
    <p><a href="?format=json">ver como JSON</a></p>
</body>
</html>
