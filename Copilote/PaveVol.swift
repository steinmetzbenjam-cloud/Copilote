import SwiftUI

/// Le transport d'aller (premier jour) ou de retour (dernier jour), en pavé : pour un vol, ce que l'on en sait en direct
/// (terminal, comptoirs, porte, tapis à bagages, horaires prévus et révisés, durée, avion), et une recherche Google du vol.
/// Affiché en tête du premier jour et en bas du dernier, dans l'Itinéraire et dans l'Aperçu.
struct PaveExtremite: View {
    let voyage: Voyage
    let extremite: TimingView.ExtremiteTransport
    /// Appui sur l'en-tête : ouvre la fiche du transport (nil : en-tête inerte).
    var onOuvrir: (() -> Void)? = nil
    private var vols = Vols.shared

    init(voyage: Voyage, extremite: TimingView.ExtremiteTransport, onOuvrir: (() -> Void)? = nil) {
        self.voyage = voyage
        self.extremite = extremite
        self.onOuvrir = onOuvrir
    }

    private var transport: Transport? { extremite == .aller ? voyage.transportAller : voyage.transportRetour }
    /// Le jour du vol : l'aller part le premier jour, le retour le dernier.
    private var jour: Date { (extremite == .aller ? voyage.jours.first : voyage.jours.last) ?? voyage.debut }
    private var numero: String { SourceVols.numeroNettoye(transport?.numero ?? "") }
    private var estUnVol: Bool { transport?.mode == .avion }
    private var aUneCle: Bool { Cles.lire(.aerodatabox) != nil }
    private let teinte = Color.indigo

