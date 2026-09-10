//
//  GlobalHotKey.swift
//  dewey
//

import Carbon.HIToolbox
import Cocoa

/// A system-wide hot key, via the Carbon RegisterEventHotKey API. Unlike an
/// NSEvent global monitor, this requires no Accessibility permission.
final class GlobalHotKey {
    private let onPress: () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    /// - Parameter keyCode: a Carbon virtual key code, e.g. `kVK_Space`.
    init?(
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags,
        onPress: @escaping () -> Void
    ) {
        self.onPress = onPress

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalHotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandlerRef
        )
        guard installStatus == noErr else { return nil }
        eventHandlerRef = installedHandlerRef

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x44_57_45_59), // "DWEY"
            id: 1
        )
        var registeredHotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(from: modifierFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registeredHotKeyRef
        )
        guard registerStatus == noErr else {
            if let installedHandlerRef {
                RemoveEventHandler(installedHandlerRef)
            }
            return nil
        }
        hotKeyRef = registeredHotKeyRef
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    fileprivate func handlePress() {
        onPress()
    }

    private static func carbonModifiers(
        from modifierFlags: NSEvent.ModifierFlags
    ) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        return carbonModifiers
    }
}

// MARK: -

private nonisolated func globalHotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }

    // Carbon dispatches hot key events on the main thread.
    MainActor.assumeIsolated {
        Unmanaged<GlobalHotKey>.fromOpaque(userData)
            .takeUnretainedValue()
            .handlePress()
    }
    return noErr
}
