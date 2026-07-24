import AppKit

private let iconHeight: CGFloat = 18
private let logoSize: CGFloat = 12
private let logoGap: CGFloat = 3
private let labelWidth: CGFloat = 17
private let labelGap: CGFloat = 2
private let barWidth: CGFloat = 24
private let barHeight: CGFloat = 5
private let rowGap: CGFloat = 3
private let capsuleWidth: CGFloat = 48
private let capsuleHeight: CGFloat = 14
private let fontSize: CGFloat = 8

func renderMenuBarIcon(
    provider: UsageProvider,
    metrics: [UsagePresentationMetric],
    style: MenuBarVisualizationStyle,
    isConfigured: Bool
) -> NSImage {
    switch style {
    case .bars:
        return renderBarsIcon(
            provider: provider,
            metrics: metrics,
            isConfigured: isConfigured
        )
    case .capsule:
        return renderCapsuleIcon(
            provider: provider,
            metrics: metrics,
            isConfigured: isConfigured
        )
    }
}

private func renderBarsIcon(
    provider: UsageProvider,
    metrics: [UsagePresentationMetric],
    isConfigured: Bool
) -> NSImage {
    let contentWidth = labelWidth + labelGap + barWidth
    let iconWidth = logoSize + logoGap + contentWidth
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        drawProviderLogo(
            provider,
            x: 0,
            y: (iconHeight - logoSize) / 2,
            size: logoSize
        )

        let barX = logoSize + logoGap + labelWidth + labelGap
        let labelX = logoSize + logoGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let rows = normalizedMetrics(metrics)

        for (index, metric) in rows.enumerated() {
            let rowY = topY + CGFloat(index) * (barHeight + rowGap)
            drawText(
                metric?.shortLabel ?? "—",
                in: NSRect(x: labelX, y: rowY - 2, width: labelWidth, height: barHeight + 4),
                alignment: .right
            )

            guard isConfigured, let metric else {
                drawDashedBar(
                    x: barX,
                    y: rowY,
                    width: barWidth,
                    height: barHeight,
                    cornerRadius: 2
                )
                continue
            }

            switch metric.kind {
            case .percentage(let percent):
                drawBar(
                    x: barX,
                    y: rowY,
                    width: barWidth,
                    height: barHeight,
                    cornerRadius: 2,
                    pct: (percent ?? 0) / 100
                )
            case .count(let count):
                drawCountValue(
                    count,
                    in: NSRect(x: barX, y: rowY - 2, width: barWidth, height: barHeight + 4)
                )
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

private func renderCapsuleIcon(
    provider: UsageProvider,
    metrics: [UsagePresentationMetric],
    isConfigured: Bool
) -> NSImage {
    let iconWidth = logoSize + logoGap + capsuleWidth
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        drawProviderLogo(
            provider,
            x: 0,
            y: (iconHeight - logoSize) / 2,
            size: logoSize
        )

        let capsuleX = logoSize + logoGap
        let capsuleY = (iconHeight - capsuleHeight) / 2
        drawSplitCapsule(
            metrics: normalizedMetrics(metrics),
            x: capsuleX,
            y: capsuleY,
            width: capsuleWidth,
            height: capsuleHeight,
            isConfigured: isConfigured
        )
        return true
    }
    image.isTemplate = true
    return image
}

private func normalizedMetrics(
    _ metrics: [UsagePresentationMetric]
) -> [UsagePresentationMetric?] {
    let values = Array(metrics.prefix(2)).map(Optional.some)
    return values + Array(repeating: nil, count: max(0, 2 - values.count))
}

private func drawSplitCapsule(
    metrics: [UsagePresentationMetric?],
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    isConfigured: Bool
) {
    let rect = NSRect(x: x, y: y, width: width, height: height)
    let outerPath = NSBezierPath(
        roundedRect: rect,
        xRadius: height / 2,
        yRadius: height / 2
    )

    NSColor.black.withAlphaComponent(0.10).setFill()
    outerPath.fill()

    NSGraphicsContext.saveGraphicsState()
    outerPath.addClip()

    let cellWidth = width / 2
    for (index, metric) in metrics.enumerated() {
        let cellRect = NSRect(
            x: x + CGFloat(index) * cellWidth,
            y: y,
            width: cellWidth,
            height: height
        )
        guard isConfigured, let metric else {
            drawCellPlaceholder(in: cellRect)
            continue
        }

        switch metric.kind {
        case .percentage(let percent):
            let progress = min(max((percent ?? 0) / 100, 0), 1)
            let fillRect = NSRect(
                x: cellRect.minX,
                y: cellRect.minY,
                width: cellRect.width * progress,
                height: cellRect.height
            )
            NSColor.black.withAlphaComponent(0.68).setFill()
            fillRect.fill()
        case .count(let count):
            drawText(
                count.map { "\(metric.shortLabel)\($0)" } ?? "—",
                in: cellRect.insetBy(dx: 2, dy: 1),
                alignment: .center,
                weight: .semibold
            )
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.42).setStroke()
    outerPath.lineWidth = 1
    outerPath.stroke()

    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: x + width / 2, y: y + 2))
    divider.line(to: NSPoint(x: x + width / 2, y: y + height - 2))
    divider.lineWidth = 1
    NSColor.black.withAlphaComponent(0.35).setStroke()
    divider.stroke()
}

private func drawCellPlaceholder(in rect: NSRect) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + 5, y: rect.midY))
    path.line(to: NSPoint(x: rect.maxX - 5, y: rect.midY))
    path.lineWidth = 1
    path.setLineDash([2, 2], count: 2, phase: 0)
    NSColor.black.withAlphaComponent(0.25).setStroke()
    path.stroke()
}

