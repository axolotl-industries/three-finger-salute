import SwiftUI
import Combine

struct OnboardingView: View {
    @State private var isTrusted = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "3.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.tint)
            
            Text("Welcome to Three Finger Salute")
                .font(.largeTitle.bold())
            
            Text("by Axolotl Industries")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, -20)
            
            VStack(alignment: .leading, spacing: 15) {
                FeatureRow(icon: "speaker.wave.3.fill", title: "Volume Swipe", description: "Three-finger vertical swipe to change volume instantly.")
                FeatureRow(icon: "computermouse", title: "Middle Click", description: "Three-finger tap or physical click to trigger a middle click.")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            Divider()
            
            VStack(spacing: 10) {
                if isTrusted {
                    Label("Accessibility Permissions Granted", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)
                    
                    Button("Get Started") {
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Label("Accessibility Permissions Required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.headline)
                    
                    Text("This app needs accessibility permissions to detect trackpad gestures and simulate clicks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(40)
        .frame(width: 500)
        .onReceive(timer) { _ in
            isTrusted = AXIsProcessTrusted()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 30)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
