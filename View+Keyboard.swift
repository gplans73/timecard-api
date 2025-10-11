import SwiftUI
#if canImport(UIKit)
extension View {
    /// Dismisses the current first responder (keyboard)
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
#endif
