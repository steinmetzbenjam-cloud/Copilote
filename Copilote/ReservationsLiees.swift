import SwiftUI
import SwiftData

/// Ce à quoi une réservation peut être liée : une étape, un hébergement ou un transport (vol, train…).
/// Le lien est gardé dans la réservation sous forme de clé : « etape:UID », « transport:UID » (le transport qui part de l'étape UID),
/// « aller » ou « retour ».
enum LienReservation {
    static func etape(_ e: Etape) -> String { "etape:\(e.uid)" }
    static func transport(depart e: Etape) -> String { "transport:\(e.uid)" }
    static let aller = "aller"
    static let retour = "retour"
}

/// Une cible proposée dans le choix « Lier à » d'une réservation.
struct CibleReservation: Identifiable, Hashable {
    enum Groupe: String, CaseIterable { case hebergements = "Hébergements", transports = "Vols et transports", etapes = "Étapes" }
    let cle: String
    let libelle: String
    let symbole: String
    let groupe: Groupe
    var id: String { cle }
}

extension Voyage {
    /// Les réservations que le voyageur de cet appareil peut voir.
    var reservationsVisibles: [Reservation] {
        let moi = MoiVoyage.lire(self)
        return reservations.filter { $0.visible(pour: moi) }
    }

    /// Les réservations liées à une étape, un hébergement ou un transport (parmi celles que je peux voir).
    func reservations(lieesA cle: String) -> [Reservation] {
        reservationsVisibles.filter { $0.lien == cle }.sorted { $0.debut < $1.debut }
    }

    private func prefixeJour(_ e: Etape) -> String {
        guard let jour = e.jour, let i = jours.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: jour) }) else { return "" }
        return "Jour \(i + 1) · "
    }

    private func nom(_ e: Etape) -> String { e.titre.isEmpty ? e.categorie.libelle : e.titre }

    /// Tout ce à quoi une réservation peut être liée, dans l'ordre du voyage.
    var ciblesReservation: [CibleReservation] {
        var cibles: [CibleReservation] = []
        if let t = transportAller {
            cibles.append(CibleReservation(cle: LienReservation.aller, libelle: "Aller · \(t.descriptif(avecHoraires: false))", symbole: t.mode.symbole, groupe: .transports))
        }
        for e in elementsDuVoyage {
            if e.categorie == .hebergement {
                cibles.append(CibleReservation(cle: LienReservation.etape(e), libelle: prefixeJour(e) + nom(e), symbole: "bed.double.fill", groupe: .hebergements))
            } else {
                cibles.append(CibleReservation(cle: LienReservation.etape(e), libelle: prefixeJour(e) + nom(e), symbole: e.categorie.symbole, groupe: .etapes))
            }
            if let t = e.transport {
                let vers = suivante(de: e).map { " → \(nom($0))" } ?? ""
                cibles.append(CibleReservation(cle: LienReservation.transport(depart: e), libelle: prefixeJour(e) + "\(t.descriptif(avecHoraires: false)) · \(nom(e))\(vers)",
                                               symbole: t.mode.symbole, groupe: .transports))
            }
        }
        if let t = transportRetour {
            cibles.append(CibleReservation(cle: LienReservation.retour, libelle: "Retour · \(t.descriptif(avecHoraires: false))", symbole: t.mode.symbole, groupe: .transports))
        }
        return cibles
    }
}

extension Reservation {
    /// L'adresse Internet saisie, complétée par « https:// » si besoin.
    var urlSite: URL? {
        guard var texte = siteWeb?.trimmingCharacters(in: .whitespacesAndNewlines), !texte.isEmpty else { return nil }
        if !texte.contains("://") { texte = "https://" + texte }
        return URL(string: texte)
    }

    /// Réservée à certains voyageurs (les autres ne la voient pas dans l'app).
    var estRestreinte: Bool { !(visiblePour ?? []).isEmpty }

    /// Visible pour ce voyageur. Tant que l'appareil ne sait pas qui l'utilise, tout reste visible.
    func visible(pour moi: String) -> Bool {
        guard let liste = visiblePour, !liste.isEmpty, !moi.isEmpty else { return true }
        return liste.contains(moi)
    }

    /// Vrai si le lien mène à Booking.com.
    var estBooking: Bool {
        guard let hote = urlSite?.host?.lowercased() else { return false }
        return hote == "booking.com" || hote.hasSuffix(".booking.com")
    }
}

/// Le logo de Booking.com : un « B » blanc suivi d'un point bleu clair, sur un carré bleu foncé.
struct LogoBooking: View {
    var taille: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.22, style: .continuous)
                .fill(Color(rouge: 0x00, vert: 0x35, bleu: 0x80))
            HStack(alignment: .lastTextBaseline, spacing: taille * 0.02) {
                Text("B").font(.system(size: taille * 0.62, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Circle().fill(Color(rouge: 0x00, vert: 0x9F, bleu: 0xE3)).frame(width: taille * 0.17, height: taille * 0.17)
                    .offset(y: -taille * 0.04)
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityLabel("Booking.com")
    }
}

/// Dans la fiche d'une étape, d'un hébergement ou d'un transport : un bouton par réservation liée, qui en ouvre le détail.
struct BoutonsReservations: View {
    var voyage: Voyage
    var cle: String
    @Environment(\.modelContext) private var contexte
    @State private var ouverte: Reservation?

    var body: some View {
        ForEach(voyage.reservations(lieesA: cle)) { r in
            HStack(spacing: 10) {
                Button { ouverte = r } label: {
                    HStack(spacing: 10) {
                        Image(systemName: r.type.symbole).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.titre.isEmpty ? r.type.libelle : r.titre).font(.subheadline.weight(.semibold))
                            Text([r.fournisseur, r.numeroConfirmation.isEmpty ? "" : "N° \(r.numeroConfirmation)"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            // Plusieurs réservations pour un même élément : on voit pour qui est chacune.
                            if r.estRestreinte {
                                Label(voyage.membresTries.filter { r.visiblePour?.contains($0.uid) ?? false }.map(\.nom).joined(separator: ", "),
                                      systemImage: "person.2.fill")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if !r.documents.isEmpty { Label("\(r.documents.count)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                // Le lien Internet de la réservation (Booking.com, la compagnie…), ouvert dans le navigateur ou l'app du site.
                if let url = r.urlSite {
                    Link(destination: url) {
                        Group {
                            if r.estBooking {
                                HStack(spacing: 6) {
                                    LogoBooking(taille: 18)
                                    Text("Booking.com")
                                }
                            } else {
                                Label("Ouvrir", systemImage: "safari")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(url.absoluteString)
                }
            }
        }
        .sheet(item: $ouverte) { r in
            ReservationEditView(reservation: r, voyage: voyage) { contexte.delete(r) }
        }
    }
}
