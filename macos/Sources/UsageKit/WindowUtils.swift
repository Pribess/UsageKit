import AppKit

func dismissOtherMenuBarPanels() {
    DispatchQueue.main.async {
        for window in NSApp.windows where window is NSPanel && !window.isKeyWindow {
            window.orderOut(nil)
        }
    }
}
