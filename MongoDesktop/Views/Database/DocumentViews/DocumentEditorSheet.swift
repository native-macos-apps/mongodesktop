import SwiftUI
import SwiftBSON

struct DocumentEditorSheet: View {
    let title: String
    @Binding var isPresented: Bool
    @State private var jsonText: String
    @State private var errorMessage: String? = nil
    @State private var isSaving = false
    
    let documentKeys: [String]
    let onSave: (BSONDocument) async -> Bool

    init(
        title: String,
        isPresented: Binding<Bool>,
        initialDocument: BSONDocument?,
        documentKeys: [String],
        onSave: @escaping (BSONDocument) async -> Bool
    ) {
        self.title = title
        self._isPresented = isPresented
        self.documentKeys = documentKeys
        self.onSave = onSave
        
        let initialText: String
        if let initialDocument {
            initialText = initialDocument.toRelaxedExtendedJSONString()
        } else {
            initialText = "{\n  \n}"
        }
        self._jsonText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                JSONEditorView(
                    text: $jsonText,
                    errorMessage: $errorMessage,
                    documentKeys: documentKeys,
                    minHeight: 300
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(errorMessage == nil ? Color.secondary.opacity(0.3) : Color.red.opacity(0.7), lineWidth: 1)
                }
                .padding()

                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(errorMessage != nil || isSaving)
                }
            }
        }
        .frame(minWidth: 550, minHeight: 450)
    }

    private func save() {
        guard errorMessage == nil else { return }
        do {
            let parsed = try MongoQueryParsing.parseFilter(jsonText)
            isSaving = true
            Task {
                let success = await onSave(parsed)
                if success {
                    isPresented = false
                } else {
                    isSaving = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
