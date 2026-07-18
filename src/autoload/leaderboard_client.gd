extends Node
## LeaderboardClient — appels HTTP à l'API PHP (async via HTTPRequest).
##
## Contrat d'API : CLAUDE.md §6.2. Toutes les méthodes sont asynchrones ;
## les résultats reviennent par signaux (au passé, cf. conventions §3).
## STUB Phase 0 : signatures et signaux seulement, aucun appel réseau.

## Émis après POST /api/group/join réussi.
signal group_joined(player_id: int, secret: String)

## Émis après POST /api/score réussi.
signal score_posted(challenge: StringName, best_score: int, cumulative: int)

## Émis après GET /api/leaderboard réussi. `entries` : Array[Dictionary]
## ({ pseudo, best_score } par épreuve, { pseudo, total } au cumul).
signal leaderboard_fetched(entries: Array[Dictionary])

## Émis quand une requête échoue (réseau ou erreur API).
signal request_failed(endpoint: String, code: int)

## URL de base de l'API, réglable par environnement (dev / prod).
@export var api_base_url: String = "/api"


## Rejoint un groupe avec un pseudo → group_joined(player_id, secret).
func join_group(_code: String, _pseudo: String) -> void:
	pass


## Poste un score (auth via GameState.player_secret) → score_posted(...).
func post_score(_challenge: StringName, _score: int) -> void:
	pass


## Récupère un classement. `challenge` vide → classement cumulé.
## → leaderboard_fetched(entries).
func fetch_leaderboard(_challenge: StringName = &"") -> void:
	pass
