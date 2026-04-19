// Three Finger Salute
import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SystemSettingsManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "3.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)
            Text("Three Finger Salute")
                .font(.headline)
            Text("Three-finger vertical swipe to change volume.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap or click with 3 fingers for Middle Click.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Label("Status: Running", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                if settings.areGesturesDisabled {
                    Label("Trackpad Optimized", systemImage: "hand.tap.fill")
                        .foregroundColor(.blue)
                } else {
                    Label("Trackpad Optimization Recommended", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("The OS's three-finger swipe gestures may conflict with this app. Would you like to automatically disable them?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Optimize Trackpad Settings") {
                        settings.optimizeSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(40)
        .frame(width: 400, height: 420)
    }
}
