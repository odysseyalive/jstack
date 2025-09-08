<?php
/**
 * Health Check Script for LAMP WebApp Template
 * COMPASS Stack Site Template System
 */

header('Content-Type: application/json');
header('Cache-Control: no-cache, no-store, must-revalidate');

$health = [
    'status' => 'ok',
    'timestamp' => date('c'),
    'checks' => []
];

try {
    // Check PHP version
    $health['checks']['php'] = [
        'status' => 'ok',
        'version' => PHP_VERSION,
        'message' => 'PHP is running'
    ];

    // Check database connection if configured
    if (isset($_ENV['DB_HOST']) && isset($_ENV['DB_NAME'])) {
        try {
            $dsn = "mysql:host={$_ENV['DB_HOST']};dbname={$_ENV['DB_NAME']};charset=utf8mb4";
            $pdo = new PDO(
                $dsn,
                $_ENV['DB_USER'] ?? 'webuser',
                $_ENV['DB_PASS'] ?? '',
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_TIMEOUT => 5
                ]
            );
            
            $stmt = $pdo->query('SELECT 1');
            $health['checks']['database'] = [
                'status' => 'ok',
                'message' => 'Database connection successful'
            ];
        } catch (PDOException $e) {
            $health['checks']['database'] = [
                'status' => 'error',
                'message' => 'Database connection failed: ' . $e->getMessage()
            ];
            $health['status'] = 'degraded';
        }
    } else {
        $health['checks']['database'] = [
            'status' => 'skipped',
            'message' => 'Database not configured'
        ];
    }

    // Check file system permissions
    $testFile = sys_get_temp_dir() . '/health_check_' . uniqid();
    if (file_put_contents($testFile, 'test') !== false) {
        unlink($testFile);
        $health['checks']['filesystem'] = [
            'status' => 'ok',
            'message' => 'File system writable'
        ];
    } else {
        $health['checks']['filesystem'] = [
            'status' => 'error',
            'message' => 'File system not writable'
        ];
        $health['status'] = 'degraded';
    }

    // Check memory usage
    $memoryUsage = memory_get_usage(true);
    $memoryLimit = ini_get('memory_limit');
    
    if ($memoryLimit !== '-1') {
        $memoryLimitBytes = return_bytes($memoryLimit);
        $memoryPercent = ($memoryUsage / $memoryLimitBytes) * 100;
        
        if ($memoryPercent > 90) {
            $health['checks']['memory'] = [
                'status' => 'warning',
                'usage' => format_bytes($memoryUsage),
                'limit' => $memoryLimit,
                'percent' => round($memoryPercent, 2),
                'message' => 'High memory usage'
            ];
            $health['status'] = 'degraded';
        } else {
            $health['checks']['memory'] = [
                'status' => 'ok',
                'usage' => format_bytes($memoryUsage),
                'limit' => $memoryLimit,
                'percent' => round($memoryPercent, 2),
                'message' => 'Memory usage normal'
            ];
        }
    } else {
        $health['checks']['memory'] = [
            'status' => 'ok',
            'usage' => format_bytes($memoryUsage),
            'limit' => 'unlimited',
            'message' => 'Memory usage tracked'
        ];
    }

    // Overall status
    $errorCount = 0;
    $warningCount = 0;
    
    foreach ($health['checks'] as $check) {
        if ($check['status'] === 'error') $errorCount++;
        if ($check['status'] === 'warning') $warningCount++;
    }
    
    if ($errorCount > 0) {
        $health['status'] = 'unhealthy';
        http_response_code(503);
    } elseif ($warningCount > 0) {
        $health['status'] = 'degraded';
        http_response_code(200);
    } else {
        $health['status'] = 'healthy';
        http_response_code(200);
    }

} catch (Exception $e) {
    $health['status'] = 'error';
    $health['message'] = 'Health check failed: ' . $e->getMessage();
    http_response_code(500);
}

echo json_encode($health, JSON_PRETTY_PRINT);

// Helper functions
function return_bytes($size_str) {
    switch (substr($size_str, -1)) {
        case 'M': case 'm': return (int)$size_str * 1048576;
        case 'K': case 'k': return (int)$size_str * 1024;
        case 'G': case 'g': return (int)$size_str * 1073741824;
        default: return $size_str;
    }
}

function format_bytes($bytes, $precision = 2) {
    $units = array('B', 'KB', 'MB', 'GB', 'TB');
    
    for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
        $bytes /= 1024;
    }
    
    return round($bytes, $precision) . ' ' . $units[$i];
}
?>