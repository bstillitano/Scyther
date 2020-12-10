//
//  MVVMController.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

internal class MenuViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var viewModel: MenuViewModel?

    // MARK: - Init
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupUI()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        //Setup Table View
        tableView.delegate = self
        tableView.dataSource = self

        //Register Table View Cells
        tableView.register(DefaultCell.self, forCellReuseIdentifier: "default")
        tableView.register(DeviceTableViewCell.self, forCellReuseIdentifier: "deviceHeader")
        tableView.register(ActionTableViewCell.self, forCellReuseIdentifier: "action")
        tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: "subtitle")

        view.addSubview(tableView)

        // Close button
        if #available(iOS 13.0, *) {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissMenu))
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissMenu))
        }
    }

    private func setupConstraints() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[subview]-0-|",
                                                           options: .directionLeadingToTrailing,
                                                           metrics: nil,
                                                           views: ["subview": tableView]))
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[subview]-0-|",
                                                           options: .directionLeadingToTrailing,
                                                           metrics: nil,
                                                           views: ["subview": tableView]))
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.setAnimationsEnabled(false)
        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        UIView.setAnimationsEnabled(true)
    }

    // MARK: - Configure
    internal func configure(with viewModel: MenuViewModel) {
        self.viewModel = viewModel

        title = viewModel.title
        navigationItem.title = viewModel.title

        tableView.reloadData()
    }

    // MARK: - Actions
    @objc
    private func dismissMenu() {
        navigationController?.dismiss(animated: true, completion: nil)
    }

    @objc
    private func warnAboutDeviceLogs(sender: UIView?) {

        // If they've previously told us not to ask again, go straight to the share sheet
        if UserDefaults.standard.bool(forKey: "dontWarnForLogExport") == true {
            shareDeviceLogs(sender: sender)
            return
        }

        let alertController = UIAlertController(title: "⚠️ WARNING ⚠️", message: "Please be aware that no effort has been made to mask content captured. \n\nThis may include but not limited to: Email adresses, Passwords, Authentication details, Payment details and more..", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        // "Continue" action
        alertController.addAction(UIAlertAction(title: "Continue", style: .destructive, handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.shareDeviceLogs(sender: sender)
            }
        }))

        // "Don't ask again" action
        alertController.addAction(UIAlertAction(title: "Don't ask again", style: .default, handler: { [weak self] _ in
            UserDefaults.standard.set(true, forKey: "dontWarnForLogExport")

            DispatchQueue.main.async {
                self?.shareDeviceLogs(sender: sender)
            }
        }))

        present(alertController, animated: true, completion: nil)
    }

    private func shareDiagnosticsBundle(sender: UIView?) {
//        DiagnosticsBundle.generate { result in
//            switch result {
//                case .success(let bundle):
//                    guard let exportedURL = bundle.export(using: InternalMenu.default.diagnosticsConfig) else { return }
//                    DispatchQueue.main.async { [weak self] in
//                        self?.presentActivityController(items: [exportedURL], sender: sender)
//                    }
//
//                case .failure: break
//            }
//        }
    }

    private func presentActivityController(items: [Any], sender: UIView?) {
        // If we have nothing to share, exit early
        guard items.count > 0 else { return }

        var applicationActivities: [UIActivity]?
//        #if targetEnvironment(simulator)
//        applicationActivities = [SaveToDesktopActivity(title: "Save to desktop") { (sharedItems) in
//            guard let sharedStrings = sharedItems as? [String] else { return }
//
//            let today = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "/", with: ":")
//            let filename = "\(UIApplication.shared.name)_\(today).log"
//            for string in sharedStrings {
//                let homeUser = NSString(string: "~").expandingTildeInPath.split(separator: "/").dropFirst().first ?? "-"
//                let path = "Users/\(homeUser)/Desktop/\(filename)"
//                FileManager.default.createFile(atPath: path, contents: string.data(using: .utf8, allowLossyConversion: true), attributes: nil)
//            }
//        }]
//        #endif

        let activityController = UIActivityViewController(activityItems: items, applicationActivities: applicationActivities)

        // This is required on iPads
        if let sender = sender {
            activityController.popoverPresentationController?.sourceView = sender
        }

        present(activityController, animated: true)
    }

    private func shareDeviceLogs(sender: UIView?) {

    }

}

extension MenuViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel?.numberOfSections ?? 0
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel?.title(forSection: section) ?? nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel?.numbeOfRows(inSection: section) ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = viewModel?.row(at: indexPath) else { return UITableViewCell() }

        let cell = tableView.dequeueReusableCell(withIdentifier: row.style.rawValue, for: indexPath)
        cell.accessoryType = (row.detailActionController != nil) ? .disclosureIndicator : .none
        cell.textLabel?.text = viewModel?.title(for: row, indexPath: indexPath)
        cell.detailTextLabel?.text = row.detailTitle

        if let url = row.iconURL {
            cell.imageView?.downloadImageFrom(url, contentMode: .scaleAspectFit, {
                cell.setNeedsLayout()
            })
        } else if #available(iOS 13.0, *), let icon = row.icon {
            cell.imageView?.image = icon
        }

        return cell
    }

}

extension MenuViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        /// Deselect Cell
        defer {
            tableView.deselectRow(at: indexPath,
                                  animated: true)
        }
        
        /// Perform Row Action
        guard let row = viewModel?.row(at: indexPath) else {
            return
        }
        viewModel?.performAction(for: row, indexPath: indexPath)

        /// Open Detail Controller
        if let detailController = row.detailActionController {
            self.navigationController?.pushViewController(detailController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        guard let row = viewModel?.row(at: indexPath) else { return false }
        return row.style == .subtitle || (row.style == .default && row.detailActionController == nil)
    }

    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        action == #selector(copy(_:))
    }

    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        guard let cell = tableView.cellForRow(at: indexPath), let key = cell.textLabel?.text else { return }

        // Currently supports only copy action
        if action == #selector(copy(_:)) {
            if let value = cell.detailTextLabel?.text, value != "null" {
                UIPasteboard.general.string = "\(key): \(value)"
            } else {
                UIPasteboard.general.string = key
            }
        }
    }

}
