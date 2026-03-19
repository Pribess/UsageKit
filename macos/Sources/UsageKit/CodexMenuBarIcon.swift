import AppKit

private let codexLabelWidth: CGFloat = 14
private let codexBarWidth: CGFloat = 24
private let codexBarHeight: CGFloat = 5
private let codexRowGap: CGFloat = 3
private let codexLabelGap: CGFloat = 2
private let codexCornerRadius: CGFloat = 2
private let codexLogoSize: CGFloat = 16
private let codexLogoGap: CGFloat = 2
private let codexBarsWidth: CGFloat = codexLabelWidth + codexLabelGap + codexBarWidth + 2
private let codexIconWidth: CGFloat = codexLogoSize + codexLogoGap + codexBarsWidth
private let codexIconHeight: CGFloat = 18
private let codexFontSize: CGFloat = 8

private let codexLabelFont = NSFont.monospacedSystemFont(ofSize: codexFontSize, weight: .medium)
private let codexLabelAttrs: [NSAttributedString.Key: Any] = [
    .font: codexLabelFont,
    .foregroundColor: NSColor.black
]

func renderCodexIcon(
    pctPrimary: Double,
    pctSecondary: Double,
    primaryLabel: String,
    secondaryLabel: String
) -> NSImage {
    let image = NSImage(size: NSSize(width: codexIconWidth, height: codexIconHeight), flipped: true) { _ in
        let offset = codexLogoSize + codexLogoGap
        let barX = offset + codexLabelWidth + codexLabelGap
        let topY = (codexIconHeight - codexBarHeight * 2 - codexRowGap) / 2
        let bottomY = topY + codexBarHeight + codexRowGap

        drawCodexGlyph(x: 0, y: (codexIconHeight - codexLogoSize) / 2, size: codexLogoSize)

        drawCodexRow(label: primaryLabel, barX: barX, barY: topY, labelX: offset) { x, y in
            drawBar(x: x, y: y, width: codexBarWidth, height: codexBarHeight, cornerRadius: codexCornerRadius, pct: pctPrimary)
        }
        drawCodexRow(label: secondaryLabel, barX: barX, barY: bottomY, labelX: offset) { x, y in
            drawBar(x: x, y: y, width: codexBarWidth, height: codexBarHeight, cornerRadius: codexCornerRadius, pct: pctSecondary)
        }
        return true
    }
    image.isTemplate = true
    return image
}

func renderCodexUnauthenticatedIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: codexIconWidth, height: codexIconHeight), flipped: true) { _ in
        let offset = codexLogoSize + codexLogoGap
        let barX = offset + codexLabelWidth + codexLabelGap
        let topY = (codexIconHeight - codexBarHeight * 2 - codexRowGap) / 2
        let bottomY = topY + codexBarHeight + codexRowGap

        drawCodexGlyph(x: 0, y: (codexIconHeight - codexLogoSize) / 2, size: codexLogoSize)

        drawCodexRow(label: "--", barX: barX, barY: topY, labelX: offset) { x, y in
            drawDashedBar(x: x, y: y, width: codexBarWidth, height: codexBarHeight, cornerRadius: codexCornerRadius)
        }
        drawCodexRow(label: "--", barX: barX, barY: bottomY, labelX: offset) { x, y in
            drawDashedBar(x: x, y: y, width: codexBarWidth, height: codexBarHeight, cornerRadius: codexCornerRadius)
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Row drawing (dynamic labels)

private func drawCodexRow(
    label: String,
    barX: CGFloat,
    barY: CGFloat,
    labelX: CGFloat,
    drawBarFill: (CGFloat, CGFloat) -> Void
) {
    let str = NSAttributedString(string: label, attributes: codexLabelAttrs)
    let size = str.size()
    let labelY = barY + (codexBarHeight - size.height) / 2
    str.draw(at: NSPoint(x: labelX + codexLabelWidth - size.width, y: labelY))
    drawBarFill(barX, barY)
}

// MARK: - OpenAI logo (pre-rendered 512px template PNG)

private let openAILogoImage: NSImage? = {
    if let bundle = usageKitResourceBundle(),
       let png = bundle.url(forResource: "openai-logo", withExtension: "png") {
        return NSImage(contentsOf: png)
    }
    return nil
}()

private func drawCodexGlyph(x: CGFloat, y: CGFloat, size: CGFloat) {
    guard let logo = openAILogoImage else { return }
    logo.draw(in: NSRect(x: x, y: y, width: size, height: size))
}
