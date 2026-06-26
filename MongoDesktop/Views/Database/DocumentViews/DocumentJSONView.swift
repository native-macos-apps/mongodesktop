import SwiftUI
import SwiftBSON

// MARK: - DocumentJSONView

struct DocumentJSONView: View {
    let documents: [BSONDocument]
    let timeZone: TimeZone
    let isLoading: Bool
    let onEdit: (BSONDocument) -> Void
    let onDelete: ([BSONDocument]) -> Void
    @State private var selectedNodeID: String? = nil

    init(
        documents: [BSONDocument],
        timeZone: TimeZone,
        isLoading: Bool,
        onEdit: @escaping (BSONDocument) -> Void = { _ in },
        onDelete: @escaping ([BSONDocument]) -> Void = { _ in }
    ) {
        self.documents = documents
        self.timeZone = timeZone
        self.isLoading = isLoading
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

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
                        JSONDocumentCard(
                            wrapper: wrapper(for: documents[index], index: index),
                            selectedNodeID: $selectedNodeID,
                            onEdit: onEdit,
                            onDelete: { doc in onDelete([doc]) }
                        )
                    }
                }
                .padding(16)
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedNodeID = nil
                    }
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
        let id = JSONNode.rootID(for: document)
        return JSONDocumentWrapper(
            id: id,
            index: index,
            document: document,
            nodes: JSONNode.rootNodes(for: document, timeZone: timeZone)
        )
    }
}

// MARK: - JSONDocumentCard

struct JSONDocumentCard: View {
    let wrapper: JSONDocumentWrapper
    @Binding var selectedNodeID: String?
    var onEdit: ((BSONDocument) -> Void)? = nil
    var onDelete: ((BSONDocument) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(wrapper.nodes) { node in
                    JSONNodeView(node: node, depth: 0, selectedNodeID: $selectedNodeID)
                }
            }
            .padding(12)
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture {
                    selectedNodeID = nil
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .contextMenu {
            if let onEdit {
                Button {
                    onEdit(self.wrapper.document)
                } label: {
                    Label("Edit Document", systemImage: "pencil")
                }
            }
            
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(self.wrapper.document)
                } label: {
                    Label("Delete Document", systemImage: "trash")
                }
            }
            
            if onEdit != nil || onDelete != nil {
                Divider()
            }

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

struct JSONDocumentCardContainer: View {
    let wrapper: JSONDocumentWrapper
    @State private var selectedNodeID: String? = nil

    var body: some View {
        JSONDocumentCard(wrapper: wrapper, selectedNodeID: $selectedNodeID)
    }
}
