import AppKit

// Custom NSView containing a horizontal NSSlider and a percentage label,
// intended to be used as NSMenuItem.view inside an NSStatusItem menu.
final class VolumeSliderView: NSView {
    var onChanged: ((Float) -> Void)?

    private let slider    = NSSlider()
    private let pctLabel  = NSTextField(labelWithString: "")

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        slider.sliderType = .linear
        slider.minValue   = 0
        slider.maxValue   = 1
        slider.isContinuous = true
        slider.target     = self
        slider.action     = #selector(sliderMoved)
        slider.frame      = NSRect(x: 8, y: 5, width: 166, height: 16)
        addSubview(slider)

        pctLabel.font      = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pctLabel.alignment = .right
        pctLabel.frame     = NSRect(x: 178, y: 5, width: 38, height: 16)
        addSubview(pctLabel)
    }

    // MARK: - Public

    var isEnabled: Bool = true {
        didSet {
            slider.isEnabled  = isEnabled
            pctLabel.textColor = isEnabled ? .labelColor : .tertiaryLabelColor
        }
    }

    func setVolume(_ level: Float, label: String) {
        slider.floatValue    = level
        pctLabel.stringValue = label
    }

    // MARK: - Action

    @objc private func sliderMoved() {
        let vol = slider.floatValue
        pctLabel.stringValue = "\(Int((vol * 100).rounded()))%"
        onChanged?(vol)
    }
}
