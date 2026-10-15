<?php
declare(strict_types=1);

// Point d'entrée unique du service /producer (voir docs/PRODUCER.md).
require __DIR__ . '/lib/app.php';

(new App(__DIR__))->run();
