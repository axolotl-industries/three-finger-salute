// Three Finger Salute
import SwiftUI

struct ContentView: View {
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
                Label("Menu Bar icon is active", systemImage: "menubar.arrow.up.rectangle")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(40)
        .frame(width: 400, height: 320)
    }
}
