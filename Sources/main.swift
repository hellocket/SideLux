// SideLux — a tiny menu bar app for external display brightness (Apple Silicon)
// - DDC/CI connections (USB-C, DisplayPort): controls the monitor's own brightness and volume
// - Non-DDC connections (e.g. HDMI): software brightness via gamma; volume unavailable
import Cocoa
import IOKit
import ServiceManagement

/// GitHub repository used by "Check for Updates…" (owner/name)
let githubRepo = "hellocket/SideLux"

// MARK: - Private IOAVService API (Apple Silicon DDC)

typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
let avCreate = unsafeBitCast(dlsym(ioKit, "IOAVServiceCreateWithService"), to: CreateFn.self)
let avWrite = unsafeBitCast(dlsym(ioKit, "IOAVServiceWriteI2C"), to: I2CFn.self)
let avRead = unsafeBitCast(dlsym(ioKit, "IOAVServiceReadI2C"), to: I2CFn.self)

enum Control: UInt8 {
    case brightness = 0x10
    case volume = 0x62
    var key: String { self == .brightness ? "brightness" : "volume" }
}

final class Display {
    let service: CFTypeRef?
    let displayID: CGDirectDisplayID
    let name: String
    var maxValue: [Control: Int] = [.brightness: 100, .volume: 100]
    /// Whether the monitor answers DDC. Decided on the first brightness read (false over HDMI, many docks, etc.)
    var ddc = true
    private let queue = DispatchQueue(label: "ddc")
    private var pending: [Control: Int] = [:]
    private var busy = false

    init(service: CFTypeRef?, displayID: CGDirectDisplayID, name: String) {
        self.service = service; self.displayID = displayID; self.name = name
        if service == nil { ddc = false }
    }

    func saved(_ c: Control) -> Int {
        UserDefaults.standard.object(forKey: "\(c.key).\(name)") as? Int ?? 50
    }
    func save(_ c: Control, _ v: Int) { UserDefaults.standard.set(v, forKey: "\(c.key).\(name)") }

    /// Software brightness: dim through the gamma curve (never below 15% so the screen stays visible)
    func applyGamma(_ v: Int) {
        let f = Float(0.15 + 0.85 * Double(v) / Double(maxValue[.brightness]!))
        CGSetDisplayTransferByFormula(displayID, 0, f, 1, 0, f, 1, 0, f, 1)
    }

    private func send(_ bytes: [UInt8]) -> Bool {
        guard let service else { return false }
        var packet = bytes
        var checksum: UInt8 = 0x6E ^ 0x51
        for b in packet { checksum ^= b }
        packet.append(checksum)
        for _ in 0..<3 {
            usleep(10_000)
            if avWrite(service, 0x37, 0x51, &packet, UInt32(packet.count)) == KERN_SUCCESS { return true }
        }
        return false
    }

    /// Reads the current value (call off the main thread). nil on failure.
    func read(_ c: Control) -> Int? {
        guard ddc, let service else { return nil }
        for _ in 0..<3 {
            guard send([0x82, 0x01, c.rawValue]) else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard avRead(service, 0x37, 0x51, &reply, UInt32(reply.count)) == KERN_SUCCESS else { continue }
            // reply: [src, len, 0x02, result, vcp, type, maxH, maxL, curH, curL, chk]
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == c.rawValue else { continue }
            let maxV = Int(reply[6]) << 8 | Int(reply[7])
            if maxV > 0 { maxValue[c] = maxV }
            return Int(reply[8]) << 8 | Int(reply[9])
        }
        if c == .brightness { ddc = false }   // no answer even for brightness → treat as non-DDC
        return nil
    }

    /// Only the latest value is sent while the slider moves, so the monitor isn't flooded
    func set(_ c: Control, _ value: Int) {
        save(c, value)
        if c == .brightness && !ddc { applyGamma(value); return }
        guard ddc else { return }
        queue.async {
            self.pending[c] = value
            guard !self.busy else { return }
            self.busy = true
            while let (ctl, v) = self.pending.first.map({ ($0.key, $0.value) }) {
                self.pending[ctl] = nil
                _ = self.send([0x84, 0x03, ctl.rawValue, UInt8(v >> 8), UInt8(v & 0xFF)])
                usleep(30_000)
            }
            self.busy = false
        }
    }
}

