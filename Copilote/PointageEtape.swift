import SwiftUI

/// En voyage : les deux moments réels d'une étape (ou d'une sous-étape) que l'on note sur place.
enum MomentPointe: String, Identifiable {
    case arrivee, depart
    var id: String { rawValue }

    var nom: String { self == .arrivee ? "Arrivée" : "Départ" }

    var symbole: String { self == .arrivee ? "figure.walk.arrival" : "figure.walk.departure" }

    var couleur: Color { self == .arrivee ? .green : .orange }

    /// Le champ de l'étape qui garde ce moment.
    var champ: ReferenceWritableKeyPath<Etape, Date?> { self == .arrivee ? \.arriveeReelle : \.departReel }
}

extension Etape {
    /// « 9:12 » : un moment réel, lu à l'heure locale du lieu de l'étape (c'est un instant, pas une heure saisie).
    @MainActor func heureReelle(_ instant: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = fuseau
        return instant.formatted(style)
    }
}

/// Les boutons « Arrivée » et « Départ » de la fiche, en voyage. Un appui propose l'heure actuelle, qu'on peut changer
/// avant de valider ; une fois notée, l'heure s'affiche dans le bouton, qui permet de la corriger ou de l'effacer.
struct PointageEtape: View {
    @Bindable var etape: Etape
    @State private var enCours: MomentPointe?

    var body: some View {
        // Côte à côte s'il y a la place pour lire les textes en entier, sinon l'un au-dessus de l'autre.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                bouton(.arrivee)
                bouton(.depart)
            }
            VStack(spacing: 8) {
                bouton(.arrivee)
                bouton(.depart)
            }
        }
        .sheet(item: $enCours) { moment in
            ConfirmationPointage(etape: etape, moment: moment)
        }
    }

    private func bouton(_ moment: MomentPointe) -> some View {
        let note = etape[keyPath: moment.champ]
        return Button { enCours = moment } label: {
            HStack(spacing: 8) {
                Image(systemName: note == nil ? moment.symbole : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 0) {
                    if let note {
                        Text("\(moment.nom) à \(etape.heureReelle(note))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text("Modifier").font(.caption).opacity(0.85)
                    } else {
                        Text(moment.nom).font(.subheadline.weight(.semibold))
                        Text("Noter l'heure").font(.caption)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(note == nil ? moment.couleur : .white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(note == nil ? moment.couleur.opacity(0.14) : moment.couleur))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.map { "\(moment.nom) notée à \(etape.heureReelle($0)), modifier" } ?? "Noter l'heure de \(moment == .arrivee ? "l'arrivée" : "départ")")
        .help(note == nil ? "Noter l'heure \(moment == .arrivee ? "d'arrivée" : "de départ") (l'heure actuelle est proposée)" : "Corriger ou effacer l'heure notée")
    }
}

/// La confirmation d'un moment : l'heure actuelle (ou celle déjà notée), modifiable, puis Valider ou Annuler.
private struct ConfirmationPointage: View {
    @Bindable var etape: Etape
    let moment: MomentPointe
    @Environment(\.dismiss) private var fermer
    @State private var brouillon = Date.now

    private var dejaNote: Date? { etape[keyPath: moment.champ] }

    /// Le départ noté avant l'arrivée (ou l'inverse) : on le signale sans l'empêcher.
    private var incoherent: Bool {
        switch moment {
        case .arrivee: etape.departReel.map { brouillon > $0 } ?? false
        case .depart: etape.arriveeReelle.map { brouillon < $0 } ?? false
        }
    }

    private var titreEtape: String { etape.titre.isEmpty ? (etape.estSousEtape ? "la sous-étape" : "l'étape") : "« \(etape.titre) »" }

    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            Image(systemName: moment.symbole)
                .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(moment.couleur))
            VStack(spacing: 4) {
                Text(moment == .arrivee ? "Arrivée à \(titreEtape)" : "Départ de \(titreEtape)")
                    .font(.headline).multilineTextAlignment(.center)
                Text(dejaNote == nil ? "L'heure actuelle est proposée : change-la si besoin." : "Corrige l'heure notée, ou efface-la.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            DatePicker(moment.nom, selection: $brouillon, displayedComponents: .hourAndMinute)
                .labelsHidden()
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                // L'heure se lit et se choisit à l'heure locale du lieu de l'étape.
                .environment(\.timeZone, etape.fuseau)
            // Les autres heures de l'app se lisent dans le fuseau du voyage (voir `Horloge`) : s'il diffère du lieu, on le précise.
            if etape.fuseau.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                Label("Heure locale du lieu (\(etape.fuseau.localizedName(for: .shortGeneric, locale: .current) ?? etape.fuseau.identifier))", systemImage: "globe")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if incoherent {
                Label(moment == .arrivee ? "Après l'heure de départ notée" : "Avant l'heure d'arrivée notée",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button("Annuler", role: .cancel) { fermer() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Valider") {
                    etape[keyPath: moment.champ] = brouillon
                    fermer()
                }
                .buttonStyle(.borderedProminent)
                .tint(moment.couleur)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            if dejaNote != nil {
                Button("Effacer l'heure", systemImage: "trash", role: .destructive) {
                    etape[keyPath: moment.champ] = nil
                    fermer()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        #if os(macOS)
        .frame(width: 340, height: 460)
        #endif
        .presentationDetents([.fraction(0.72), .large])
        .onAppear { brouillon = dejaNote ?? .now }
    }
}

/// Une pastille discrète pour une liste : arrivé (vert) ou reparti (coche), en voyage.
struct PastillePointage: View {
    let etape: Etape

    var body: some View {
        if let depart = etape.departReel {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Départ à \(etape.heureReelle(depart))")
                .help("Départ à \(etape.heureReelle(depart))")
        } else if let arrivee = etape.arriveeReelle {
            Image(systemName: "figure.walk.arrival").foregroundStyle(.green)
                .accessibilityLabel("Arrivée à \(etape.heureReelle(arrivee))")
                .help("Arrivée à \(etape.heureReelle(arrivee))")
        }
    }
}
