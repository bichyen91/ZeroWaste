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
import UIKit

struct ScannedLine: Identifiable, Hashable {
    let id = UUID()
    var itemName: String
    var expiredDateText: String
    var predictedExpired: Date?
}

struct ScanReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var message = SharedProperties.shared
    
    @State private var formTop: CGFloat = 0
    @State private var selectedImage: UIImage? = nil
    @State private var showCamera: Bool = false
    @State private var showDateCamera: Bool = false
    @State private var isProcessing = false
    
    @State private var purchaseDate: Date = Date()
    @State private var lines: [ScannedLine] = []
    @State private var namePredictDebounce: [UUID: DispatchWorkItem] = [:]
    
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
                    RoundedCorner(radius: 20, corners: [.bottomLeft, .bottomRight]).fill(Color.white)
                    VStack(spacing: 0) {
                        itemsList
                        bottomBar
                    }
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
            if selectedImage != nil { Task { await scanReceipt() } }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CustomCameraScreen(onDone: { result in
                showCamera = false
                if let img = result { selectedImage = img }
            }, overlayMessage: "Align camera with the item section.")
        }
        .onChange(of: selectedImage) {
            if selectedImage != nil { Task { await scanReceipt() } }
        }
        .onChange(of: purchaseDate) {
            Task { await predictAll() }
        }
    }
    
    private var formSection: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 50)
                Text("Purchase date").foregroundColor(.gray)
                HStack(spacing: 8) {
                    DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                        .datePickerStyle(.automatic)
                        .labelsHidden()
                }
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

    private func expiryBinding(for line: ScannedLine) -> Binding<Date> {
        if let idx = lines.firstIndex(of: line) {
            return Binding<Date>(
                get: { lines[idx].predictedExpired ?? Date() },
                set: { newValue in
                    lines[idx].predictedExpired = newValue
                    lines[idx].expiredDateText = SharedProperties.parseDateToString(newValue, to: "yyyy-MM-dd")
                }
            )
        } else {
            return .constant(Date())
        }
    }

    @ViewBuilder
    private var itemsList: some View {
        List {
            if lines.isEmpty {
                HStack { Spacer(); Text("No items yet").foregroundColor(.gray); Spacer() }
            } else {
                Section {
                    ForEach(lines) { line in
                        rowView(line: line)
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
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Spacer()
            Button(action: { showCamera = true }) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.camera").imageScale(.large)
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

    // Split row UI to reduce type-checking complexity
    @ViewBuilder
    private func rowView(line: ScannedLine) -> some View {
        let nameBinding = binding(for: line).itemName
        HStack {
            TextField("Item name", text: nameBinding)
                .textInputAutocapitalization(.never)
                .onChange(of: nameBinding.wrappedValue) {
                    let id = line.id
                    namePredictDebounce[id]?.cancel()
                    let work = DispatchWorkItem { Task { await predictOne(for: line) } }
                    namePredictDebounce[id] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
                }

            DatePicker("", selection: expiryBinding(for: line), displayedComponents: .date)
                .labelsHidden()

            Button(action: { if let idx = lines.firstIndex(of: line) { lines.remove(at: idx) } }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete item")
        }
    }
    
    // MARK: - Main Scan
    private func scanReceipt() async {
        guard let image = selectedImage else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        let pre = ScanReceiptHelper.enhance(image: image) ?? image
        guard let cgImage = pre.cgImage else { return }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        if #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = true }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { print("Vision error: \(error)"); return }
        
        let ordered: [(text: String, box: CGRect)] = (request.results ?? [])
            .compactMap { obs -> (String, CGRect)? in
                guard let cand = obs.topCandidates(1).first else { return nil }
                return (cand.string, obs.boundingBox)
            }
            .sorted { a, b in
                if abs(a.box.maxY - b.box.maxY) > 0.005 { return a.box.maxY > b.box.maxY }
                return a.box.minX < b.box.minX
            }
        
        let allTextLines = ordered.map { ScanReceiptHelper.normalizeOCRGlitches($0.text) }
        let fullText = allTextLines.joined(separator: " ")
        print("Full OCR text: \(fullText)")
        
        if let d = ScanReceiptHelper.extractPurchaseDate(lines: allTextLines, full: fullText) {
            purchaseDate = ScanReceiptHelper.normalizeToLocalMidday(d)
        }
        
        // Extract data line-by-line with filtering (letters-only, skip keywords/phone/zip)
        var items = ScanReceiptHelper.extractItemsLineByLine(lines: allTextLines)
        print("Final items found: \(items)")
        lines = items.map { ScannedLine(itemName: $0, expiredDateText: "", predictedExpired: nil) }
        await predictAll()
    }
    
    // MARK: - Predictions
    private func predictAll() async {
        for index in lines.indices {
            let name = lines[index].itemName
            await withCheckedContinuation { continuation in
                AIService.shared.predictExpiredDate(itemName: name, purchaseDate: purchaseDate) { date in
                    if let d = date {
                        let normalized = ScanReceiptHelper.normalizeToLocalMidday(d)
                        lines[index].predictedExpired = normalized
                        lines[index].expiredDateText = SharedProperties.parseDateToString(normalized, to: "yyyy-MM-dd")
                    } else {
                        lines[index].predictedExpired = nil
                        lines[index].expiredDateText = ""
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func predictOne(for line: ScannedLine) async {
        guard let idx = lines.firstIndex(of: line) else { return }
        let name = lines[idx].itemName
        await withCheckedContinuation { continuation in
            AIService.shared.predictExpiredDate(itemName: name, purchaseDate: purchaseDate) { date in
                if let d = date {
                    let normalized = ScanReceiptHelper.normalizeToLocalMidday(d)
                    lines[idx].predictedExpired = normalized
                    lines[idx].expiredDateText = SharedProperties.parseDateToString(normalized, to: "yyyy-MM-dd")
                } else {
                    lines[idx].predictedExpired = nil
                    lines[idx].expiredDateText = ""
                }
                continuation.resume()
            }
        }
    }
    
    private func saveItems() {
        var savedItems: [Item] = []
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
            savedItems.append(newItem)
        }
        do {
            try modelContext.save()
            if let user = UserSession.shared.currentUser {
                savedItems.forEach { NotificationManager.shared.scheduleForItem($0, user: user) }
            }
        } catch { print(error) }
        dismiss()
    }
}

#Preview { ScanReceiptView() }

// MARK: - Custom camera (capture -> crop -> confirm)
fileprivate struct CustomCameraScreen: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void
    var overlayMessage: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = CustomCameraViewController()
        controller.onFinish = { image in onDone(image) }
        controller.overlayMessage = overlayMessage
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    class Coordinator: NSObject { var parent: CustomCameraScreen; init(_ parent: CustomCameraScreen) { self.parent = parent } }
}

fileprivate class CustomCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onFinish: ((UIImage?) -> Void)?
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let captureButton = UIButton(type: .custom)
    private let liveRetakeButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private weak var confirmUseButtonRef: UIButton?
    private weak var confirmRetakeButtonRef: UIButton?
    private var capturedImage: UIImage?
    var overlayMessage: String = "Align camera with the item section."
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
    
    private func setupSession() {
        session.beginConfiguration()
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.sessionPreset = .photo
        session.commitConfiguration()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(previewLayer)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    private func setupUI() {
        
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 32
        captureButton.layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
        captureButton.layer.borderWidth = 2
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        
        liveRetakeButton.setTitle("Retake", for: .normal)
        liveRetakeButton.setTitleColor(.white, for: .normal)
        liveRetakeButton.translatesAutoresizingMaskIntoConstraints = false
        liveRetakeButton.addTarget(self, action: #selector(retakeLive), for: .touchUpInside)
        view.addSubview(liveRetakeButton)

        // Cancel button (top-right)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelCamera), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            captureButton.widthAnchor.constraint(equalToConstant: 64),
            captureButton.heightAnchor.constraint(equalToConstant: 64),
            liveRetakeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            liveRetakeButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
    }
    
    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func retakeLive() { /* adjust frame and capture again */ }
    @objc private func cancelCamera() { onFinish?(nil) }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else {
            onFinish?(nil); return
        }
        let normalized = fixOrientation(img)
        showConfirm(for: normalized)
    }
    
    private func showConfirm(for image: UIImage) {
        capturedImage = image
        session.stopRunning()
        let preview = UIImageView(image: image)
        preview.contentMode = .scaleAspectFit
        preview.frame = view.bounds
        view.addSubview(preview)
        captureButton.isHidden = true
        liveRetakeButton.isHidden = true
        
        let useBtn = UIButton(type: .system)
        useBtn.setTitle("Use", for: .normal)
        useBtn.setTitleColor(.white, for: .normal)
        useBtn.addTarget(self, action: #selector(useCropped), for: .touchUpInside)
        let retakeBtn = UIButton(type: .system)
        retakeBtn.setTitle("Retake", for: .normal)
        retakeBtn.setTitleColor(.white, for: .normal)
        retakeBtn.addTarget(self, action: #selector(retake), for: .touchUpInside)
        useBtn.translatesAutoresizingMaskIntoConstraints = false
        retakeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(useBtn)
        view.addSubview(retakeBtn)
        NSLayoutConstraint.activate([
            retakeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            retakeBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            useBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            useBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        confirmUseButtonRef = useBtn
        confirmRetakeButtonRef = retakeBtn
    }
    
    @objc private func useCropped() { onFinish?(capturedImage) }
    @objc private func retake() {
        confirmUseButtonRef?.removeFromSuperview()
        confirmRetakeButtonRef?.removeFromSuperview()
        for v in view.subviews where v is UIImageView { v.removeFromSuperview() }
        confirmUseButtonRef = nil
        confirmRetakeButtonRef = nil
        captureButton.isHidden = false
        liveRetakeButton.isHidden = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
}

fileprivate func fixOrientation(_ img: UIImage) -> UIImage {
    if img.imageOrientation == .up { return img }
    UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
    img.draw(in: CGRect(origin: .zero, size: img.size))
    let normalized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return normalized ?? img
}