private func drawCountValue(_ count: Int?, in rect: NSRect) {
    drawText(
        count.map(String.init) ?? "—",
        in: rect,
        alignment: .left,
        weight: .semibold
    )
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    alignment: NSTextAlignment,
    weight: NSFont.Weight = .medium
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let string = NSAttributedString(
        string: text,
        attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
    )
    string.draw(in: rect)
}

private func drawBar(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat,
    pct: Double
) {
    let bgRect = NSRect(x: x, y: y, width: width, height: height)
    let bgPath = NSBezierPath(
        roundedRect: bgRect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    NSColor.black.withAlphaComponent(0.25).setFill()
    bgPath.fill()

    let clampedPct = max(0, min(1, pct))
    guard clampedPct > 0 else { return }

    let fillRect = NSRect(
        x: x,
        y: y,
        width: width * clampedPct,
        height: height
    )
    let fillPath = NSBezierPath(
        roundedRect: fillRect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    NSColor.black.setFill()
    fillPath.fill()
}

private func drawDashedBar(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat
) {
    let rect = NSRect(x: x, y: y, width: width, height: height)
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    NSColor.black.withAlphaComponent(0.25).setStroke()
    path.lineWidth = 1
    path.setLineDash([2, 2], count: 2, phase: 0)
    path.stroke()
}

private func drawProviderLogo(
    _ provider: UsageProvider,
    x: CGFloat,
    y: CGFloat,
    size: CGFloat
) {
    if provider == .claude, let claudeLogoImage {
        claudeLogoImage.draw(
            in: NSRect(x: x, y: y, width: size, height: size)
        )
        return
    }

    let configuration = NSImage.SymbolConfiguration(
        pointSize: size,
        weight: .medium
    )
    let symbol = NSImage(
        systemSymbolName: provider.systemImage,
        accessibilityDescription: provider.settingsName
    )?.withSymbolConfiguration(configuration)
    symbol?.draw(
        in: NSRect(x: x, y: y, width: size, height: size)
    )
}

private let claudeLogoImage: NSImage? = {
    if let bundle = agentUsageBarResourceBundle(),
       let png = bundle.url(forResource: "claude-logo", withExtension: "png") {
        return NSImage(contentsOf: png)
    }
    return nil
}()