func findExternalDisplays() -> [Display] {
    var services: [CFTypeRef] = []
    var iter: io_iterator_t = 0
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS {
        while case let entry = IOIteratorNext(iter), entry != 0 {
            defer { IOObjectRelease(entry) }
            let loc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if loc == "External", let svc = avCreate(kCFAllocatorDefault, entry)?.takeRetainedValue() { services.append(svc) }
        }
        IOObjectRelease(iter)
    }
    let screens = NSScreen.screens.compactMap { s -> (CGDirectDisplayID, String)? in
        guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              CGDisplayIsBuiltin(id) == 0 else { return nil }
        return (id, s.localizedName)
    }
    return screens.enumerated().map { i, sc in
        Display(service: i < services.count ? services[i] : nil, displayID: sc.0, name: sc.1)
    }
}

// MARK: - Menu bar UI

/// All text in the menu uses the same size as regular menu items
let menuFontSize = NSFont.menuFont(ofSize: 0).pointSize
let rowWidth: CGFloat = 252   // slider a bit longer than the "…DisplayPort" line
let rightMargin: CGFloat = 23.5  // space after a two-digit value
let twoDigitWidth: CGFloat = 14
// Columns measured from screenshots of native menu items (points from the menu's left edge)
let checkColumnCenter: CGFloat = 17.75   // center of the ✓ column
let checkColumnLeft: CGFloat = 13.5      // left edge of the ✓ → the display name starts here
/// Native item titles start at 31pt; a leading three-per-em space (1/3 em) pushes them right for a roomier ✓ → text gap
let titlePrefix = "\u{2004}"
let titleShift = (titlePrefix as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
let textColumn: CGFloat = 31 + titleShift // where item titles start → notes and sliders start here too
let labelInset: CGFloat = 3              // NSTextField draws its text this far right of its frame
let valueWidth: CGFloat = 22             // room for "100"
let valueGap: CGFloat = 11               // slider→value gap, same as the icon→slider gap

/// Slider that does its own mouse tracking inside the menu:
/// - click anywhere on the track to jump there, then keep dragging (even past the ends)
/// - the mouse-up is consumed here, so the menu stays open after adjusting
/// - scroll (trackpad or wheel) over it to adjust
final class MenuSlider: NSSlider {
    private var scrollRemainder: Double = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func value(at event: NSEvent) -> Double {
        let p = convert(event.locationInWindow, from: nil)
        let knob = (cell as? NSSliderCell)?.knobThickness ?? 20
        let start = bounds.minX + knob / 2, width = bounds.width - knob
        let f = min(max((p.x - start) / width, 0), 1)
        return (minValue + f * (maxValue - minValue)).rounded()
    }

    private func update(_ v: Double) {
        let v = min(max(v, minValue), maxValue)
        guard v != doubleValue else { return }
        doubleValue = v
        sendAction(action, to: target)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        update(value(at: event))
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            update(value(at: e))
            if e.type == .leftMouseUp { break }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        // Physical "up" (or right) always brightens, whatever the natural-scrolling setting
        let sign: Double = event.isDirectionInvertedFromDevice ? -1 : 1
        let raw = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? Double(event.scrollingDeltaY) : -Double(event.scrollingDeltaX)
        let step = event.hasPreciseScrollingDeltas ? raw / 4 : raw * 2   // trackpad: fine steps, wheel: 2 per notch
        scrollRemainder += sign * step
        let whole = scrollRemainder.rounded(.towardZero)
        guard whole != 0 else { return }
        scrollRemainder -= whole
        update(doubleValue + whole)
    }
}

/// One slider line: icon + slider + value
final class ControlLine: NSObject {
    let control: Control
    let display: Display
    let icon = NSImageView()
    let slider = MenuSlider()
    let value = NSTextField(labelWithString: "–")
    let note = NSTextField(labelWithString: "Requires USB-C or DisplayPort")
    private var beforeMute: Int?

    init(_ control: Control, display: Display, y: CGFloat, in view: NSView) {
        self.control = control; self.display = display
        super.init()
        // Sun matches the menu bar icon; the speaker symbol is weighted to match the sun's 1.2pt rays
        // Both drawn at 90% size inside their original canvas, so centers don't move
        let base = control == .brightness ? menuBarIcon()
            : NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Volume")!
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))!
        icon.image = scaledTemplate(base, 0.9)
        icon.imageScaling = .scaleNone
        // Both glyphs centered at 18pt (on the 2x pixel grid, next to the ✓ center at 17.75pt).
        // The speaker symbol's drawing sits ~0.5pt left of its image center, hence the different origin.
        let size = icon.image?.size ?? .zero
        let originX: CGFloat = control == .brightness ? 10.0 : 9.5
        icon.frame = NSRect(x: originX, y: y + ((22 - size.height) / 2).rounded(.down), width: size.width, height: size.height)
        let sliderStart = textColumn          // the track starts right at the frame's edge
        let sliderEnd = rowWidth - rightMargin - twoDigitWidth - valueGap
        slider.frame = NSRect(x: sliderStart, y: y, width: sliderEnd - sliderStart, height: 22)
        slider.minValue = 0; slider.maxValue = 100
        slider.isContinuous = true
        slider.isEnabled = false
        value.font = .monospacedDigitSystemFont(ofSize: menuFontSize, weight: .regular)
        value.alignment = .left   // fixed gap after the slider, whatever the digit count
        value.frame = NSRect(x: sliderEnd + valueGap - labelInset, y: y + 2, width: valueWidth + 8, height: 18)
        note.font = .systemFont(ofSize: menuFontSize)
        note.frame = NSRect(x: textColumn - labelInset, y: y + 0.5,   // optically centered on the speaker icon
                             width: rowWidth - textColumn, height: 18)
        note.isHidden = true
        // One gray only: icons, values and notes all use the same secondary color
        icon.contentTintColor = .secondaryLabelColor
        value.textColor = .secondaryLabelColor
        note.textColor = .secondaryLabelColor
        [icon, slider, value, note].forEach(view.addSubview)
    }

    /// nil = unsupported (volume without DDC)
    func show(_ v: Int?) {
        let supported = v != nil
        slider.isHidden = !supported; value.isHidden = !supported; note.isHidden = supported
        guard let v else { return }
        slider.maxValue = Double(display.maxValue[control]!)
        slider.doubleValue = Double(v)
        value.stringValue = "\(v)"
        slider.isEnabled = true
    }

    @objc func changed() {
        let v = Int(slider.doubleValue.rounded())
        value.stringValue = "\(v)"
        beforeMute = nil
        display.set(control, v)
    }

    /// For shortcuts: step by 1/16
    func nudge(up: Bool) {
        let maxV = display.maxValue[control]!
        let step = max(1, maxV / 16)
        let cur = slider.isEnabled ? Int(slider.doubleValue.rounded()) : display.saved(control)
        slider.doubleValue = Double(max(0, min(maxV, cur + (up ? step : -step))))
        changed()
    }

    /// Mute toggle: drops to 0, pressing again restores the previous value
    func toggleMute() {
        let cur = Int(slider.doubleValue.rounded())
        let restore = beforeMute
        slider.doubleValue = Double(restore ?? 0)
        changed()
        beforeMute = restore == nil ? max(cur, 1) : nil
    }
}

