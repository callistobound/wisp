import SwiftUI

/// An option made of on/off flags, written `a,no-b,c` (or `true`/`false` for all).
struct FlagSet: Equatable {
    var on: Set<String>

    init(names: [String], text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "true": on = Set(names)
        case "false": on = []
        default:
            let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            on = Set(parts.filter { names.contains($0) })
        }
    }

    /// Every flag, in declaration order, `no-` for off.
    func text(names: [String]) -> String {
        names.map { on.contains($0) ? $0 : "no-\($0)" }.joined(separator: ",")
    }
}

/// One checkbox per flag; each toggle saves the whole value.
struct FlagsControl: View {
    let names: [String]
    let current: String
    let save: (String) -> Void

    var body: some View {
        let flags = FlagSet(names: names, text: current)
        HStack(spacing: 14) {
            ForEach(names, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { flags.on.contains(name) },
                    set: { isOn in
                        var next = flags
                        if isOn { next.on.insert(name) } else { next.on.remove(name) }
                        save(next.text(names: names))
                    }))
                .toggleStyle(.checkbox)
            }
        }
    }
}
