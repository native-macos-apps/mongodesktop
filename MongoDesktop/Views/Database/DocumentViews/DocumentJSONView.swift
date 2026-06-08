import SwiftUI
import SwiftBSON

// MARK: - DocumentJSONView

struct DocumentJSONView: View {
    let documents: [BSONDocument]
    let timeZone: TimeZone
    let isLoading: Bool

    var body: some View {
        if isLoading && documents.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if documents.isEmpty {
            VStack {
                ContentUnavailableView(
                    "No documents",
                    systemImage: "curlybraces",
                    description: Text("This collection is empty or the filter returned no results.")
                )
                .padding(.top, 40)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(documents.indices, id: \.self) { index in
                        JSONDocumentCard(wrapper: wrapper(for: documents[index], index: index))
                    }
                }
                .padding(16)
            }
            .overlay {
                if isLoading {
                    VStack {
                        ProgressView()
                            .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial.opacity(0.3))
                }
            }
        }
    }

    private func wrapper(for document: BSONDocument, index: Int) -> JSONDocumentWrapper {
        let id: String
        if let rawId = document["_id"] {
            id = "id-\(String(describing: rawId))"
        } else {
            id = "idx-\(index)"
        }

        return JSONDocumentWrapper(
            id: id,
            index: index,
            document: document,
            nodes: document.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
        )
    }
}

// MARK: - JSONDocumentCard

struct JSONDocumentCard: View {
    let wrapper: JSONDocumentWrapper

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(wrapper.nodes) { node in
                    JSONNodeView(node: node, depth: 0)
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.wrapper.document.toCanonicalExtendedJSONString(), forType: .string)
            } label: {
                Label("Copy (BSON)", systemImage: "doc.on.doc")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.wrapper.document.toRelaxedExtendedJSONString(), forType: .string)
            } label: {
                Label("Copy JSON", systemImage: "curlybraces")
            }
        }
    }
}
