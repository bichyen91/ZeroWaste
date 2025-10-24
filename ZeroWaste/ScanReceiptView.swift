//
//  ScanReceiptView.swift
//  ZeroWaste
//
//  Restored view to scan receipts, crop, extract items, and predict expiry dates
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
        .fullScreenCover(isPresented: $showDateCamera) {
            CustomCameraScreen(onDone: { result in
                showDateCamera = false
                if let img = result { Task { await scanDateOnly(image: img) } }
            }, overlayMessage: "Align camera for the purchase date")
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
                    // Button(action: { showDateCamera = true }) {
                    //     Image(systemName: "camera.badge.clock").imageScale(.large)
                    // }
                    // .accessibilityLabel("Scan date only")
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
    
    // MARK: - Scan date only path
    private func scanDateOnly(image: UIImage) async {
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
        do { try handler.perform([request]) } catch { return }
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
        if let d = ScanReceiptHelper.extractPurchaseDate(lines: allTextLines, full: fullText) {
            purchaseDate = ScanReceiptHelper.normalizeToLocalMidday(d)
        }
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

// MARK: - Adjustable crop overlay used by custom camera and cropper
fileprivate struct CropOverlay: View {
    @Binding var cropRect: CGRect
    let containerSize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Path { path in
                    let full = CGRect(origin: .zero, size: geo.size)
                    path.addRect(full)
                    path.addRect(cropRect)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(dragGesture(in: geo.size))
                
                handle(at: CGPoint(x: cropRect.minX, y: cropRect.minY)) { delta in resize(from: .topLeft, delta: delta, bounds: geo.size) }
                handle(at: CGPoint(x: cropRect.maxX, y: cropRect.minY)) { delta in resize(from: .topRight, delta: delta, bounds: geo.size) }
                handle(at: CGPoint(x: cropRect.minX, y: cropRect.maxY)) { delta in resize(from: .bottomLeft, delta: delta, bounds: geo.size) }
                handle(at: CGPoint(x: cropRect.maxX, y: cropRect.maxY)) { delta in resize(from: .bottomRight, delta: delta, bounds: geo.size) }
            }
            .onAppear {
                cropRect = cropRect.intersection(CGRect(origin: .zero, size: geo.size)).integral
            }
        }
    }
    
    private func handle(at point: CGPoint, onDrag: @escaping (CGSize) -> Void) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 18, height: 18)
            .position(point)
            .gesture(DragGesture().onChanged { value in onDrag(value.translation) })
    }
    
    private func dragGesture(in bounds: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            var newRect = cropRect.offsetBy(dx: value.translation.width, dy: value.translation.height)
            let maxRect = CGRect(origin: .zero, size: bounds)
            if newRect.minX < 0 { newRect.origin.x = 0 }
            if newRect.minY < 0 { newRect.origin.y = 0 }
            if newRect.maxX > maxRect.maxX { newRect.origin.x = maxRect.maxX - newRect.width }
            if newRect.maxY > maxRect.maxY { newRect.origin.y = maxRect.maxY - newRect.height }
            cropRect = newRect.integral
        }
    }
    
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private func resize(from corner: Corner, delta: CGSize, bounds: CGSize) {
        var rect = cropRect
        switch corner {
        case .topLeft:
            rect.origin.x += delta.width
            rect.origin.y += delta.height
            rect.size.width -= delta.width
            rect.size.height -= delta.height
        case .topRight:
            rect.origin.y += delta.height
            rect.size.width += delta.width
            rect.size.height -= delta.height
        case .bottomLeft:
            rect.origin.x += delta.width
            rect.size.width -= delta.width
            rect.size.height += delta.height
        case .bottomRight:
            rect.size.width += delta.width
            rect.size.height += delta.height
        }
        let minSize: CGFloat = 40
        rect.size.width = max(minSize, rect.size.width)
        rect.size.height = max(minSize, rect.size.height)
        let maxRect = CGRect(origin: .zero, size: bounds)
        if rect.minX < 0 { rect.origin.x = 0 }
        if rect.minY < 0 { rect.origin.y = 0 }
        if rect.maxX > maxRect.maxX { rect.origin.x = maxRect.maxX - rect.width }
        if rect.maxY > maxRect.maxY { rect.origin.y = maxRect.maxY - rect.height }
        cropRect = rect.integral
    }
}

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
    private var cropOverlay = CameraCropOverlay(frame: .zero)
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
        // Removed live crop frame overlay
        
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
        // Use full image (live crop frame removed)
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

