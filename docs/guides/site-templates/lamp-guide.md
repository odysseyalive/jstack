# LAMP WebApp Template Guide

> Deploy modern PHP applications with Apache and MariaDB

## Overview

The LAMP WebApp template provides a production-ready foundation for:
- **Custom PHP applications** with database integration
- **Content Management Systems** (WordPress, Drupal, etc.)
- **E-commerce platforms** with shopping cart functionality
- **Web applications** requiring server-side processing

**Tech Stack**:
- PHP 8.2 with Apache
- MariaDB 10.11 database
- Modern PHP configuration
- Multi-container orchestration
- Automated database initialization

---

## Quick Deploy

```bash
# Deploy with defaults:
./jstack.sh --add-site myapp.com --template lamp-webapp

# Your app will be live at:
# https://myapp.com (with SSL automatically configured)
```

**Deploy time**: ~4 minutes

---

## Template Structure

```
templates/lamp-webapp/
├── site.json                 # Site configuration
├── docker-compose.yml        # Multi-container setup
├── web/                      # PHP application files
│   ├── index.php            # Main entry point
│   ├── config/              # Application configuration
│   ├── includes/            # Shared PHP includes
│   ├── assets/              # CSS, JS, images
│   └── vendor/              # Composer dependencies
├── database/                 # Database configuration
│   ├── init.sql             # Database schema
│   ├── data/                # Sample data
│   └── migrations/          # Schema migrations
├── config/                   # Server configuration
│   ├── php.ini              # PHP configuration
│   ├── apache.conf          # Apache virtual host
│   └── my.cnf               # MariaDB configuration
├── backups/                  # Database backup scripts
│   ├── backup.sh            # Backup script
│   └── restore.sh           # Restore script
├── logs/                     # Application logs
└── docs/                     # Template documentation
```

---

## Customization Guide

### 1. Basic Configuration (site.json)

```json
{
  "domain": "myapp.com",
  "template": "lamp-webapp",
  "app": {
    "name": "My Web Application",
    "environment": "production",
    "debug": false
  },
  "database": {
    "name": "myapp_db",
    "user": "myapp_user",
    "password": "auto-generated",
    "host": "database",
    "port": 3306
  },
  "php": {
    "version": "8.2",
    "memory_limit": "256M",
    "max_execution_time": 30,
    "upload_max_filesize": "10M"
  },
  "features": {
    "composer": true,
    "ssl": true,
    "backups": true
  }
}
```

### 2. PHP Application Structure

**Main Entry Point** (`web/index.php`):
```php
<?php
require_once 'config/config.php';
require_once 'includes/database.php';
require_once 'includes/functions.php';

// Initialize database connection
$db = new Database();
$conn = $db->getConnection();

// Simple routing
$page = $_GET['page'] ?? 'home';

switch ($page) {
    case 'home':
        include 'pages/home.php';
        break;
    case 'about':
        include 'pages/about.php';
        break;
    case 'contact':
        include 'pages/contact.php';
        break;
    default:
        include 'pages/404.php';
}
?>
```

**Configuration** (`web/config/config.php`):
```php
<?php
// Database configuration
define('DB_HOST', getenv('DATABASE_HOST') ?: 'database');
define('DB_NAME', getenv('DATABASE_NAME') ?: 'myapp_db');
define('DB_USER', getenv('DATABASE_USER') ?: 'myapp_user');
define('DB_PASS', getenv('DATABASE_PASSWORD') ?: '');

// Application settings
define('APP_NAME', getenv('APP_NAME') ?: 'My Web Application');
define('APP_URL', getenv('APP_URL') ?: 'https://myapp.com');
define('APP_ENV', getenv('APP_ENV') ?: 'production');

// Security settings
define('SESSION_TIMEOUT', 3600); // 1 hour
define('CSRF_TOKEN_EXPIRE', 7200); // 2 hours

// Start session with secure settings
session_start([
    'cookie_httponly' => true,
    'cookie_secure' => true,
    'cookie_samesite' => 'Strict'
]);
?>
```

**Database Class** (`web/includes/database.php`):
```php
<?php
class Database {
    private $host = DB_HOST;
    private $database = DB_NAME;
    private $username = DB_USER;
    private $password = DB_PASS;
    private $connection;

    public function getConnection() {
        $this->connection = null;

        try {
            $this->connection = new PDO(
                "mysql:host=" . $this->host . ";dbname=" . $this->database,
                $this->username,
                $this->password,
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_EMULATE_PREPARES => false,
                ]
            );
        } catch (PDOException $exception) {
            error_log("Connection error: " . $exception->getMessage());
            throw new Exception("Database connection failed");
        }

        return $this->connection;
    }
}
?>
```

