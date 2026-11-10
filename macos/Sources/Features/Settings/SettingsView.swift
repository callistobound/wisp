import SwiftUI

struct SettingsView: View {
    var body: some View {
        HStack {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text("Coming Soon. 🚧").font(.title)
                Text("You can't configure settings in the GUI yet. To modify settings, " +
                     "edit the file at $HOME/.config/ghostty/config.ghostty and restart Ghostty.")
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
