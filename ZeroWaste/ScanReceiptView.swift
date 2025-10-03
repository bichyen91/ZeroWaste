//
//  ScanReceiptView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 9/20/25.
//

import SwiftUI
import PhotosUI
import AVFoundation
import Vision
import SwiftData
 

struct ScannedLine: Identifiable, Hashable {
    let id = UUID()
    var itemName: String
    var expiredDateText: String // display only
    var predictedExpired: Date?
}

// UIKit camera wrapper
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onCapture: (UIImage?) -> Void
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = info[.originalImage] as? UIImage
            parent.image = img
            parent.onCapture(img)
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onCapture(nil)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            picker.sourceType = .photoLibrary
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

struct ScanReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var message = SharedProperties.shared
    
    @State private var formTop: CGFloat = 0
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var showCamera: Bool = false
    @State private var isProcessing = false
    
    @State private var purchaseDate: Date = Date()
    @State private var lines: [ScannedLine] = []
    
    init(initialImage: UIImage? = nil) {
        _selectedImage = State(initialValue: initialImage)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZeroWasteHeader { dismiss() }
                Spacer()
                
                formSection
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        GeometryReader { geo in
                            Color.white
                                .preference(key: FormTopKey.self, value: geo.frame(in: .global).minY)
                        }
                    )
                    .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
                    .shadow(radius: 20)
                    .onPreferenceChange(FormTopKey.self) { value in
                        self.formTop = value
                    }
                    .padding(.top)
                
                ZStack {
                    RoundedCorner(radius: 20, corners: [.bottomLeft, .bottomRight])
                        .fill(Color.white)
                    
                    VStack(spacing: 0) {
                        List {
                            if lines.isEmpty {
                                HStack { Spacer(); Text("No items yet").foregroundColor(.gray); Spacer() }
                            } else {
                                Section {
                                    ForEach(lines) { line in
                                        HStack {
                                            TextField("Item name", text: binding(for: line).itemName)
                                                .textInputAutocapitalization(.never)
                                            
                                            DatePicker("", selection: Binding(get: {
                                                binding(for: line).predictedExpired.wrappedValue ?? Date()
                                            }, set: { newValue in
                                                binding(for: line).predictedExpired.wrappedValue = newValue
                                                binding(for: line).expiredDateText.wrappedValue = SharedProperties.parseDateToString(newValue, to: "yyyy-MM-dd")
                                            }), displayedComponents: .date)
                                                .labelsHidden()
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text("Item Name").fontWeight(.semibold)
                                        Spacer()
                                        Text("Expired Date").fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        
                        // Bottom action bar inside white area
                        HStack {
                            Spacer()
                            Button(action: { showCamera = true }) {
                                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.camera")
                                    .imageScale(.large)
                            }
                            .accessibilityLabel("Retake receipt photo")
                            .zeroWasteStyle(width: 60)
                            .disabled(isProcessing)
                            Spacer()
                            Button("Save") { saveItems() }
                                .zeroWasteStyle(width: 120)
                                .disabled(isProcessing || lines.isEmpty)
                            Spacer()
                            Button("Cancel") { dismiss() }
                                .zeroWasteStyle(width: 120)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.bottom)
                }
                .clipShape(RoundedCorner(radius: 20, corners: [.bottomLeft, .bottomRight]))
            }
            .padding()
            
            FormAvatarImage(imageName: "scan", formTop: formTop)
            
            if isProcessing {
                ProgressView("Scanning…")
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                    .shadow(radius: 10)
            }
        }
        .background {
            Image("Background").resizable().scaledToFill().ignoresSafeArea()
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            if selectedImage == nil { showCamera = true }
            if selectedImage != nil {
                Task { await scanReceipt() }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage) { captured in
                if let img = captured {
                    selectedImage = img
                }
            }
        }
        .onChange(of: selectedImage) { newImage in
            if newImage != nil {
                Task { await scanReceipt() }
            }
        }
    }
    
    private var formSection: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 50)
                Text("Purchase date").foregroundColor(.gray)
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.automatic)
                    .labelsHidden()
            }
        }
    }
    
    private func binding(for line: ScannedLine) -> (itemName: Binding<String>, expiredDateText: Binding<String>, predictedExpired: Binding<Date?>) {
        guard let index = lines.firstIndex(of: line) else {
            return (.constant(""), .constant(""), .constant(nil))
        }
        return (
            Binding(get: { lines[index].itemName }, set: { lines[index].itemName = $0 }),
            Binding(get: { lines[index].expiredDateText }, set: { lines[index].expiredDateText = $0 }),
            Binding(get: { lines[index].predictedExpired }, set: { lines[index].predictedExpired = $0 })
        )
    }
    
    // MARK: - Main Scan
    
    private func scanReceipt() async {
        guard let image = selectedImage else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        // (Optional) Light pre-processing to help OCR
        let pre = ScanReceiptHelper.enhance(image: image) ?? image
        guard let cgImage = pre.cgImage else { return }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"] // add more if needed: ["en-US","es-ES"]
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Vision error: \(error)")
            return
        }
        
        // Order OCR results top→down, left→right using bounding boxes
        let ordered: [(text: String, box: CGRect)] = (request.results ?? [])
            .compactMap { obs -> (String, CGRect)? in
                guard let cand = obs.topCandidates(1).first else { return nil }
                return (cand.string, obs.boundingBox)
            }
            .sorted { a, b in
                // Vision's coordinates are normalized, origin bottom-left
                // Sort by descending maxY (top first), then minX (left to right)
                if abs(a.box.maxY - b.box.maxY) > 0.005 {
                    return a.box.maxY > b.box.maxY
                }
                return a.box.minX < b.box.minX
            }
        
        let allTextLines = ordered.map { ScanReceiptHelper.normalizeOCRGlitches($0.text) }
        let fullText = allTextLines.joined(separator: " ")
        print("Full OCR text: \(fullText)")
        
        // --- Purchase Date ---
        if let d = ScanReceiptHelper.extractPurchaseDate(lines: allTextLines, full: fullText) {
            purchaseDate = ScanReceiptHelper.normalizeToLocalMidday(d)
        }
        
        // --- Items (line-by-line extraction) ---
        let items = ScanReceiptHelper.extractItemsLineByLine(lines: allTextLines)
        
        print("Final items found: \(items)")
        lines = items.map { ScannedLine(itemName: $0, expiredDateText: "", predictedExpired: nil) }
        await predictAll()
    }
    
    // MARK: - Predict expiry for all
    private func predictAll() async {
        for index in lines.indices {
            let name = lines[index].itemName
            await withCheckedContinuation { continuation in
                AIService.shared.predictExpiredDate(itemName: name, purchaseDate: purchaseDate) { date in
                    lines[index].predictedExpired = date
                    if let d = date {
                        lines[index].expiredDateText = SharedProperties.parseDateToString(d, to: "yyyy-MM-dd")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func saveItems() {
        for entry in lines {
            guard !entry.itemName.isEmpty, let exp = entry.predictedExpired else { continue }
            let newItem = Item(
                itemCode: Item.getNextItemCode(from: modelContext),
                itemName: entry.itemName.lowercased(),
                purchasedDate: SharedProperties.parseDateToString(purchaseDate, to: "yyyy-MM-dd"),
                expiredDate: SharedProperties.parseDateToString(exp, to: "yyyy-MM-dd"),
                createdDate: SharedProperties.parseDateToString(Date(), to: "yyyy-MM-dd"),
                username: UserSession.shared.currentUser?.username ?? ""
            )
            modelContext.insert(newItem)
        }
        do { try modelContext.save() } catch { print(error) }
        dismiss()
    }
    
}

#Preview { ScanReceiptView() }
