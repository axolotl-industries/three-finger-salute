import SwiftUI

struct VolumeHUD: View {
    let volume: Float
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill")
                .font(.system(size: 40))
                .foregroundColor(.primary.opacity(0.8))
                .contentTransition(.symbolEffect(.replace))
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(volume))
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 10)
        }
        .padding(25)
        .frame(width: 160, height: 160)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }
}
