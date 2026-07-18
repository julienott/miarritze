extends Node
## ScoreManager — source de vérité LOCALE des scores.
##
## Meilleurs scores locaux par épreuve, calcul du cumul (somme des best des
## 5 épreuves cœur, cf. Challenges.CORE), logique de déblocage du Phare.
## Pousse vers LeaderboardClient quand un nouveau best est établi
## (fait par ChallengeBase.end(), pas ici).
## STUB Phase 0 : API publique seulement, pas de persistance.

## Meilleur score local par épreuve (clé : StringName d'épreuve).
var _best_scores: Dictionary = {}


## Soumet un score local. Retourne true si c'est un nouveau meilleur score
## (l'appelant déclenche alors le post réseau via LeaderboardClient).
func submit_local(challenge: StringName, score: int) -> bool:
	var previous: int = best(challenge)
	if score <= previous:
		return false
	_best_scores[challenge] = score
	return true


## Meilleur score local pour une épreuve (0 si jamais jouée).
func best(challenge: StringName) -> int:
	return int(_best_scores.get(challenge, 0))


## Score cumulé = somme des best des 5 épreuves cœur (débloque le Phare).
func cumulative() -> int:
	var total: int = 0
	for challenge: StringName in Challenges.CORE:
		total += best(challenge)
	return total
