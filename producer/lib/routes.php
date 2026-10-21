<?php
declare(strict_types=1);

/**
 * Description des routes de l'API /producer, servie par GET routes (page Aide/API de
 * l'interface, `cli.py routes`). Tenir à jour avec App::dispatch().
 * Chaque route : méthode, nom, groupe, paramètres (query pour GET, corps JSON pour POST),
 * effet, et commande cli.py correspondante s'il y en a une.
 */
return [
    // --------------------------------------------------------------- session
    ['GET', 'session', 'Session', '', 'État de la session web et jeton CSRF (public).', ''],
    ['POST', 'login', 'Session', '{password}', 'Connexion par mot de passe (en-tête X-CSRF-Token requis).', ''],
    ['POST', 'logout', 'Session', '{}', 'Déconnexion.', ''],
    // ---------------------------------------------------------------- assets
    ['GET', 'index', 'Assets', '', 'Index des assets du build (assets, versions des fichiers, données Gordeka : persos, '
        . 'animations attendues, cartes de jeu, règles, liens assets ↔ cartes, file pixelforge).', ''],
    ['GET', 'index_version', 'Assets', '', 'Version légère de l\'index (date + taille), sondée pour le direct.', ''],
    ['GET', 'file', 'Assets', '&p=<chemin>[&v=<empreinte>]', 'Sert un fichier listé par l\'index (liste blanche, '
        . 'requêtes partielles).', ''],
    // ---------------------------------------------------- commentaires d'asset
    ['GET', 'comments', 'Commentaires', '&status=open|done, &asset=<id>', 'Commentaires d\'asset, avec outdated, '
        . 'current_version et card_id (carte où le commentaire a été reporté).', 'comments [--open] [--asset ID]'],
    ['POST', 'comment', 'Commentaires', '{asset, kind: amelioration|valide, body, context?}', 'Commentaire d\'asset '
        . 'seul (sans carte).', ''],
    ['POST', 'asset_comment', 'Commentaires', '{asset?, detail?, body, kind?, card?, title?, type?, parent?, context?}',
        'Commentaire depuis un asset : enregistré sur l\'asset (version servie) et reporté sur la carte liée '
        . '(card = id ; card = "new" : nouvelle carte ; sans card : la carte non terminée liée à l\'asset, sinon nouvelle '
        . 'carte en Backlog). Renvoie {comment, card, created}.',
        'asset-comment ASSET "texte" [--detail walk] [--card N]'],
    ['POST', 'comment_update', 'Commentaires', '{id, status?, reply?}', 'Répond à un commentaire ou change son statut.',
        'reply ID "texte" [--done] · close ID [--reopen]'],
    ['POST', 'comment_delete', 'Commentaires', '{id}', 'Supprime un commentaire.', ''],
    // ---------------------------------------------------------------- kanban
    ['GET', 'cards', 'Kanban', '&status=, &parent=, &night=1, &type=, &milestone=<id>|none, &asset=, &q=',
        'Cartes avec notes, children, children_done (QA + Done), status_at (entrée dans la colonne), milestone_id, due.',
        'cards [--status S] [--parent N] [--night] [--type T] [--milestone N|none] [--asset ID] [--search Q]'],
    ['GET', 'card', 'Kanban', '&id=N', '{card, children, events} : détail, enfants et historique.', 'show N'],
    ['GET', 'events', 'Kanban', '&since=<epoch>[&card=N]', 'Événements depuis since (1000 au plus) et now du serveur.',
        'events --since 15m [--card N]'],
    ['POST', 'card', 'Kanban', '{title, type?, description?, priority?, asset?, detail?, night?, status?, parent?, '
        . 'milestone?, due?}', 'Crée une carte (Backlog par défaut).', 'add-card --title … [--milestone N] [--due AAAA-MM-JJ]'],
    ['POST', 'card_update', 'Kanban', '{id, type?, title?, description?, priority?, asset?, detail?, night?, parent?, '
        . 'milestone? (0 = aucun), due? ("" = aucune)}', 'Modifie une carte ; chaque vrai changement est historisé.',
        'set N [--milestone N|0] [--due AAAA-MM-JJ|aucune] …'],
    ['POST', 'card_move', 'Kanban', '{id, status, index?}', 'Déplace une carte (review accepté pour qa).', 'move N doing'],
    ['POST', 'cards_bulk', 'Kanban', '{ids: [..], status?, night?, priority?, milestone?}', 'Même changement sur '
        . 'plusieurs cartes (500 au plus), dans une transaction.', 'bulk 4 5 6 [--status qa] [--night on] [--priority haute] [--milestone N]'],
    ['POST', 'card_comment', 'Kanban', '{id, body}', 'Commente une carte (alias card_note).', 'comment N "texte"'],
    ['POST', 'card_accept', 'Kanban', '{id}', 'QA → Done (descendants encore en QA compris) ; renvoie accepted.', ''],
    ['POST', 'card_refuse', 'Kanban', '{id, body}', 'QA → Doing, à retraiter, avec le commentaire de refus.', ''],
    ['POST', 'card_delete', 'Kanban', '{id}', 'Supprime une carte (enfants détachés).', ''],
    // ---------------------------------------------------------------- jalons
    ['GET', 'milestones', 'Roadmap', '', 'Jalons (ouverts d\'abord, puis position, échéance).', 'milestones'],
    ['POST', 'milestone', 'Roadmap', '{title, description?, due?}', 'Crée un jalon.', 'add-milestone --title … [--due …]'],
    ['POST', 'milestone_update', 'Roadmap', '{id, title?, description?, due?, closed?, position?}', 'Modifie un jalon.',
        'set-milestone N [--title …] [--due …] [--closed on|off]'],
    ['POST', 'milestone_delete', 'Roadmap', '{id}', 'Supprime un jalon ; ses cartes restent, sans jalon.', ''],
    ['GET', 'stats', 'Roadmap', '&stale_days=3', 'Tableau de bord : colonnes, feuilles, à retraiter, Doing immobiles, '
        . 'échéances dépassées, avancement des jalons, commentaires ouverts, activité 24 h.', 'stats'],
    ['GET', 'routes', 'Aide', '', 'Cette liste.', 'routes'],
];
