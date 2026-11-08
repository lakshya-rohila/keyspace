import Carbon.HIToolbox
import Foundation

enum HotKeyAction {
    case switchTo(SpaceKey)
    case move(SpaceKey)
    case pause
}

/// Global hotkeys via Carbon's RegisterEventHotKey.
/// Unlike a CGEventTap, this does NOT see every keystroke: macOS only wakes us
/// for the exact combos we registered, and it needs no Input Monitoring permission.
final class HotKeys {
    static var onPress: ((HotKeyAction) -> Void)?

    // Physical key codes (US layout positions). Not sequential, so spelled out.
    static let keyCodes: [SpaceKey: Int] = [
        "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
        "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
        "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
        "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
        "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
        "Z": kVK_ANSI_Z,
    ]

    static func carbonFlags(_ m: HotkeyModifier) -> UInt32 {
        switch m {
        case .option: UInt32(optionKey)
        case .controlOption: UInt32(controlKey | optionKey)
        case .control: UInt32(controlKey)
        }
    }

    // Hotkey id -> what it does. Rebuilt on every registration.
    private static var actions: [UInt32: HotKeyAction] = [:]
    private static let pauseID: UInt32 = 1

    private var spaceRefs: [EventHotKeyRef] = []
    private var pauseRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async {
                if let action = HotKeys.actions[id] { HotKeys.onPress?(action) }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    /// Registers <mod>+key (switch) and <mod>⇧+key (move) for each active key.
    /// Returns the keys whose shortcuts are taken by another app.
    @discardableResult
    func registerSpaceKeys(_ keys: [SpaceKey], _ modifier: HotkeyModifier) -> [SpaceKey] {
        unregisterSpaceKeys()
        let base = Self.carbonFlags(modifier)
        var failed: [SpaceKey] = []
        var nextID: UInt32 = 10
        for key in keys {
            guard let code = Self.keyCodes[key] else { continue }
            var ok = true
            for (flags, action) in [(base, HotKeyAction.switchTo(key)), (base | UInt32(shiftKey), .move(key))] {
                if let r = register(id: nextID, keyCode: code, modifiers: flags) {
                    spaceRefs.append(r)
                    Self.actions[nextID] = action
                } else { ok = false }
                nextID += 1
            }
            if !ok { failed.append(key) }
        }
        return failed
    }

    func unregisterSpaceKeys() {
        spaceRefs.forEach { UnregisterEventHotKey($0) }
        spaceRefs.removeAll()
        Self.actions = Self.actions.filter { $0.key == Self.pauseID }
    }

    /// <mod>⇧0 toggles pause. Stays registered while paused so you can resume.
    func registerPauseKey(_ modifier: HotkeyModifier) {
        if let pauseRef { UnregisterEventHotKey(pauseRef) }
        pauseRef = register(id: Self.pauseID, keyCode: kVK_ANSI_0,
                            modifiers: Self.carbonFlags(modifier) | UInt32(shiftKey))
        Self.actions[Self.pauseID] = .pause
    }

    private func register(id: UInt32, keyCode: Int, modifiers: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4B53_5043) /* 'KSPC' */, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("Keyspace: hotkey id \(id) unavailable (status \(status)) — another app may own it")
            return nil
        }
        return ref
    }
}
