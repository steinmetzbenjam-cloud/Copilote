import SwiftUI

extension View {
    /// Demande confirmation avant de supprimer `element` : la suppression n'a lieu qu'après « Supprimer ».
    /// Un ⌘Z (ou une secousse de l'iPhone) l'annule encore ensuite.
    func confirmerSuppression<T>(_ element: Binding<T?>, titre: @escaping (T) -> String, message: String = "Tu pourras l'annuler juste après avec ⌘Z ou en secouant l'iPhone.",
                                 bouton: String = "Supprimer", action: @escaping (T) -> Void) -> some View {
        confirmationDialog(element.wrappedValue.map(titre) ?? "",
                           isPresented: Binding(get: { element.wrappedValue != nil }, set: { if !$0 { element.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: element.wrappedValue) { valeur in
            Button(bouton, role: .destructive) { action(valeur) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text(message)
        }
    }

    /// Même chose pour une suppression sans élément à transmettre (un bouton « Supprimer » dans une fiche).
    func confirmerSuppression(_ demande: Binding<Bool>, titre: String, message: String = "Tu pourras l'annuler juste après avec ⌘Z ou en secouant l'iPhone.",
                              bouton: String = "Supprimer", action: @escaping () -> Void) -> some View {
        confirmationDialog(titre, isPresented: demande, titleVisibility: .visible) {
            Button(bouton, role: .destructive, action: action)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
