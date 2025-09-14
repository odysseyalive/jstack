<?php
$dbuser = getenv('DBUSER');
$dbpass = getenv('DBPASS');
$mysqli = new mysqli('localhost', $dbuser, $dbpass, 'lampdb');
if ($mysqli->connect_error) {
    die('Connect Error (' . $mysqli->connect_errno . ') ' . $mysqli->connect_error);
}
$result = $mysqli->query('SELECT NOW() AS now');
$row = $result->fetch_assoc();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>LAMP + MariaDB Template</title>
</head>
<body>
    <h1>LAMP + MariaDB Docker Template</h1>
    <p>Credentials now loaded from environment variables for security.</p>
    <p>Current time from MariaDB: <strong><?php echo $row['now']; ?></strong></p>
    <p>If you see this page, your LAMP stack is running inside Docker!</p>
</body>
</html>
