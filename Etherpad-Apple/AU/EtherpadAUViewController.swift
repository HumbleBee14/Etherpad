import CoreAudioKit
import UIKit

/// Plugin UI: touch surface + shared patch defaults via `SynthPatchState` / `SynthTouchCoordinator`.
public final class EtherpadAUViewController: AUViewController {

    private let surface = TouchSurfaceView()
    private let touchCoordinator = SynthTouchCoordinator()
    private var patch = SynthPatchState.factoryDefault
    private var connected = false

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)

        touchCoordinator.engine = nil
        surface.delegate = touchCoordinator
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        connectToAudioUnitIfNeeded()
    }

    private func connectToAudioUnitIfNeeded() {
        guard !connected, let au = EtherpadAUContext.audioUnit else { return }
        connected = true
        touchCoordinator.engine = au.hostEngine
        patch.apply(to: au.hostEngine)
        surface.numberOfNotes = Double(patch.size)
    }

    public override func beginRequest(with context: NSExtensionContext) {
        // Required by NSExtensionRequestHandling on AUViewController principal class.
    }
}
