//
//  CameraService.swift
//  OnCuts
//
//  AVFoundation camera session with Snapchat-style front-camera mirroring.
//

#if os(iOS)

@preconcurrency import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Session + capture

final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isAuthorized = false
    @Published private(set) var setupFailed = false

    private let sessionQueue = DispatchQueue(label: "com.oncuts.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var photoDelegateRetain: PhotoCaptureDelegate?

    private var devicePosition: AVCaptureDevice.Position = .back

    func ensureAuthorized() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await MainActor.run { isAuthorized = true }
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                isAuthorized = ok
                if !ok { setupFailed = true }
            }
        default:
            await MainActor.run {
                isAuthorized = false
                setupFailed = true
            }
        }
    }

    func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.rebuildSession()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.devicePosition = self.devicePosition == .back ? .front : .back
            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }
            self.rebuildSession()
            if wasRunning { self.session.startRunning() }
        }
    }

    func capturePhoto(flashMode: AVCaptureDevice.FlashMode, completion: @escaping @MainActor (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let position = self.devicePosition
            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            } else {
                settings.flashMode = .off
            }

            let delegate = PhotoCaptureDelegate(devicePosition: position) { image in
                Task { @MainActor in
                    completion(image)
                }
                self.sessionQueue.async {
                    self.photoDelegateRetain = nil
                }
            }
            self.photoDelegateRetain = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func rebuildSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else {
            Task { @MainActor [weak self] in self?.setupFailed = true }
            return
        }

        session.addInput(input)
        session.addOutput(photoOutput)
    }

    // MARK: - Snapchat-style output

    /// Front: mirror like the preview (`leftMirrored`). Rear: prefer embedded JPEG orientation from the capture pipeline.
    nonisolated static func makeUIImage(from photo: AVCapturePhoto, devicePosition: AVCaptureDevice.Position) -> UIImage? {
        if devicePosition == .front {
            guard let cgImage = photo.cgImageRepresentation() else { return nil }
            return UIImage(cgImage: cgImage, scale: 1.0, orientation: .leftMirrored)
        }
        if let data = photo.fileDataRepresentation(), let img = UIImage(data: data) {
            return img
        }
        guard let cgImage = photo.cgImageRepresentation() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
}

// MARK: - Photo delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let devicePosition: AVCaptureDevice.Position
    let onComplete: (UIImage?) -> Void

    init(devicePosition: AVCaptureDevice.Position, onComplete: @escaping (UIImage?) -> Void) {
        self.devicePosition = devicePosition
        self.onComplete = onComplete
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if error != nil {
            onComplete(nil)
            return
        }
        onComplete(CameraService.makeUIImage(from: photo, devicePosition: devicePosition))
    }
}

// MARK: - Preview

final class CameraPreviewContainer: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        CameraPreviewView.applyPreviewRotation(previewLayer)
    }
}

enum CameraPreviewView {
    fileprivate static func applyPreviewRotation(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection else { return }
        let angle = interfaceOrientationAngle()
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private static func interfaceOrientationAngle() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return 90 }
        switch scene.interfaceOrientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        default: return 90
        }
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewContainer {
        let v = CameraPreviewContainer()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: CameraPreviewContainer, context: Context) {
        uiView.previewLayer.session = session
        CameraPreviewView.applyPreviewRotation(uiView.previewLayer)
    }
}

// MARK: - Profile capture UI

enum CameraState: Equatable {
    case capturing
    case reviewing
}

private struct ProfileCameraLiquidSpinner: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.large)
            .tint(Color.oliveGreen)
            .padding(22)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
            }
    }
}

struct ProfileCameraCaptureView: View {
    @Binding var isPresented: Bool
    /// Upload path (e.g. `runUpload`); runs while the liquid spinner is visible.
    var onConfirmUpload: @MainActor (UIImage) async -> Void

    @StateObject private var camera = CameraService()
    @State private var flashOn = false
    @State private var cameraState: CameraState = .capturing
    @State private var reviewBuffer: UIImage?
    @State private var isConfirmingUpload = false

    private let stateSpring = Animation.spring(response: 0.48, dampingFraction: 0.82)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            mainVisualLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                bottomChrome
            }
            .animation(stateSpring, value: cameraState)
            .animation(stateSpring, value: isConfirmingUpload)

            if isConfirmingUpload {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ProfileCameraLiquidSpinner()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(stateSpring, value: isConfirmingUpload)
        .task {
            await camera.ensureAuthorized()
            if camera.isAuthorized {
                camera.configureAndStart()
            }
        }
        .onDisappear {
            camera.stop()
            reviewBuffer = nil
            cameraState = .capturing
            isConfirmingUpload = false
        }
    }

    @ViewBuilder
    private var mainVisualLayer: some View {
        switch cameraState {
        case .capturing:
            if camera.isAuthorized && !camera.setupFailed {
                CameraPreviewRepresentable(session: camera.session)
            } else if camera.setupFailed {
                Text("Camera unavailable")
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        case .reviewing:
            if let reviewBuffer {
                Image(uiImage: reviewBuffer)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
            }
        }
    }

    @ViewBuilder
    private var topChrome: some View {
        if cameraState == .capturing {
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(OnCutsFont.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .padding(.leading, 20)
                .padding(.top, 12)

                Spacer()

                Button {
                    withAnimation(stateSpring) {
                        flashOn.toggle()
                    }
                } label: {
                    Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(OnCutsFont.system(size: 22))
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 20)
                .padding(.top, 12)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        Group {
            switch cameraState {
            case .capturing:
                HStack(spacing: 44) {
                    Button {
                        camera.flipCamera()
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(OnCutsFont.system(size: 26))
                            .foregroundStyle(.white)
                    }

                    Button {
                        let mode: AVCaptureDevice.FlashMode = flashOn ? .on : .off
                        camera.capturePhoto(flashMode: mode) { image in
                            guard let image else { return }
                            camera.stop()
                            withAnimation(stateSpring) {
                                reviewBuffer = image
                                cameraState = .reviewing
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(.white)
                                .frame(width: 58, height: 58)
                        }
                    }

                    Color.clear
                        .frame(width: 26, height: 26)
                }
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))

            case .reviewing:
                if !isConfirmingUpload {
                    HStack {
                        Button {
                            withAnimation(stateSpring) {
                                reviewBuffer = nil
                                cameraState = .capturing
                            }
                            camera.configureAndStart()
                        } label: {
                            Image(systemName: "xmark")
                                .font(OnCutsFont.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 56, height: 56)
                                .background {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            guard let reviewBuffer else { return }
                            withAnimation(stateSpring) {
                                isConfirmingUpload = true
                            }
                            Task { @MainActor in
                                await onConfirmUpload(reviewBuffer)
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(OnCutsFont.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 56, height: 56)
                                .background {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

#endif
