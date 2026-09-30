import SwiftUI

struct PortForwarderTableHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text(L("k8s.status"))
                .frame(width: 80, alignment: .leading)
            Text(L("k8s.name"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L("k8s.service"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L("ports.column.port"))
                .frame(width: 80, alignment: .leading)
            Text(L("common.actions"))
                .frame(width: 80, alignment: .center)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
