//
//  NetworkLoggerViewController.swift
//  
//
//  Created by Brandon Stillitano on 24/12/20.
//

#if !os(macOS)
import UIKit

//class NetworkLoggerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UISearchControllerDelegate, DataCleaner {
class NetworkLoggerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UISearchControllerDelegate {
    // MARK: Properties
    
    var tableView: UITableView = UITableView()
    var searchController: UISearchController!
    
    // MARK: View Life Cycle
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.edgesForExtendedLayout = UIRectEdge.all
        self.extendedLayoutIncludesOpaqueBars = true
        self.automaticallyAdjustsScrollViewInsets = false
        
        self.tableView.frame = self.view.frame
        self.tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.tableView.translatesAutoresizingMaskIntoConstraints = true
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.view.addSubview(self.tableView)
        
        self.tableView.register(NetworkLogCell.self, forCellReuseIdentifier: NSStringFromClass(NetworkLogCell.self))

//        let rightButtons = [
//            UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(NFXListController_iOS.trashButtonPressed)),
//            UIBarButtonItem(image: UIImage.NFXSettings(), style: .plain, target: self, action: #selector(NFXListController_iOS.settingsButtonPressed))
//        ]
//
//        self.navigationItem.rightBarButtonItems = rightButtons


        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.searchResultsUpdater = self
        self.searchController.delegate = self
        self.searchController.hidesNavigationBarDuringPresentation = false
        self.searchController.dimsBackgroundDuringPresentation = false
        self.searchController.searchBar.autoresizingMask = [.flexibleWidth]
        self.searchController.searchBar.backgroundColor = UIColor.clear
//        self.searchController.searchBar.barTintColor = UIColor.NFXOrangeColor()
//        self.searchController.searchBar.tintColor = UIColor.NFXOrangeColor()
        self.searchController.searchBar.searchBarStyle = .minimal
        self.searchController.view.backgroundColor = UIColor.clear
        
        if #available(iOS 11.0, *) {
            self.navigationItem.searchController = self.searchController
            self.definesPresentationContext = true
        } else {
            let searchView = UIView()
            searchView.frame = CGRect(x: 0, y: 0, width: self.view.frame.width - 60, height: 0)
            searchView.autoresizingMask = [.flexibleWidth]
            searchView.autoresizesSubviews = true
            searchView.backgroundColor = UIColor.clear
            searchView.addSubview(self.searchController.searchBar)
            self.searchController.searchBar.sizeToFit()
            searchView.frame = self.searchController.searchBar.frame

            self.navigationItem.titleView = searchView
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadTableViewData()
    }
    
    // MARK: UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
//        self.updateSearchResultsForSearchControllerWithString(searchController.searchBar.text!)
        reloadTableViewData()
    }
    
    @objc func deactivateSearchController()
    {
        self.searchController.isActive = false
    }
    
    // MARK: UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        if (self.searchController.isActive) {