### 3. Database Setup

**Schema Definition** (`database/init.sql`):
```sql
-- Create database tables
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL UNIQUE,
    content TEXT,
    author_id INT,
    status ENUM('draft', 'published') DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Create indexes for performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_posts_slug ON posts(slug);
CREATE INDEX idx_posts_status ON posts(status);
```

**Sample Data** (`database/data/sample.sql`):
```sql
-- Insert sample data
INSERT INTO users (username, email, password_hash) VALUES
('admin', 'admin@myapp.com', '$2y$10$example_hash_here'),
('editor', 'editor@myapp.com', '$2y$10$another_hash_here');

INSERT INTO posts (title, slug, content, author_id, status) VALUES
('Welcome Post', 'welcome-post', 'This is a sample welcome post.', 1, 'published'),
('About Us', 'about-us', 'Learn more about our company.', 1, 'published');
```

---

## Advanced PHP Features

### User Authentication

```php
<?php
// web/includes/auth.php
class Auth {
    private $db;

    public function __construct($database) {
        $this->db = $database;
    }

    public function login($email, $password) {
        $stmt = $this->db->prepare("SELECT id, password_hash FROM users WHERE email = ?");
        $stmt->execute([$email]);
        $user = $stmt->fetch();

        if ($user && password_verify($password, $user['password_hash'])) {
            $_SESSION['user_id'] = $user['id'];
            $_SESSION['user_email'] = $email;
            return true;
        }

        return false;
    }

    public function logout() {
        session_destroy();
        return true;
    }

    public function isAuthenticated() {
        return isset($_SESSION['user_id']);
    }

    public function requireAuth() {
        if (!$this->isAuthenticated()) {
            header('Location: /login.php');
            exit;
        }
    }
}
?>
```

### CSRF Protection

```php
<?php
// web/includes/csrf.php
class CSRF {
    public static function generateToken() {
        if (!isset($_SESSION['csrf_token'])) {
            $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
            $_SESSION['csrf_token_time'] = time();
        }
        return $_SESSION['csrf_token'];
    }

    public static function validateToken($token) {
        if (!isset($_SESSION['csrf_token']) || !isset($_SESSION['csrf_token_time'])) {
            return false;
        }

        // Check token age
        if (time() - $_SESSION['csrf_token_time'] > CSRF_TOKEN_EXPIRE) {
            unset($_SESSION['csrf_token'], $_SESSION['csrf_token_time']);
            return false;
        }

        return hash_equals($_SESSION['csrf_token'], $token);
    }
}
?>
```

### API Endpoints

```php
<?php
// web/api/posts.php
header('Content-Type: application/json');
require_once '../config/config.php';
require_once '../includes/database.php';

$db = new Database();
$conn = $db->getConnection();

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        $stmt = $conn->prepare("SELECT * FROM posts WHERE status = 'published' ORDER BY created_at DESC");
        $stmt->execute();
        $posts = $stmt->fetchAll();
        
        echo json_encode([
            'success' => true,
            'data' => $posts
        ]);
        break;

    case 'POST':
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!isset($input['title']) || !isset($input['content'])) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Missing required fields']);
            exit;
        }

        $slug = strtolower(trim(preg_replace('/[^A-Za-z0-9-]+/', '-', $input['title'])));
        
        $stmt = $conn->prepare("INSERT INTO posts (title, slug, content, author_id, status) VALUES (?, ?, ?, ?, 'published')");
        $stmt->execute([$input['title'], $slug, $input['content'], $_SESSION['user_id']]);
        
        echo json_encode([
            'success' => true,
            'id' => $conn->lastInsertId()
        ]);
        break;

    default:
        http_response_code(405);
        echo json_encode(['success' => false, 'error' => 'Method not allowed']);
}
?>
```

---

## Server Configuration

### PHP Configuration (`config/php.ini`)

```ini
; Security settings
expose_php = Off
display_errors = Off
log_errors = On
error_log = /var/log/php_errors.log

; Performance settings
memory_limit = 256M
max_execution_time = 30
max_input_time = 30

; File upload settings
file_uploads = On
upload_max_filesize = 10M
post_max_size = 10M
max_file_uploads = 20

; Session security
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = "Strict"

; Opcache settings
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 4000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
```

### Apache Configuration (`config/apache.conf`)