final class DisplayRow: NSView {
    let display: Display
    let title = NSTextField(labelWithString: "")
    var brightness: ControlLine!
    var volume: ControlLine!

    /// Lets text blend with the menu material exactly like native menu items
    override var allowsVibrancy: Bool { true }

    init(display: Display) {
        self.display = display
        super.init(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 82))
        title.stringValue = display.name
        title.font = .systemFont(ofSize: menuFontSize, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: checkColumnLeft - labelInset, y: 58, width: rowWidth - checkColumnLeft - 12, height: 18)
        addSubview(title)
        brightness = ControlLine(.brightness, display: display, y: 30, in: self)
        volume = ControlLine(.volume, display: display, y: 4, in: self)
        for line in [brightness!, volume!] { line.slider.target = line; line.slider.action = #selector(ControlLine.changed) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        DispatchQueue.global().async {
            let b = self.display.read(.brightness)
            let v = self.display.ddc ? self.display.read(.volume) : nil
            DispatchQueue.main.async {
                let d = self.display
                if d.ddc {
                    self.brightness.show(b ?? d.saved(.brightness))
                    self.volume.show(v ?? d.saved(.volume))
                } else {
                    let saved = d.saved(.brightness)
                    d.applyGamma(saved)
                    self.brightness.show(saved)
                    self.volume.show(nil)
                }
            }
        }
    }
}

