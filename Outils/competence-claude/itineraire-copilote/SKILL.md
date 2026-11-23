---
name: itineraire-copilote
description: Prépare l'itinéraire d'une journée (ou d'une demi-journée) de voyage — étapes, horaires, planning, déplacements entre les étapes — puis le livre dans un fichier JSON que l'application Copilote importe en une seule étape « à placer » contenant toutes les sous-étapes et leurs transports. À utiliser dès que l'utilisateur demande un itinéraire, un programme, un planning ou « que faire » sur une journée dans une ville ou une région, ou parle de l'importer dans Copilote.
---

# Itinéraire de la journée pour Copilote

Tu prépares une journée de voyage concrète et réaliste, tu la présentes lisiblement, puis tu la livres au **format Copilote** pour que l'utilisateur l'importe dans son application (bouton **« Itinéraire de Claude »** du cadre **« Étapes à placer »**). Dans l'app, tout l'itinéraire devient **une seule étape** (le titre de la journée) dont **tes étapes sont les sous-étapes**, reliées par les transports que tu as trouvés. L'utilisateur la glisse ensuite du doigt sur le jour voulu.

## 1. Comprendre la demande

Repère dans le message : le lieu (ville, quartier, région), la date, le point de départ (hôtel ?), l'heure de début et de fin, les centres d'intérêt, le rythme, qui voyage (enfants, mobilité), les moyens de transport souhaités (à pied, voiture, transports en commun) et le budget.

- Pose **au plus une question groupée**, et seulement si un élément manque vraiment (le lieu, en général). Sinon, choisis des valeurs raisonnables et dis-les en une ligne (« Je pars de 9 h, à pied et en métro, retour vers 18 h »).
- Si la date est connue, tiens-en compte : jour de fermeture, jours fériés, saison, heure du coucher du soleil.

## 2. Chercher (recherche web si disponible)

Vérifie plutôt que de supposer, pour chaque étape retenue :
- l'**adresse exacte** et les **coordonnées** (latitude, longitude en degrés décimaux, 5 décimales) — vérifie qu'elles tombent bien dans la bonne ville ;
- les **horaires d'ouverture** du jour visé et les jours de fermeture ;
- les **prix d'entrée** (adulte, enfant…) avec leur devise ;
- le **temps de visite** habituel ;
- les **trajets** entre deux étapes consécutives : mode le plus sensé, durée, ligne de métro/bus/train et arrêts quand c'est utile, prix du billet.

Si une information reste incertaine, ne l'invente pas : laisse le champ vide et signale-le dans `notes`.

## 3. Construire le planning

- Enchaîne les étapes dans un **ordre géographique logique** (pas d'allers-retours inutiles).
- Prévois des horaires réalistes : temps de visite + trajet + une marge de 10 à 15 min ; un déjeuner (12 h – 14 h) et, si la journée s'y prête, une pause ou un dîner.
- Vérifie que **chaque visite tombe dans les horaires d'ouverture**.
- 4 à 9 étapes en général ; moins pour une demi-journée ou avec des enfants.
- Les heures sont **locales au lieu visité**, au format `HH:mm`.
- Le transport d'une étape décrit le trajet **vers l'étape suivante**. La dernière étape n'a pas de transport.

## 4. Présenter

Dans la conversation, donne d'abord un résumé lisible :
- une phrase d'introduction (l'esprit de la journée) ;
- un tableau : heure · étape · durée · comment y aller ensuite ;
- 2 à 4 conseils pratiques (réservation conseillée, billet combiné, tenue, affluence…).

## 5. Livrer au format Copilote

Le format complet est décrit dans [references/format.md](references/format.md) ; un exemple complet est dans [exemples/kyoto.json](exemples/kyoto.json). L'essentiel :

```json
{
  "format": "copilote-itineraire",
  "version": 1,
  "titre": "Kyoto, temples de l'Est",
  "lieu": "Higashiyama, Kyoto, Japon",
  "date": "2026-12-03",
  "fuseau": "Asia/Tokyo",
  "resume": "Une journée à pied dans le vieux Kyoto…",
  "conseils": ["Arriver à Kiyomizu-dera avant 9 h pour éviter la foule."],
  "etapes": [
    {
      "titre": "Kiyomizu-dera",
      "adresse": "1-294 Kiyomizu, Higashiyama-ku, Kyoto",
      "latitude": 34.99485, "longitude": 135.78504,
      "categorie": "visite",
      "heure": "08:30", "heureFin": "09:45",
      "resume": "Temple sur pilotis, vue sur la ville.",
      "horaires": "6:00–18:00",
      "prix": { "adulte": 500, "enfant": 200, "devise": "JPY" },
      "transport": { "mode": "pied", "duree": 15, "distanceKm": 1.1, "notes": "Par Sannenzaka et Ninenzaka." }
    }
  ]
}
```

Règles :
- `format` vaut toujours `"copilote-itineraire"` et `version` vaut `1`.
- `categorie` : `visite`, `musee`, `repas`, `activite`, `hebergement` ou `autre`.
- `transport.mode` : `pied`, `velo`, `voiture`, `commun` (transports en commun), `avion` ou `bateau`. Précise le type dans `sousType` : `Train`, `Bus`, `Métro`, `Tram`, `Ferry`, `Taxi / VTC`, `Location`…
- Pour un train, un bus ou un bateau à heure fixe, donne `depart` et `arrivee` (`HH:mm`), la ligne dans `numero`, les arrêts dans `de` et `vers`.
- `duree` est en **minutes** ; `prix` est **par personne**, avec la `devise` en code ISO (EUR, JPY, USD…). Omets un prix que tu ne connais pas.
- Pas de champ à `null` ni de commentaire dans le JSON : omets ce qui est inconnu.

### Comment livrer

1. **Si tu peux créer des fichiers** (exécution de code) : écris `itineraire-<lieu>-<date>.json` (sans espaces ni accents dans le nom), vérifie-le avec `python3 scripts/verifier.py <fichier>`, corrige jusqu'à ce qu'il soit valide, puis présente le fichier.
2. **Dans tous les cas**, termine par le JSON complet dans un bloc de code ```json, pour qu'il puisse être copié depuis un téléphone.
3. Termine par cette consigne, en une ligne :
   > Dans Copilote : Itinéraire → Étapes à placer → **Itinéraire de Claude** → « Coller l'itinéraire copié » (ou « Ouvrir le fichier de Claude… »), puis glisse l'étape sur le jour voulu.

## Modifications

Si l'utilisateur demande un changement (« remplace le musée par un parc », « commence plus tard »), recalcule les horaires et les trajets touchés, puis redonne **tout** le JSON (l'app importe un itinéraire complet, pas un morceau).
