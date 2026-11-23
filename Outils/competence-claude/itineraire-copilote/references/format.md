# Format « copilote-itineraire », version 1

Un fichier JSON encodé en UTF-8, un seul objet. L'application Copilote le transforme ainsi :

| Dans le fichier | Dans Copilote |
|---|---|
| l'objet racine | **une étape à placer** (sans jour), titre = `titre` |
| chaque élément de `etapes` | une **sous-étape** de cette étape, dans l'ordre du tableau |
| `etapes[i].transport` | le **transport** de la sous-étape *i* vers la sous-étape *i + 1* |

Les horaires de l'étape qui contient tout vont de la première heure de début à la dernière heure de fin ; sa position est `latitude`/`longitude` de la racine, sinon celle de la première sous-étape.

L'app est indulgente : les champs inconnus sont ignorés, une catégorie ou un mode inconnu prend une valeur par défaut, et un texte qui entoure le JSON (message complet, bloc de code) est accepté au collage. Mais vise un JSON exact.

## Racine

| Champ | Type | Obligatoire | Rôle |
|---|---|---|---|
| `format` | texte | oui | toujours `"copilote-itineraire"` |
| `version` | entier | oui | `1` |
| `titre` | texte | oui | nom de la journée, court : « Kyoto, temples de l'Est » |
| `lieu` | texte | non | ville / quartier / région |
| `date` | texte | non | `AAAA-MM-JJ`, le jour prévu (indicatif : l'utilisateur place l'étape lui-même) |
| `fuseau` | texte | non | identifiant IANA du fuseau du lieu (`Europe/Paris`, `Asia/Tokyo`) |
| `categorie` | texte | non | catégorie de l'étape qui contient tout (défaut `visite`) |
| `resume` | texte | non | l'esprit de la journée, 1 à 3 phrases (va dans les notes) |
| `notes` | texte | non | autres remarques (va dans les notes) |
| `conseils` | liste de textes | non | conseils pratiques (va dans les notes, en liste) |
| `latitude`, `longitude` | nombres | non | position de l'étape qui contient tout |
| `etapes` | liste | oui, ≥ 1 | les étapes de la journée, dans l'ordre |

## Étape (`etapes[i]`)

| Champ | Type | Obligatoire | Rôle |
|---|---|---|---|
| `titre` | texte | oui | nom du lieu : « Kiyomizu-dera » |
| `adresse` (ou `lieu`) | texte | conseillé | adresse postale ; sert aussi à retrouver la position dans Plans si les coordonnées manquent |
| `latitude`, `longitude` | nombres | conseillé | degrés décimaux, 5 décimales |
| `categorie` | texte | non | `visite`, `musee`, `repas`, `activite`, `hebergement`, `autre` |
| `heure` | texte | conseillé | début, `HH:mm`, heure locale |
| `heureFin` | texte | non | fin, `HH:mm` |
| `duree` | nombre | non | minutes sur place (sert si `heureFin` manque) |
| `resume` | texte | non | description courte du lieu |
| `horaires` | texte | non | horaires d'ouverture, lisibles : « 9:00–17:00, fermé le lundi » |
| `siteWeb` | texte | non | URL officielle |
| `notes` | texte | non | conseils propres à l'étape (réservation, entrée à utiliser…) |
| `prix` | objet Prix | non | prix d'entrée par personne |
| `transport` | objet Transport | non | trajet vers l'étape suivante ; absent pour la dernière |

## Transport

| Champ | Type | Rôle |
|---|---|---|
| `mode` | texte | `pied`, `velo`, `voiture`, `commun`, `avion`, `bateau` (acceptés aussi : `train`, `metro`, `bus`, `tram`, `taxi`, `ferry`) |
| `sousType` | texte | `Train`, `Bus`, `Métro`, `Tram`, `Ferry` (commun) ; `Taxi / VTC`, `Location`, `Voiture personnelle` (voiture) ; `Location`, `Libre-service` (vélo) |
| `compagnie` | texte | opérateur : « JR West », « RATP » |
| `numero` | texte | ligne ou numéro : « Ligne 1 », « Bus 206 » |
| `de`, `vers` | textes | arrêts, gares ou stations |
| `depart`, `arrivee` | textes | `HH:mm`, pour un trajet à horaire fixe |
| `duree` | nombre | minutes de trajet estimées |
| `distanceKm` | nombre | distance |
| `notes` | texte | précisions : sortie à prendre, correspondance, billet |
| `prix` | objet Prix | billet par personne |

À pied, à vélo, en voiture et en bateau, Copilote recalcule lui-même le trajet sur la carte ; ta durée reste dans les notes du transport. En transports en commun et en avion, ta durée sert d'estimation dans le Timing (sauf si `depart` et `arrivee` sont donnés).

## Prix

| Champ | Type | Rôle |
|---|---|---|
| `adulte`, `etudiant`, `adolescent`, `enfant` | nombres | prix par personne ; omets ceux qu'on ne connaît pas ; `0` pour gratuit |
| `devise` | texte | code ISO 4217 : `EUR` (défaut), `JPY`, `USD`… |

Un prix dans une devise que le voyage n'utilise pas est gardé en texte dans les notes.
