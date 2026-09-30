import SwiftUI

struct SearchablePickerView: View {
    let items: [String]
    let selection: String
    let isLoading: Bool
    let placeholder: String
    let onSelect: (String) -> Void
    let onRefresh: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [String] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // List
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text(L("common.loading"))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            } else if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text(L("k8s.searchableNoItems"))
                            .foregroundStyle(.secondary)
                        Button(L("common.refresh")) { onRefresh() }
                            .buttonStyle(.bordered)
                    } else {
                        Text(L("k8s.searchableNoMatches"))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems, id: \.self) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack {
                                    if item == selection {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .frame(width: 16)
                                    } else {
                                        Color.clear.frame(width: 16)
                                    }
                                    Text(item)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(item == selection ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // Refresh button
            Button {
                onRefresh()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(L("common.refresh"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 220)
        .onAppear {
            isSearchFocused = true
        }
    }
}