```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html
    ServerName myapp.com
    
    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # Hide Apache version
    ServerTokens Prod
    ServerSignature Off
    
    # Directory settings
    <Directory /var/www/html>
        Options -Indexes -FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Deny access to sensitive files
        <FilesMatch "^\.">
            Require all denied
        </FilesMatch>
        
        <FilesMatch "\.(sql|log|ini|conf)$">
            Require all denied
        </FilesMatch>
    </Directory>
    
    # Enable compression
    LoadModule deflate_module modules/mod_deflate.so
    <Location />
        SetOutputFilter DEFLATE
        SetEnvIfNoCase Request_URI \
            \.(?:gif|jpe?g|png|ico)$ no-gzip dont-vary
        SetEnvIfNoCase Request_URI \
            \.(?:exe|t?gz|zip|bz2|sit|rar)$ no-gzip dont-vary
    </Location>
    
    # Custom error pages
    ErrorDocument 404 /errors/404.php
    ErrorDocument 500 /errors/500.php
</VirtualHost>
```

### MariaDB Configuration (`config/my.cnf`)

```ini
[mysqld]
# Basic settings
port = 3306
socket = /var/run/mysqld/mysqld.sock
datadir = /var/lib/mysql

# Security settings
skip-name-resolve
local-infile = 0

# Performance settings
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Connection settings
max_connections = 100
connect_timeout = 10
wait_timeout = 300
interactive_timeout = 300

# Query cache
query_cache_type = 1
query_cache_size = 32M
query_cache_limit = 2M

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
log_queries_not_using_indexes = 1

[mysql]
default-character-set = utf8mb4

[client]
default-character-set = utf8mb4
```

---

## Docker Configuration

### Multi-Container Setup (`docker-compose.yml`)

```yaml
version: '3.8'

services:
  web:
    build: 
      context: .
      dockerfile: Dockerfile
    container_name: lamp-${DOMAIN//./-}
    restart: unless-stopped
    volumes:
      - ./web:/var/www/html:delegated
      - ./config/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro
      - ./config/apache.conf:/etc/apache2/sites-available/000-default.conf:ro
      - ./logs:/var/log/apache2
    environment:
      - DATABASE_HOST=database
      - DATABASE_NAME=${DB_NAME}
      - DATABASE_USER=${DB_USER}
      - DATABASE_PASSWORD=${DB_PASSWORD}
      - APP_URL=https://${DOMAIN}
      - APP_ENV=production
    depends_on:
      database:
        condition: service_healthy
    networks:
      - jarvis_private
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health.php"]
      interval: 30s
      timeout: 10s
      retries: 3

  database:
    image: mariadb:10.11
    container_name: lamp-db-${DOMAIN//./-}
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=${DB_NAME}
      - MYSQL_USER=${DB_USER}
      - MYSQL_PASSWORD=${DB_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
      - ./database/init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
      - ./database/data:/docker-entrypoint-initdb.d/02-data:ro
      - ./config/my.cnf:/etc/mysql/conf.d/custom.cnf:ro
      - ./backups:/backups
    networks:
      - jarvis_private
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  db_data:
    driver: local

networks:
  jarvis_private:
    external: true
```

### PHP Dockerfile

```dockerfile
FROM php:8.2-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    libicu-dev \
    libonig-dev \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        pdo \
        pdo_mysql \
        mysqli \
        zip \
        intl \
        mbstring \
        opcache

# Enable Apache modules
RUN a2enmod rewrite headers deflate

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY web/ .

# Install PHP dependencies if composer.json exists
RUN if [ -f composer.json ]; then composer install --no-dev --optimize-autoloader; fi

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Health check script
COPY <<EOF /usr/local/bin/health-check
#!/bin/bash
curl -f http://localhost/health.php || exit 1
EOF
RUN chmod +x /usr/local/bin/health-check

EXPOSE 80

CMD ["apache2-foreground"]
```

---

## Backup and Maintenance

### Automated Backup Script (`backups/backup.sh`)

```bash
#!/bin/bash

# Configuration
DB_CONTAINER="lamp-db-${DOMAIN//./-}"
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Database backup
echo "Creating database backup..."
docker exec "$DB_CONTAINER" mysqldump -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/db_backup_$DATE.sql"

# Web files backup
echo "Creating web files backup..."
tar -czf "$BACKUP_DIR/web_backup_$DATE.tar.gz" -C web/ .

# Clean old backups (keep last 7 days)
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

### Health Check Script (`web/health.php`)

```php
<?php
// Basic health check endpoint
header('Content-Type: application/json');

$health = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'checks' => []
];

// Check database connection
try {
    require_once 'includes/database.php';
    $db = new Database();
    $conn = $db->getConnection();
    $stmt = $conn->query('SELECT 1');
    $health['checks']['database'] = 'ok';
} catch (Exception $e) {
    $health['status'] = 'unhealthy';
    $health['checks']['database'] = 'error';
}

// Check disk space
$diskFree = disk_free_space('/var/www/html');
$diskTotal = disk_total_space('/var/www/html');
$diskUsage = ($diskTotal - $diskFree) / $diskTotal * 100;

