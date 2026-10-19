import SwiftUI
import UIKit

/// Hosts the SwiftUI keys. `hasDictationKey` stays false so iOS keeps Apple's own dictation mic in
/// the strip below the keyboard, which is where every nudge points.
final class KeyboardViewController: UIInputViewController {
    private lazy var model = KeyboardModel(
        autocapitalizes: autocapitalizes,
        insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
        deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() }
    )

    /// Whether the field wants sentence capitals. A trait of the field, not its text.
    private var autocapitalizes: Bool {
        textDocumentProxy.autocapitalizationType.map { $0 == .sentences || $0 == .words || $0 == .allCharacters } ?? true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KeyboardView(
            model: model,
            showsGlobeKey: needsInputModeSwitchKey,
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() }
        ))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: KeyboardView.height),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refresh(autocapitalizes: autocapitalizes)
    }
}
