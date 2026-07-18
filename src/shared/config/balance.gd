class_name Balance
## Constantes de barème et seuils tunables.
##
## TOUTES les valeurs ici sont des PLACEHOLDERS Phase 0, à régler au
## playtest (cf. DESIGN.md §10). Le serveur PHP maintient un miroir des
## plafonds de plausibilité (Validation.php) — garder les deux en phase.

## Seuil de score cumulé qui débloque le Phare (hypothèse à confirmer).
const LIGHTHOUSE_UNLOCK_THRESHOLD: int = 5000

## Plafond de plausibilité par épreuve : tout score au-delà est rejeté
## côté serveur (anti-triche léger). Valeurs volontairement larges.
const MAX_PLAUSIBLE_SCORE: Dictionary = {
	&"beach_run": 100_000,
	&"surf": 100_000,
	&"fishing": 100_000,
	&"rock_crossing": 100_000,
	&"espadrille": 100_000,
	&"lighthouse": 100_000,
}

## Durée par défaut d'une épreuve à temps limité, en secondes
## (chaque épreuve peut la surcharger via @export time_limit).
const DEFAULT_TIME_LIMIT: float = 60.0