if ($diskUsage > 90) {
    $health['status'] = 'warning';
    $health['checks']['disk'] = 'high_usage';
} else {
    $health['checks']['disk'] = 'ok';
}

// Set HTTP status code
if ($health['status'] === 'unhealthy') {
    http_response_code(503);
} elseif ($health['status'] === 'warning') {
    http_response_code(200);
}

echo json_encode($health, JSON_PRETTY_PRINT);
?>
```

---

## Security Best Practices

### Input Validation

```php
<?php
// web/includes/validator.php
class Validator {
    public static function email($email) {
        return filter_var($email, FILTER_VALIDATE_EMAIL);
    }
    
    public static function sanitizeString($string) {
        return htmlspecialchars(strip_tags(trim($string)), ENT_QUOTES, 'UTF-8');
    }
    
    public static function validateLength($string, $min = 1, $max = 255) {
        $length = mb_strlen($string);
        return $length >= $min && $length <= $max;
    }
    
    public static function alphanumeric($string) {
        return preg_match('/^[a-zA-Z0-9_-]+$/', $string);
    }
}
?>
```

### SQL Injection Prevention

```php
<?php
// Always use prepared statements
class PostRepository {
    private $db;
    
    public function __construct($database) {
        $this->db = $database;
    }
    
    public function findById($id) {
        $stmt = $this->db->prepare("SELECT * FROM posts WHERE id = ?");
        $stmt->execute([$id]);
        return $stmt->fetch();
    }
    
    public function create($data) {
        $stmt = $this->db->prepare("
            INSERT INTO posts (title, slug, content, author_id, status) 
            VALUES (?, ?, ?, ?, ?)
        ");
        return $stmt->execute([
            $data['title'],
            $data['slug'],
            $data['content'],
            $data['author_id'],
            $data['status']
        ]);
    }
}
?>
```

---

## Troubleshooting

### Common Issues

**Database connection fails**:
```bash
# Check database container status
docker ps | grep lamp-db

# Check database logs
docker logs lamp-db-myapp-com

# Test connection from web container
docker exec lamp-myapp-com php -r "
$pdo = new PDO('mysql:host=database;dbname=myapp_db', 'user', 'pass');
echo 'Connected successfully';
"
```

**PHP errors**:
```bash
# Check PHP error logs
docker logs lamp-myapp-com

# Check Apache error logs
tail -f logs/error.log

# Enable debug mode temporarily
# Edit site.json: "debug": true
```

**Performance issues**:
```bash
# Monitor resource usage
docker stats lamp-myapp-com lamp-db-myapp-com

# Check slow query log
docker exec lamp-db-myapp-com cat /var/log/mysql/slow.log

# Analyze database performance
docker exec lamp-db-myapp-com mysql -u root -p -e "SHOW PROCESSLIST;"
```

---

## WordPress Integration

### WordPress Deployment

```bash
# Download WordPress
cd templates/lamp-webapp/web/
curl -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz --strip-components=1
rm latest.tar.gz

# Configure WordPress
cp wp-config-sample.php wp-config.php
# Edit wp-config.php with database settings

# Deploy
./jstack.sh --add-site myblog.com --template ~/lamp-wordpress/
```

### Custom WordPress Configuration

```php
<?php
// wp-config.php additions
define('DB_HOST', getenv('DATABASE_HOST') ?: 'database');
define('DB_NAME', getenv('DATABASE_NAME') ?: 'wordpress_db');
define('DB_USER', getenv('DATABASE_USER') ?: 'wp_user');
define('DB_PASSWORD', getenv('DATABASE_PASSWORD') ?: '');

// Security keys (generate at https://api.wordpress.org/secret-key/1.1/salt/)
define('AUTH_KEY', getenv('WP_AUTH_KEY'));
define('SECURE_AUTH_KEY', getenv('WP_SECURE_AUTH_KEY'));
// ... other keys

// Security enhancements
define('DISALLOW_FILE_EDIT', true);
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
?>
```

---

## Next Steps

1. **🔒 [Security Hardening](../../reference/security.md#php-security)** - Advanced security measures
2. **⚡ [Performance Optimization](../../reference/performance.md#php-apps)** - Speed up your application
3. **📊 [Database Optimization](../database-tuning.md)** - Optimize MariaDB performance
4. **🔄 [CI/CD Setup](../../reference/cicd.md#php-deployment)** - Automated deployments
5. **📈 [Monitoring](../monitoring.md#lamp-stack)** - Application and database monitoring

**Need help?** Join the [AI Productivity Hub](https://www.skool.com/ai-productivity-hub) community!