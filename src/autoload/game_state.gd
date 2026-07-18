extends Node
## GameState — session courante du joueur.
##
## Détient l'identité (pseudo + code de groupe), les jetons renvoyés par
## l'API (player_id / player_secret) et l'état de déblocage du Phare.
## STUB Phase 0 : API publique seulement, pas de logique métier.

## Pseudo choisi par le joueur (jamais de nom réel — cf. CLAUDE.md §0.6).
var pseudo: String = ""

## Code de groupe partageable (leaderboard privé).
var group_code: String = ""

## Identifiant joueur renvoyé par POST /api/group/join (0 = pas encore joint).
var player_id: int = 0

## Jeton secret par joueur, requis pour poster un score.
var player_secret: String = ""


## Enregistre l'identité de session (appelé depuis pseudo_entry).
func set_identity(p_pseudo: String, p_code: String) -> void:
	pseudo = p_pseudo
	group_code = p_code


## Le Phare est débloqué quand le cumul franchit Balance.LIGHTHOUSE_UNLOCK_THRESHOLD.
## STUB : la vraie logique arrivera avec ScoreManager (Phase 3).
func is_lighthouse_unlocked() -> bool:
	return false
