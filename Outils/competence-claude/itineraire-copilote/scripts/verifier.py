#!/usr/bin/env python3
"""Vérifie qu'un fichier JSON suit le format « copilote-itineraire » (version 1).

Usage : python3 verifier.py itineraire.json
Affiche les erreurs (le fichier sera refusé ou mal lu par Copilote) et les avertissements (à corriger si possible).
Code de sortie 0 si aucune erreur.
"""
import json
import re
import sys

CATEGORIES = {"visite", "musee", "repas", "activite", "hebergement", "autre"}
MODES = {"pied", "velo", "voiture", "commun", "avion", "bateau",
         "train", "metro", "bus", "tram", "taxi", "ferry"}
HEURE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
DEVISE = re.compile(r"^[A-Z]{3}$")


def minutes(h):
    return int(h[:2]) * 60 + int(h[3:])


def verifier(doc):
    erreurs, avertissements = [], []

    def texte(obj, cle, ou, obligatoire=False):
        v = obj.get(cle)
        if v is None:
            if obligatoire:
                erreurs.append(f"{ou} : « {cle} » manquant")
            return None
        if not isinstance(v, str):
            erreurs.append(f"{ou} : « {cle} » doit être un texte")
            return None
        if obligatoire and not v.strip():
            erreurs.append(f"{ou} : « {cle} » est vide")
        return v

    def nombre(obj, cle, ou):
        v = obj.get(cle)
        if v is not None and (isinstance(v, bool) or not isinstance(v, (int, float))):
            erreurs.append(f"{ou} : « {cle} » doit être un nombre (sans unité ni guillemets)")
            return None
        return v

    def heure(obj, cle, ou):
        v = texte(obj, cle, ou)
        if v is not None and not HEURE.match(v):
            erreurs.append(f"{ou} : « {cle} » = {v!r}, attendu HH:mm (ex. 09:30)")
            return None
        return v

    def prix(obj, ou):
        p = obj.get("prix")
        if p is None:
            return
        if not isinstance(p, dict):
            erreurs.append(f"{ou} : « prix » doit être un objet")
            return
        for cle in ("adulte", "etudiant", "adolescent", "enfant"):
            nombre(p, cle, f"{ou} › prix")
        d = texte(p, "devise", f"{ou} › prix")
        if d is not None and not DEVISE.match(d):
            erreurs.append(f"{ou} › prix : devise {d!r}, attendu un code ISO (EUR, JPY…)")

    def position(obj, ou, conseillee):
        la, lo = nombre(obj, "latitude", ou), nombre(obj, "longitude", ou)
        if (la is None) != (lo is None):
            erreurs.append(f"{ou} : latitude et longitude vont ensemble")
        elif la is None:
            if conseillee:
                avertissements.append(f"{ou} : pas de coordonnées (Copilote cherchera l'adresse dans Plans)")
        elif not (-90 <= la <= 90 and -180 <= lo <= 180) or (la == 0 and lo == 0):
            erreurs.append(f"{ou} : coordonnées impossibles ({la}, {lo})")
        return (la, lo) if la is not None and lo is not None else None

    if not isinstance(doc, dict):
        return ["la racine doit être un objet JSON"], []
    if doc.get("format") != "copilote-itineraire":
        erreurs.append("« format » doit valoir \"copilote-itineraire\"")
    if doc.get("version") != 1:
        erreurs.append("« version » doit valoir 1")
    texte(doc, "titre", "racine", obligatoire=True)
    for cle in ("lieu", "date", "fuseau", "categorie", "resume", "notes"):
        texte(doc, cle, "racine")
    if doc.get("date") and not re.match(r"^\d{4}-\d{2}-\d{2}$", doc["date"]):
        avertissements.append("racine : « date » attendue au format AAAA-MM-JJ")
    if doc.get("categorie") and doc["categorie"] not in CATEGORIES:
        avertissements.append(f"racine : catégorie {doc['categorie']!r} inconnue (→ visite)")
    conseils = doc.get("conseils")
    if conseils is not None and not (isinstance(conseils, list) and all(isinstance(c, str) for c in conseils)):
        erreurs.append("racine : « conseils » doit être une liste de textes")
    position(doc, "racine", False)

    etapes = doc.get("etapes")
    if not isinstance(etapes, list) or not etapes:
        erreurs.append("« etapes » doit être une liste non vide")
        return erreurs, avertissements

    precedente = None  # (titre, minute de fin estimée)
    positions = []
    for i, e in enumerate(etapes):
        ou = f"étape {i + 1}"
        if not isinstance(e, dict):
            erreurs.append(f"{ou} : doit être un objet")
            continue
        titre = texte(e, "titre", ou, obligatoire=True) or ou
        ou = f"étape {i + 1} ({titre})"
        texte(e, "lieu", ou)
        texte(e, "adresse", ou)
        for cle in ("resume", "horaires", "siteWeb", "notes"):
            texte(e, cle, ou)
        if not (e.get("adresse") or e.get("lieu")):
            avertissements.append(f"{ou} : pas d'adresse")
        cat = texte(e, "categorie", ou)
        if cat is not None and cat not in CATEGORIES:
            avertissements.append(f"{ou} : catégorie {cat!r} inconnue (→ visite)")
        pos = position(e, ou, True)
        if pos:
            positions.append((ou, pos))
        debut, fin = heure(e, "heure", ou), heure(e, "heureFin", ou)
        duree = nombre(e, "duree", ou)
        if debut is None:
            avertissements.append(f"{ou} : pas d'heure de début")
        if debut and fin and minutes(fin) <= minutes(debut):
            erreurs.append(f"{ou} : heureFin ({fin}) avant ou égale à heure ({debut})")
        if debut and precedente and precedente[1] is not None and minutes(debut) < precedente[1]:
            avertissements.append(f"{ou} : commence à {debut}, avant la fin estimée de « {precedente[0]} » et du trajet")
        prix(e, ou)

        t = e.get("transport")
        fin_estimee = None
        if debut:
            fin_estimee = minutes(fin) if fin else minutes(debut) + (duree or 0)
        if t is not None:
            if i == len(etapes) - 1:
                avertissements.append(f"{ou} : la dernière étape n'a pas besoin de transport (il sera ignoré)")
            if not isinstance(t, dict):
                erreurs.append(f"{ou} : « transport » doit être un objet")
            else:
                to = f"{ou} › transport"
                mode = texte(t, "mode", to)
                if mode is None:
                    avertissements.append(f"{to} : pas de mode (→ à pied)")
                elif mode not in MODES:
                    erreurs.append(f"{to} : mode {mode!r} inconnu ({', '.join(sorted(MODES))})")
                for cle in ("sousType", "compagnie", "numero", "de", "vers", "notes"):
                    texte(t, cle, to)
                dep, arr = heure(t, "depart", to), heure(t, "arrivee", to)
                d = nombre(t, "duree", to)
                nombre(t, "distanceKm", to)
                prix(t, to)
                if fin_estimee is not None:
                    fin_estimee += (minutes(arr) - minutes(dep)) if dep and arr else (d or 0)
        elif i < len(etapes) - 1:
            avertissements.append(f"{ou} : pas de transport vers l'étape suivante")
        precedente = (titre, fin_estimee)

    # Un point à plus de 300 km des autres : coordonnées probablement fausses.
    if len(positions) >= 3:
        lats = sorted(p[1][0] for p in positions)
        lons = sorted(p[1][1] for p in positions)
        med = (lats[len(lats) // 2], lons[len(lons) // 2])
        for ou, (la, lo) in positions:
            if abs(la - med[0]) > 3 or abs(lo - med[1]) > 3:
                avertissements.append(f"{ou} : très loin des autres étapes, vérifier les coordonnées")
    return erreurs, avertissements


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    try:
        with open(sys.argv[1], encoding="utf-8") as f:
            doc = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERREUR : JSON invalide — {e}")
        return 1
    erreurs, avertissements = verifier(doc)
    for e in erreurs:
        print(f"ERREUR : {e}")
    for a in avertissements:
        print(f"Avertissement : {a}")
    if not erreurs:
        n = len(doc["etapes"])
        print(f"OK : « {doc['titre']} », {n} étape{'s' if n > 1 else ''}, prêt pour Copilote.")
    return 1 if erreurs else 0


if __name__ == "__main__":
    sys.exit(main())