// MARK: - Cropping helpers for custom camera
fileprivate class CameraCropOverlay: UIView {
    var message: String = ""
    private let messageLabel = UILabel()
    private let frameLayer = CAShapeLayer()
    fileprivate private(set) var cropRect: CGRect = .zero
    private var panStart: CGPoint = .zero
    private let handleSize: CGFloat = 22
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private var handleViews: [Corner: UIView] = [:]
    var cropIgnoresPassThrough: Bool = true
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    
    private func setup() {
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)
        
        frameLayer.strokeColor = UIColor.yellow.cgColor
        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.lineWidth = 2
        layer.addSublayer(frameLayer)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        // Corner handles for resizing
        for corner in [Corner.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let v = UIView(frame: CGRect(x: 0, y: 0, width: handleSize, height: handleSize))
            v.backgroundColor = UIColor.yellow
            v.layer.cornerRadius = handleSize/2
            v.layer.borderColor = UIColor.black.cgColor
            v.layer.borderWidth = 1
            v.isUserInteractionEnabled = true
            let drag = UIPanGestureRecognizer(target: self, action: #selector(handleCornerPan(_:)))
            v.addGestureRecognizer(drag)
            addSubview(v)
            handleViews[corner] = v
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        messageLabel.frame = CGRect(x: 16, y: 16, width: bounds.width - 32, height: 60)
        messageLabel.text = message
        if cropRect == .zero {
            let initialW = bounds.width * 0.85
            let initialH = bounds.height * 0.35
            cropRect = CGRect(x: (bounds.width - initialW)/2, y: (bounds.height - initialH)/2, width: initialW, height: initialH)
        }
        drawOverlay()
    }
    
    private func drawOverlay() {
        let path = UIBezierPath(rect: bounds)
        let cutout = UIBezierPath(rect: cropRect)
        path.append(cutout)
        path.usesEvenOddFillRule = true
        let dimLayer = CAShapeLayer()
        dimLayer.frame = bounds
        dimLayer.path = path.cgPath
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor(white: 0, alpha: 0.55).cgColor
        layer.sublayers?.removeAll(where: { $0 is CAShapeLayer && $0 !== frameLayer })
        layer.insertSublayer(dimLayer, below: frameLayer)
        frameLayer.path = UIBezierPath(rect: cropRect).cgPath
        layoutHandles()
    }
    
    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let translation = g.translation(in: self)
        switch g.state {
        case .began:
            panStart = translation
        case .changed:
            let dx = translation.x - panStart.x
            let dy = translation.y - panStart.y
            cropRect = cropRect.offsetBy(dx: dx, dy: dy)
            cropRect.origin.x = max(0, min(cropRect.origin.x, bounds.width - cropRect.width))
            cropRect.origin.y = max(0, min(cropRect.origin.y, bounds.height - cropRect.height))
            panStart = translation
            drawOverlay()
        default: break
        }
    }
    
    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .changed:
            let scale = g.scale
            let newW = max(40, min(bounds.width, cropRect.width * scale))
            let newH = max(40, min(bounds.height, cropRect.height * scale))
            let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
            cropRect.size = CGSize(width: newW, height: newH)
            cropRect.origin = CGPoint(x: center.x - newW/2, y: center.y - newH/2)
            cropRect.origin.x = max(0, min(cropRect.origin.x, bounds.width - cropRect.width))
            cropRect.origin.y = max(0, min(cropRect.origin.y, bounds.height - cropRect.height))
            g.scale = 1
            drawOverlay()
        default: break
        }
    }

    @objc private func handleCornerPan(_ g: UIPanGestureRecognizer) {
        guard let view = g.view, let corner = handleViews.first(where: { $0.value === view })?.key else { return }
        let t = g.translation(in: self)
        var rect = cropRect
        switch corner {
        case .topLeft:
            rect.origin.x += t.x
            rect.origin.y += t.y
            rect.size.width -= t.x
            rect.size.height -= t.y
        case .topRight:
            rect.origin.y += t.y
            rect.size.width += t.x
            rect.size.height -= t.y
        case .bottomLeft:
            rect.origin.x += t.x
            rect.size.width -= t.x
            rect.size.height += t.y
        case .bottomRight:
            rect.size.width += t.x
            rect.size.height += t.y
        }
        // Min size and clamp
        rect.size.width = max(40, rect.size.width)
        rect.size.height = max(40, rect.size.height)
        rect.origin.x = max(0, min(rect.origin.x, bounds.width - rect.size.width))
        rect.origin.y = max(0, min(rect.origin.y, bounds.height - rect.size.height))
        cropRect = rect.integral
        g.setTranslation(.zero, in: self)
        drawOverlay()
    }

    private func layoutHandles() {
        handleViews[.topLeft]?.center = CGPoint(x: cropRect.minX, y: cropRect.minY)
        handleViews[.topRight]?.center = CGPoint(x: cropRect.maxX, y: cropRect.minY)
        handleViews[.bottomLeft]?.center = CGPoint(x: cropRect.minX, y: cropRect.maxY)
        handleViews[.bottomRight]?.center = CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        for v in handleViews.values { v.isHidden = cropRect == .zero }
    }
}

fileprivate func cropImage(_ image: UIImage, with overlay: CameraCropOverlay, in containerSize: CGSize) -> UIImage {
    let base = fixOrientation(image)
    let imgSize = base.size
    let fitScale = min(containerSize.width / imgSize.width, containerSize.height / imgSize.height)
    let displayW = imgSize.width * fitScale
    let displayH = imgSize.height * fitScale
    let originX = (containerSize.width - displayW) / 2
    let originY = (containerSize.height - displayH) / 2
    let rect = overlay.cropRect
    let xInImage = max(0, (rect.minX - originX) / fitScale)
    let yInImage = max(0, (rect.minY - originY) / fitScale)
    let wInImage = max(1, rect.width / fitScale)
    let hInImage = max(1, rect.height / fitScale)
    guard let cg = base.cgImage else { return base }
    let scale = base.scale
    let cropRectPx = CGRect(x: xInImage * scale, y: yInImage * scale, width: wInImage * scale, height: hInImage * scale).integral
    guard cropRectPx.intersects(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)) else { return base }
    let bounded = cropRectPx.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard let cropped = cg.cropping(to: bounded) else { return base }
    return UIImage(cgImage: cropped, scale: base.scale, orientation: .up)
}

fileprivate func fixOrientation(_ img: UIImage) -> UIImage {
    if img.imageOrientation == .up { return img }
    UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
    img.draw(in: CGRect(origin: .zero, size: img.size))
    let normalized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return normalized ?? img
}