//            return self.filteredTableData.count
            return 0
        } else {
            return LoggerHTTPModelManager.sharedInstance.getModels().count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = self.tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(NetworkLogCell.self), for: indexPath) as? NetworkLogCell else {
            return UITableViewCell()
        }
        
        if (self.searchController.isActive) {
//            if self.filteredTableData.count > 0 {
//                let obj = self.filteredTableData[(indexPath as NSIndexPath).row]
//                cell.configForObject(obj)
//            }
        } else {
            if LoggerHTTPModelManager.sharedInstance.getModels().count > 0 {
                let obj = LoggerHTTPModelManager.sharedInstance.getModels()[indexPath.row]
                cell.configForObject(obj)
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView.init(frame: CGRect.zero)
    }
    
    func reloadTableViewData() {
        DispatchQueue.main.async { () -> Void in
            self.tableView.reloadData()
            self.tableView.setNeedsDisplay()
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        var detailsController : NFXDetailsController_iOS
//        detailsController = NFXDetailsController_iOS()
//        var model: NFXHTTPModel
//        if (self.searchController.isActive) {
//            model = self.filteredTableData[(indexPath as NSIndexPath).row]
//        } else {
//            model = NFXHTTPModelManager.sharedInstance.getModels()[(indexPath as NSIndexPath).row]
//        }
//        detailsController.selectedModel(model)
//        self.navigationController?.pushViewController(detailsController, animated: true)
        
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 58
    }
}

#endif

//#if !os(macOS)
//import UIKit
//
//internal class NetworkLoggerViewController: UIViewController {
//    // MARK: - Data
//    private let tableView = UITableView(frame: .zero, style: .plain)
//    private var viewModel: NetworkLoggerViewModel = NetworkLoggerViewModel()
//
//    // MARK: - Init
//    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
//        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
//
//        setupUI()
//        setupConstraints()
//        setupData()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
//    // MARK: - Setup
//    private func setupUI() {
//        //Setup Table View
//        tableView.delegate = self
//        tableView.dataSource = self
//        view.addSubview(tableView)
//
//        //Register Table View Cells
//        tableView.register(DefaultCell.self, forCellReuseIdentifier: RowStyle.default.rawValue)
//        tableView.register(CheckmarkCell.self, forCellReuseIdentifier: RowStyle.checkmarkAccessory.rawValue)
//    }
//
//    private func setupConstraints() {
//        tableView.translatesAutoresizingMaskIntoConstraints = false
//        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[subview]-0-|",
//                                                           options: .directionLeadingToTrailing,
//                                                           metrics: nil,
//                                                           views: ["subview": tableView]))
//        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[subview]-0-|",
//                                                           options: .directionLeadingToTrailing,
//                                                           metrics: nil,
//                                                           views: ["subview": tableView]))
//    }
//
//    private func setupData() {
//        self.viewModel.delegate = self
//        self.viewModel.prepareObjects()
//
//        title = viewModel.title
//        navigationItem.title = viewModel.title
//    }
//
//    // MARK: - Lifecycle
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//
//        UIView.setAnimationsEnabled(false)
//        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
//        UIView.setAnimationsEnabled(true)
//    }
//}
//
//extension NetworkLoggerViewController: UITableViewDataSource {
//
//    func numberOfSections(in tableView: UITableView) -> Int {
//        return viewModel.numberOfSections
//    }
//
//    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
//        return viewModel.title(forSection: section)
//    }
//
//    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//        return viewModel.numbeOfRows(inSection: section)
//    }
//
//    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//        // Check for Cell
//        guard let row = viewModel.row(at: indexPath) else {
//            return UITableViewCell()
//        }
//
//        // Setup Cell
//        let cell = tableView.dequeueReusableCell(withIdentifier: row.cellReuseIdentifier,
//                                                 for: indexPath)
//        cell.textLabel?.text = viewModel.title(for: row, indexPath: indexPath)
//        cell.detailTextLabel?.text = row.detailText
//        cell.accessoryView = row.accessoryView
//
//        // Setup Accessory
//        switch row.style {
//        case .checkmarkAccessory:
//            guard let checkRow: CheckmarkRow = row as? CheckmarkRow else {
//                break
//            }
//            cell.accessoryType = checkRow.checked ? .checkmark : .none
//        default:
//            break
//        }
//
//        return cell
//    }
//
//}
//
//extension NetworkLoggerViewController: UITableViewDelegate {
//    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        // Deselect Cell
//        defer { tableView.deselectRow(at: indexPath, animated: true) }
//
//        // Check for Cell
//        guard let row = viewModel.row(at: indexPath) else {
//            return
//        }
//        row.actionBlock?()
//    }
//}
//
//extension NetworkLoggerViewController: NetworkLoggerViewModelProtocol {
//    func viewModelShouldReloadData() {
//        self.tableView.reloadData()
//    }
//}
//#endif
