// AboutViewController.swift — port of AboutActivity.java
//
// Renders the About page with native UIKit (UILabel / UITextView /
// UIImageView). Previously used WKWebView, which works but spawns a
// WebContent helper process that prints a steady stream of harmless-
// but-noisy system warnings (sandbox extension failures, missing
// com.apple.developer.web-browser-engine entitlements, RBS process-
// termination warnings). Switching to native UI eliminates that noise
// entirely and shaves a few MB of memory.

import UIKit

final class AboutViewController: UIViewController {

    private let bgColor   = UIColor(red: 0x3b/255, green: 0x44/255, blue: 0x4b/255, alpha: 1)
    private let textColor = UIColor(red: 0x50/255, green: 0x72/255, blue: 0xa7/255, alpha: 1)
    private let linkColor = UIColor(red: 0xe9/255, green: 0xd6/255, blue: 0x6b/255, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgColor

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = bgColor
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.layoutMargins = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)
        stack.isLayoutMarginsRelativeArrangement = true
        scroll.addSubview(stack)

        // Title
        let title = UILabel()
        title.text = "EtherSurface"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = textColor
        title.textAlignment = .center
        stack.addArrangedSubview(title)

        // Byline
        let byline = UILabel()
        byline.text = "By Paul Batchelor"
        byline.font = .systemFont(ofSize: 17, weight: .semibold)
        byline.textColor = textColor
        byline.textAlignment = .center
        stack.addArrangedSubview(byline)

        // Body paragraph
        let body = UILabel()
        body.text = "EtherSurface is a performance surface for touch devices. " +
                    "It is written using Csound 6 and the Csound iOS framework."
        body.font = .systemFont(ofSize: 16)
        body.textColor = textColor
        body.textAlignment = .center
        body.numberOfLines = 0
        stack.addArrangedSubview(body)

        // Link 1 — batchelorsounds.com
        stack.addArrangedSubview(makeLinkView(
            leading: "For more information about EtherSurface and other sound design toys and tools, visit ",
            linkText: "www.batchelorsounds.com",
            url: URL(string: "https://www.batchelorsounds.com")!))

        // Link 2 — csounds.com
        stack.addArrangedSubview(makeLinkView(
            leading: "For more information about Csound, visit ",
            linkText: "www.csounds.com",
            url: URL(string: "https://www.csounds.com")!))

        // Logo
        if let logo = UIImage(named: "logo_shadow") ?? UIImage(named: "logo") {
            let iv = UIImageView(image: logo)
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.heightAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
            stack.addArrangedSubview(iv)
        }

        // Layout
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        // Close button
        let closeBtn = UIButton(type: .close)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    /// Renders a centred paragraph with one tappable link inline.
    private func makeLinkView(leading: String, linkText: String, url: URL) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.textAlignment = .center

        let attr = NSMutableAttributedString(string: leading, attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: textColor,
        ])
        attr.append(NSAttributedString(string: linkText, attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: linkColor,
            .link: url,
        ]))
        tv.attributedText = attr
        tv.linkTextAttributes = [.foregroundColor: linkColor]
        return tv
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