// MARK: - Shortcuts: ⌃ + brightness keys (F1/F2), ⌃ + volume keys (F10/F11/F12)

let NX_SYSDEFINED: UInt32 = 14
let KEY_SOUND_UP = 0, KEY_SOUND_DOWN = 1, KEY_BRIGHTNESS_UP = 2, KEY_BRIGHTNESS_DOWN = 3, KEY_MUTE = 7

func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = delegate.keyTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    }
    // Keys pressed without ⌃ go to macOS as usual (built-in display, speakers)
    guard type.rawValue == NX_SYSDEFINED, event.flags.contains(.maskControl),
          let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8,
          let row = delegate.targetRow() else { return pass }
    let key = (ns.data1 & 0xFFFF0000) >> 16
    let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
    let action: (() -> Void)?
    switch key {
    case KEY_BRIGHTNESS_UP, KEY_BRIGHTNESS_DOWN:
        action = { row.brightness.nudge(up: key == KEY_BRIGHTNESS_UP) }
    case KEY_SOUND_UP, KEY_SOUND_DOWN, KEY_MUTE:
        guard row.display.ddc else { return pass }   // no DDC volume → let macOS handle it
        action = key == KEY_MUTE ? { row.volume.toggleMute() } : { row.volume.nudge(up: key == KEY_SOUND_UP) }
    default:
        return pass
    }
    if isDown, let action { DispatchQueue.main.async(execute: action) }
    return nil
}

/// Same-size template image with its drawing scaled about the center
func scaledTemplate(_ image: NSImage, _ factor: CGFloat) -> NSImage {
    let size = image.size
    let out = NSImage(size: size, flipped: false) { rect in
        let w = size.width * factor, h = size.height * factor
        image.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        return true
    }
    out.isTemplate = true
    return out
}

/// Native item title nudged right by `titleShift`, for a roomier ✓ → text gap
func menuTitle(_ text: String) -> NSAttributedString {
    NSAttributedString(string: titlePrefix + text, attributes: [.font: NSFont.menuFont(ofSize: 0)])
}