    var body: some View {
        if let t = transport {
            VStack(alignment: .leading, spacing: 10) {
                enTete(t)
                if estUnVol { detailsDuVol }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(teinte.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(teinte.opacity(0.35), lineWidth: 1))
            .task(id: Vols.cle(numero, jour)) {
                guard estUnVol, !numero.isEmpty, aUneCle else { return }
                await vols.actualiser(numero, jour)
            }
        }
    }

    private func enTete(_ t: Transport) -> some View {
        Button { onOuvrir?() } label: {
            HStack(spacing: 10) {
                Image(systemName: t.mode.symbole).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Circle().fill(teinte))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(extremite == .aller ? "Aller" : "Retour") · \(t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelleCourt)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(teinte)
                    Text(t.descriptif).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if case .trouve(let infos)? = vols.etat(numero, jour), !infos.statut.isEmpty { pastille(infos.statut) }
                if onOuvrir != nil { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(teinte.opacity(0.6)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOuvrir == nil)
    }

    private func pastille(_ statut: String) -> some View {
        let alerte = ["Retardé", "Annulé", "Dérouté", "Annulation possible"].contains(statut)
        return Text(statut).font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((alerte ? Color.red : Color.green).opacity(0.16), in: Capsule())
            .foregroundStyle(alerte ? Color.red : Color.green)
    }

    @ViewBuilder private var detailsDuVol: some View {
        if numero.isEmpty {
            Text("Saisis le numéro du vol (AF 1234) dans la fiche du transport pour voir le terminal, la porte et le tapis à bagages.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            switch aUneCle ? vols.etat(numero, jour) : nil {
            case .trouve(let infos)?:
                infosDuVol(infos)
            case .enCours?:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Recherche du vol…") }
                    .font(.footnote).foregroundStyle(.secondary)
            case .introuvable?:
                Text("Aucun vol \(numero) trouvé le \(jour.formatted(.dateTime.day().month(.wide))) : vérifie le numéro, ou réessaie plus près du départ.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .erreur(let message)?:
                Text(message).font(.footnote).foregroundStyle(.orange)
            case nil:
                if !aUneCle {
                    Text("Ajoute une clé AeroDataBox dans Réglages pour voir ici le terminal, la porte, le tapis à bagages et les horaires à jour.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                if aUneCle {
                    Button("Actualiser", systemImage: "arrow.clockwise") { Task { await vols.actualiser(numero, jour, forcer: true) } }
                        .disabled(vols.etat(numero, jour) == .enCours)
                }
                if let url = rechercheGoogle { Link(destination: url) { Label("Rechercher sur Google", systemImage: "magnifyingglass") } }
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.borderless)
            .tint(teinte)
        }
    }

    private var rechercheGoogle: URL? {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [.init(name: "q", value: "vol \(numero) \(jour.formatted(.dateTime.day().month(.wide).year()))")]
        return c.url
    }

    private func infosDuVol(_ infos: InfosVol) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let resume = [[infos.compagnie, infos.numero].filter { !$0.isEmpty }.joined(separator: " "),
                          infos.duree.map { "Durée \(Self.texteDuree($0))" }, infos.avion]
                .compactMap { $0 }.filter { !$0.isEmpty }
            if !resume.isEmpty { Text(resume.joined(separator: " · ")).font(.footnote.weight(.medium)) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    escale(infos.depart, titre: "Départ", symbole: "airplane.departure", depart: true)
                    escale(infos.arrivee, titre: "Arrivée", symbole: "airplane.arrival", depart: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    escale(infos.depart, titre: "Départ", symbole: "airplane.departure", depart: true)
                    escale(infos.arrivee, titre: "Arrivée", symbole: "airplane.arrival", depart: false)
                }
            }
        }
    }

    private func escale(_ e: InfosVol.Escale, titre: String, symbole: String, depart: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(titre, systemImage: symbole).font(.caption.bold()).foregroundStyle(teinte)
            Text([e.code, e.aeroport].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline.weight(.semibold)).lineLimit(2)
            if let prevue = e.prevue {
                HStack(spacing: 6) {
                    let revisee = e.revisee.flatMap { abs($0.timeIntervalSince(prevue)) >= 60 ? $0 : nil }
                    Text(heure(prevue, e.fuseau)).monospacedDigit().strikethrough(revisee != nil).foregroundStyle(revisee != nil ? .secondary : .primary)
                    if let revisee { Text(heure(revisee, e.fuseau)).monospacedDigit().bold().foregroundStyle(.orange) }
                }
                .font(.subheadline)
            }
            FlowLayout(espacement: 6) {
                if let v = e.terminal { info("Terminal", v) }
                if depart, let v = e.comptoirs { info("Comptoirs", v) }
                if let v = e.porte { info("Porte", v) }
                if !depart, let v = e.tapis { info("Tapis", v) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func info(_ titre: String, _ valeur: String) -> some View {
        (Text("\(titre) ").foregroundColor(.secondary) + Text(valeur).bold())
            .font(.footnote)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(FondDePage.carte, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// L'heure à l'aéroport concerné.
    private func heure(_ date: Date, _ zone: TimeZone?) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone ?? .current))
    }

    static func texteDuree(_ secondes: TimeInterval) -> String {
        let m = Int((secondes / 60).rounded())
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
    }
}

/// La fiche du transport d'aller ou de retour (comme depuis le Timing).
struct FicheExtremite: View {
    let voyage: Voyage
    let extremite: TimingView.ExtremiteTransport

    var body: some View {
        let elements = voyage.elementsDuVoyage
        let etape = extremite == .aller ? elements.first : elements.last
        let nom = etape.map { $0.titre.isEmpty ? "Étape" : $0.titre } ?? "Étape"
        let jours = voyage.jours
        TransportEditView(
            trajet: extremite == .aller ? "Départ → \(nom)" : "\(nom) → Retour",
            jour: (extremite == .aller ? jours.first : jours.last) ?? .now,
            coordonnees: nil,
            existant: extremite == .aller ? voyage.transportAller : voyage.transportRetour,
            lieuxExtremites: true,
            voyage: voyage,
            cleLien: extremite == .aller ? LienReservation.aller : LienReservation.retour,
            enregistrer: { nouveau in
                if extremite == .aller { voyage.transportAller = nouveau } else { voyage.transportRetour = nouveau }
            })
    }
}
