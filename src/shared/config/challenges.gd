class_name Challenges
## Registre des épreuves : identifiants et métadonnées.
##
## Les identifiants StringName sont la clé canonique partout (scores,
## API, audio, routes). L'enum sert aux match/export dans l'éditeur.

## Les 6 lieux-épreuves de Biarritz (cf. DESIGN.md §3).
enum Id {
	BEACH_RUN,      ## Grande Plage — runner latéral
	SURF,           ## Côte des Basques — surf
	FISHING,        ## Port des Pêcheurs — pêche
	ROCK_CROSSING,  ## Rocher de la Vierge — traversée-timing
	ESPADRILLE,     ## Port Vieux — lancer d'espadrille
	LIGHTHOUSE,     ## Phare — ascension (débloquable au cumul)
}

## Identifiant canonique (StringName) par valeur d'enum.
const IDS: Dictionary = {
	Id.BEACH_RUN: &"beach_run",
	Id.SURF: &"surf",
	Id.FISHING: &"fishing",
	Id.ROCK_CROSSING: &"rock_crossing",
	Id.ESPADRILLE: &"espadrille",
	Id.LIGHTHOUSE: &"lighthouse",
}

## Les 5 épreuves cœur : leur somme des best = score cumulé,
## qui débloque le Phare (le Phare n'en fait pas partie).
const CORE: Array[StringName] = [
	&"beach_run",
	&"surf",
	&"fishing",
	&"rock_crossing",
	&"espadrille",
]
