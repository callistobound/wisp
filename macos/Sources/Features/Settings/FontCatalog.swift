import AppKit
import CoreText

/// A variation axis, e.g. `wght` 100–900.
struct FontAxis {
    let tag: String
    let name: String
    let min: Double
    let max: Double
}

/// Installed fonts and what a family offers, for the font settings.
@MainActor
enum FontCatalog {
    private static var cachedFamilies: [Suggestion]?

    /// Installed families, monospaced first, each previewed in its own face.
    static func families() -> [Suggestion] {
        if let cachedFamilies { return cachedFamilies }
        var mono: [Suggestion] = []
        var other: [Suggestion] = []
        for family in NSFontManager.shared.availableFontFamilies where !family.hasPrefix(".") {
            let face = firstFace(family)
            if let face, face.isFixedPitch {
                mono.append(Suggestion(value: family, section: "Monospaced", fontName: face.fontName))
            } else {
                other.append(Suggestion(value: family, section: "Other fonts", fontName: face?.fontName))
            }
        }
        let all = mono + other
        cachedFamilies = all
        return all
    }

    /// Style names such as "Bold" or "Medium Italic".
    static func styles(family: String) -> [String] {
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        var seen = Set<String>()
        return members.compactMap { $0.count > 1 ? $0[1] as? String : nil }.filter { seen.insert($0).inserted }
    }

    /// OpenType feature tags the family's first face supports, with readable names.
    static func features(family: String) -> [(tag: String, name: String)] {
        guard let face = firstFace(family),
              let types = CTFontCopyFeatures(face as CTFont) as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var result: [(tag: String, name: String)] = []
        for type in types {
            let selectors = type[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? []
            for selector in selectors {
                guard let tag = selector[kCTFontOpenTypeFeatureTag as String] as? String,
                      seen.insert(tag).inserted else { continue }
                let name = selector[kCTFontFeatureSelectorNameKey as String] as? String
                    ?? type[kCTFontFeatureTypeNameKey as String] as? String ?? tag
                result.append((tag: tag, name: name))
            }
        }
        return result
    }

    /// Variation axes of the family's first face, e.g. `wght` 100–900.
    static func axes(family: String) -> [FontAxis] {
        guard let face = firstFace(family),
              let axes = CTFontCopyVariationAxes(face as CTFont) as? [[String: Any]] else { return [] }
        return axes.compactMap { axis in
            guard let id = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                  let min = axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber,
                  let max = axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber else { return nil }
            let tag = fourCC(id.uint32Value)
            return FontAxis(tag: tag, name: axis[kCTFontVariationAxisNameKey as String] as? String ?? tag,
                            min: min.doubleValue, max: max.doubleValue)
        }
    }

    /// The family a font option applies to: the first `font-family` entry for its
    /// variant (`-bold`, `-italic`, `-bold-italic`), else the regular one.
    static func primaryFamily(option: String, values: [String: [String]]) -> String? {
        let variant = ["-bold-italic", "-bold", "-italic"].first { option.hasSuffix($0) } ?? ""
        func first(_ key: String) -> String? {
            values[key]?.first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        return first("font-family\(variant)") ?? first("font-family")
    }

    private static func firstFace(_ family: String) -> NSFont? {
        guard let name = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first?.first as? String
        else { return nil }
        return NSFont(name: name, size: NSFont.systemFontSize)
    }

    private static func fourCC(_ value: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }, encoding: .ascii) ?? "\(value)"
    }
}
