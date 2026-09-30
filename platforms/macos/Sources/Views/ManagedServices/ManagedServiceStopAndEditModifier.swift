import SwiftUI

/**
 * Shared "Stop & Edit" confirmation for an owned running service.
 *
 * Editing a running service is never an in-place socket mutation: the user
 * must confirm the stop first, and the editor opens only once the runtime has
 * actually reached the stopped state (design notes, section 12.2). The same
 * flow backs both the detail actions and the list context menu.
 */
struct ManagedServiceStopAndEditRequest: Identifiable {
    let id: UUID
    let name: String
}

private struct ManagedServiceStopAndEditModifier: ViewModifier {
    @Binding var request: ManagedServiceStopAndEditRequest?
    let onConfirmed: (UUID) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            L("service.edit.confirmTitle"),
            isPresented: Binding(
                get: { request != nil },
                set: { presented in
                    if !presented { request = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("service.edit.stopAndEdit"), role: .destructive) {
                if let id = request?.id {
                    onConfirmed(id)
                }
                request = nil
            }
            Button(L("service.cancel"), role: .cancel) {
                request = nil
            }
        } message: {
            Text(L("service.edit.confirmMessage", request?.name ?? ""))
        }
    }
}

extension View {
    /// Presents the Stop & Edit confirmation for a running managed service.
    func managedServiceStopAndEditConfirmation(
        _ request: Binding<ManagedServiceStopAndEditRequest?>,
        onConfirmed: @escaping (UUID) -> Void
    ) -> some View {
        modifier(ManagedServiceStopAndEditModifier(request: request, onConfirmed: onConfirmed))
    }
}