/// Menu bar icon: 8 rays + small center dot (template image, adapts to light/dark)
func menuBarIcon() -> NSImage {
    // Ray position and weight follow SF Symbol "sun.max" (4.7–7.0pt from center, 1.2pt wide)
    let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
        let c = NSPoint(x: 8, y: 8)
        NSColor.black.set()
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.15, y: c.y - 2.15, width: 4.3, height: 4.3)).fill()
        let rays = NSBezierPath()
        rays.lineWidth = 1.2
        rays.lineCapStyle = .round
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            rays.move(to: NSPoint(x: c.x + cos(a) * 5.3, y: c.y + sin(a) * 5.3))
            rays.line(to: NSPoint(x: c.x + cos(a) * 6.4, y: c.y + sin(a) * 6.4))
        }
        rays.stroke()
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "Brightness"
    return img
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    var rows: [DisplayRow] = []
    var keyTap: CFMachPort?
    var keysEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "brightnessKeys") }
        set { UserDefaults.standard.set(newValue, forKey: "brightnessKeys") }
    }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem.button?.image = menuBarIcon()
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if keysEnabled && !startKeyTap(prompt: false) { waitForPermission() }
    }

    func applicationWillTerminate(_ n: Notification) { CGDisplayRestoreColorSyncSettings() }

    @objc func rebuild() {
        menu.removeAllItems()
        rows = findExternalDisplays().map(DisplayRow.init)
        if rows.isEmpty {
            let item = NSMenuItem(title: "No External Display", action: nil, keyEquivalent: "")
        item.attributedTitle = menuTitle(item.title)
            item.isEnabled = false
            menu.addItem(item)
        }
        for row in rows {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
            row.refresh()
        }
        menu.addItem(.separator())
        let keys = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(toggleKeys(_:)), keyEquivalent: "")
        keys.attributedTitle = menuTitle(keys.title)
        keys.target = self
        keys.state = keysEnabled ? .on : .off
        keys.toolTip = "⌃F1 / ⌃F2  Brightness\n⌃F11 / ⌃F12  Volume\n⌃F10  Mute\nRequires Accessibility permission."
        menu.addItem(keys)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.attributedTitle = menuTitle(login.title)
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.attributedTitle = menuTitle(update.title)
        update.target = self
        menu.addItem(update)
        let quit = NSMenuItem(title: "Quit SideLux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.attributedTitle = menuTitle(quit.title)
        menu.addItem(quit)
        // Small spacer so the bottom margin matches the top
        let spacer = NSMenuItem()
        spacer.view = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 4))
        menu.addItem(spacer)
    }

    func menuWillOpen(_ menu: NSMenu) { rows.forEach { $0.refresh() } }

    /// With several external displays, the one under the mouse; otherwise the first one
    func targetRow() -> DisplayRow? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let row = rows.first(where: { $0.display.displayID == id }) { return row }
        return rows.first
    }

    // MARK: Shortcuts

    /// true on success. false without Accessibility permission (shows the system prompt when `prompt`)
    @discardableResult
    func startKeyTap(prompt: Bool) -> Bool {
        if keyTap != nil { return true }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts),
              let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1) << CGEventMask(NX_SYSDEFINED),
                                          callback: keyTapCallback, userInfo: nil) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        return true
    }

    func stopKeyTap() {
        if let tap = keyTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        keyTap = nil
    }

    @objc func toggleKeys(_ sender: NSMenuItem) {
        if keysEnabled {
            keysEnabled = false; stopKeyTap(); sender.state = .off
        } else {
            keysEnabled = true; sender.state = .on
            if !startKeyTap(prompt: true) { waitForPermission() }
        }
    }

    /// Turns shortcuts on as soon as permission is granted, without a relaunch
    func waitForPermission() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { t in
            if !self.keysEnabled || self.startKeyTap(prompt: false) { t.invalidate() }
        }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister(); sender.state = .off }
            else { try SMAppService.mainApp.register(); sender.state = .on }
        } catch { NSSound.beep() }
    }

    // MARK: Updates (GitHub Releases)

    @objc func checkForUpdates() {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String).map { $0.hasPrefix("v") || $0.hasPrefix("V") ? String($0.dropFirst()) : $0 }
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async { self.showUpdateResult(latest: tag, page: page) }
        }.resume()
    }

    func showUpdateResult(latest: String?, page: URL?) {
        let alert = NSAlert()
        if let latest, latest.compare(version, options: .numeric) == .orderedDescending {
            alert.messageText = "SideLux \(latest) is available"
            alert.informativeText = "You have version \(version)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
        } else if latest != nil {
            alert.messageText = "You're up to date"
            alert.informativeText = "SideLux \(version) is the latest version."
        } else {
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "Check your internet connection and try again."
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, alert.buttons.count > 1 {
            NSWorkspace.shared.open(page ?? URL(string: "https://github.com/\(githubRepo)/releases/latest")!)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
