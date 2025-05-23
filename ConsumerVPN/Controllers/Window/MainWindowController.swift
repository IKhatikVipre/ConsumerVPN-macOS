//
//  MainWindowController.swift
//  WhiteLabelVPN
//
//  Created by Zephaniah Cohen on 9/8/16.
//  Copyright © 2016 WLVPN. All rights reserved.
//

import Foundation
import AppKit

protocol UIViewFadeAnimation {
    func revealViewsAnimation()
    var animatableViews: [NSView] { get set }
}

extension UIViewFadeAnimation {
    /// Applies a fade animation to each view in the subviewsToAnimate array
    func revealViewsAnimation() {
        
        for subView in self.animatableViews {
            subView.layer?.opacity = 0
        }
        
        DispatchQueue.main.async {
            let fadeInAnimation = Animations.opacityFadeAnimation(startingAlphaValue: 0.0, endingAlphaValue: 1.0, animationDuration: 2, animationName: "fadeIn")
            for subView in self.animatableViews {
                subView.layer?.add(fadeInAnimation, forKey: "fadeIn")
                subView.layer?.opacity = 1.0
            }
        }
    }
}

class MainWindowController : BaseWindowController {
    
    //MARK: - Properties
    
    @IBOutlet weak var backgroundView: ColorView!
    @IBOutlet weak var contentView: NSView!

    fileprivate var currentView : NSView!
    fileprivate var shouldConnectAtStartUp = false
    fileprivate var cancelledConnection: Bool = false
    
    fileprivate lazy var disconnectView : DisconnectView = {
        let disconnectView = DisconnectView.newInstance()
        disconnectView.delegate = self
        return disconnectView
    }()
    
    fileprivate lazy var connectView : ConnectView = {
        let connectView = ConnectView.newInstance()
        connectView.setTouchBarItems()
        connectView.delegate = self
        connectView.apiManager = apiManager
        return connectView
    }()
    
    fileprivate lazy var loginViewController : LoginViewController = {
        let loginViewController = LoginViewController.newWith(apiManager: apiManager, toggleDelegate: self)
        loginViewController.setTouchBarItems()
        return loginViewController
    }()
    
    fileprivate lazy var signupViewController : SignupViewController = {
        let signupViewController = SignupViewController.newWith(apiManager: apiManager, toggleDelegate: self, purchaseCoordinator: purchaseCoordinator)
        signupViewController.setTouchBarItems()
        return signupViewController
    }()
    
    fileprivate lazy var serverViewController : ServerViewController = {
        let serverWindowController = serverWindowController
        let serverViewController = serverWindowController.contentViewController as! ServerViewController
        serverViewController.delegate = self
        return serverViewController
    }()
    
    fileprivate lazy var serverWindowController : ServerWindowController = {
        let serverWindowController = ServerWindowController.newWith(apiManager: apiManager)
        return serverWindowController
    }()
    
    fileprivate lazy var productsViewController : ProductsViewController = {
        return ProductsViewController.newWith(apiManager: apiManager, purchaseCoordinator: purchaseCoordinator)
    }()
    
    fileprivate lazy var purchaseViewController : PurchaseViewController = {
        return PurchaseViewController.newWith(apiManager: apiManager, purchaseCoordinator: purchaseCoordinator)
    }()
    
    fileprivate lazy var loadingView : LoadingView = {
        let loadingView = LoadingView.newInstance()
        loadingView.delegate = self
        return loadingView
    }()
    
    var currentCities: [City] = []
    
    var purchaseCoordinator: PurchaseCoordinator!
    
    fileprivate var alert: NSAlert?
    
    //MARK: - Window Management
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        NotificationCenter.default.addObserver(for: self)
        
        themeWindow()
        
        if ApiManagerHelper.shared.isUserLogin() {
            manageConnectionViews()
        } else {
            customBarItems = loginViewController.getCustomBarItems()
            showLoginView()
        }
        
        // Set the Server Select Text
        connectView.locationNameLabel.stringValue = ApiManagerHelper.shared.getCityLocationString()
        
        //Starts off disabled until initial server list and server updates succeed.
        connectView.toggleUIForEnabledState(isEnabled: false)
        
        evaluateGeneralPreferences()
        ApiManagerHelper.shared.setDefaultEncryption()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(userDidSelectPlan(notification:)),
                                               name: NSNotification.Name("Selected Plan"),
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(userDidSignup),
                                               name: NSNotification.Name("CancelPurchase"),
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(userDidSignup),
                                               name: NSNotification.Name("UserDidSignUp"),
                                               object: nil)
        
        if ApiManagerHelper.shared.isUserLogin(), UserDefaults.standard.bool(forKey: WLHideOnAppLaunch)  {
            if shouldConnectAtStartUp {
                ApiManagerHelper.shared.refreshServer()
            } else {
                ApiManagerHelper.shared.synchronizeConfiguration()
            }
        }
    }
    
    deinit {
        let center = NotificationCenter.default
        center.removeObserver(for: self)
        center.removeObserver(self, name: NSNotification.Name("Selected Plan"), object: nil)
        center.removeObserver(self, name: NSNotification.Name("CancelPurchase"), object: nil)
        center.removeObserver(self, name: NSNotification.Name("UserDidSignUp"), object: nil)
    }
    
    /// Shows the appropriate view controller view based upon active VPN connection
    /// state.
    fileprivate func manageConnectionViews() {
        if ApiManagerHelper.shared.isConnectedToVPN() == false {
            customBarItems = connectView.getCustomBarItems()
            showConnectView()
        } else {
            customBarItems = disconnectView.getCustomBarItems()
            showDisconnectView()
        }
    }
    
    /// Swaps back to the connect view only if we are on the disconnect
    /// view and not on the server list.
    fileprivate func updateAppliedViewForDisconnectOrFailure() {
        if currentView is DisconnectView || currentView is LoadingView {
            showConnectView()
        }
    }
    
    //MARK: - Utility Methods
    
    /// Prepares the window properties for initial load.
    private func themeWindow() {
        window!.title = Theme.brandName
        
        window?.titleVisibility = .hidden
        
        backgroundView.backgroundColor = NSColor.primaryBackground
    }
    
    /// Displays an alert controller window dialog with the supplied message and
    /// title.
    ///
    /// - parameter informativeText: The alert informative text.
    /// - parameter messageText: The alert message text.
    fileprivate func displayAlert(informativeText : String, messageText : String) {
        if let alert = self.alert {
            if let sheetWindow = alert.window.sheetParent {
                sheetWindow.endSheet(alert.window)
            }
        }
        
        let alert = NSAlert()
        alert.informativeText = informativeText
        alert.messageText = messageText
        alert.alertStyle = .warning
        if let window = window {
            self.alert = alert
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }
    
    //MARK: - View Swap Functions
    
    /// Shows the loginViewController, presenting it with the correct animation.
    internal func showLoginView() {
        swapView(to: loginViewController.colorView)
    }
    
    /// Shows the connectViewController, presenting it with the correct animation.
    internal func showConnectView() {
        swapView(to: connectView)
    }
    
    /// Shows the connectViewController, presenting it with the correct animation.
    internal func showLoadingView() {
        swapView(to: loadingView)
    }
    
    /// Shows the disconnectViewController, presenting it with the correct animation.
    internal func showDisconnectView() {
        
        disconnectView.locationLabel.stringValue = ApiManagerHelper.shared.getCityDisplayString()
        disconnectView.locationLabel.isHidden = false
        swapView(to: disconnectView)
    }
    
    /// Swaps the currentView with the provided view.Applies
    /// a fade transition animation when swapping view controllers.
    ///
    /// - parameter newView: The view to swap in.
    fileprivate func swapView(to newView: TouchBarComponents)  {
        let helperView = newView as! NSView
        customBarItems = newView.getCustomBarItems()
        
        if let _ = currentView {
            contentView.replaceSubview(currentView, with: newView as! NSView)
            
            if let animatableView = newView as? UIViewFadeAnimation {
                animatableView.revealViewsAnimation()
            }
            
            helperView.translatesAutoresizingMaskIntoConstraints = false
            helperView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0.0).isActive = true
            helperView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0.0).isActive = true
            helperView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 0.0).isActive = true
            helperView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 0.0).isActive = true
            contentView.layoutSubtreeIfNeeded()
        } else {
            helperView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(helperView)
            
            helperView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0.0).isActive = true
            helperView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0.0).isActive = true
            helperView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 0.0).isActive = true
            helperView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 0.0).isActive = true
        }
        updateTouchBar()
        
        currentView = helperView
    }
    
    /// Looks through the general preferences determining if a connection should
    /// be made at startup and modify the vpn configuration accordingly for selected
    /// preferences.
    fileprivate func evaluateGeneralPreferences() {
        
        if UserDefaults.standard.bool(forKey: WLDoNotAutomaticallyConnect) == true {
            shouldConnectAtStartUp = false
        } else {
            shouldConnectAtStartUp = true
        }
        
        if UserDefaults.standard.bool(forKey: WLConnectToFastestServer) == true {
            //Should just load balance to the fastest server for the currently assigned
            //city on the vpn configuration.
            ApiManagerHelper.shared.setServer(nil)
            
        } else if UserDefaults.standard.bool(forKey: WLConnectToFastestServerInCountry) == true {
            
            let countries = ApiManagerHelper.shared.fetchCountries()
            
            guard let selectedCountryNamePreference = UserDefaults.standard.value(forKey: WLSelectedCountry) as? String else {
                return
            }
            
            if let selectedCountryPreference = countries.filter({ $0.name?.lowercased() == selectedCountryNamePreference.lowercased() }).first {
                ApiManagerHelper.shared.selectServerWith(country: selectedCountryPreference)
            }
        }
    }
    
    func touchBarLoginHelper() {
        loginViewController.login()
    }
    
    fileprivate func updateTouchBar() {
        if #available(OSX 10.12.2, *) {
            self.touchBar = nil
            self.touchBar = makeTouchBar()
        }
    }
    /// Evaluate preferences connection options.
    /// If any option besides "do not automatically connect", configure and attempt connection
    ///
    fileprivate func evaluateInitialConnectionToServer() {
        if ApiManagerHelper.shared.isConnectedToVPN() || ApiManagerHelper.shared.isVPNConnectionInProgress() {
            return;
        }
        if UserDefaults.standard.bool(forKey: WLConnectToFastestServerInCountry) == true {
            let countries = ApiManagerHelper.shared.fetchCountries()
            if let selectedCountryName = UserDefaults.standard.value(forKey: WLSelectedCountry) as? String,
                let selectedCountry = countries.filter({$0.name == selectedCountryName}).first {
                ApiManagerHelper.shared.selectServerWith(country: selectedCountry)
            }
        } else if UserDefaults.standard.bool(forKey: WLConnectToFastestServer) == true {
            ApiManagerHelper.shared.setServer( nil)
            ApiManagerHelper.shared.setCity(nil)
            ApiManagerHelper.shared.setCoutnry(nil)
        }
        shouldConnectAtStartUp = false
        self.didSelectConnect()
    }
}

//MARK: - VPN Account Status Reporting Conformance

extension MainWindowController : VPNAccountStatusReporting {
    
    func statusLogoutWillBegin(_ notification: Notification) {
        connectView.vpnConnectButton.isClickable = false
    }
    
    /// Displays an alert dialog informing the user the the login failed.
    ///
    /// - parameter notification: The vpn notification.
    func statusLoginFailed(_ notification: Notification) {
        connectView.vpnConnectButton.buttonText = NSLocalizedString("Connect", comment: "Connect")
        
        if currentView != loginViewController.view {
            displayAlert(informativeText: NSLocalizedString("LoginFailedGeneral", comment: "LoginFailedGeneral"), messageText: NSLocalizedString("LoginFailedTitle", comment: "LoginFailedTitle"))
        }
    }
    
    /// Updates the button of the login button text to indicate login status.
    func statusLoginWillBegin(_ notification: Notification) {
        connectView.vpnConnectButton.buttonText =  NSLocalizedString("LoggingIn", comment: "LoggingIn")
    }
    
    /// Shows the appropriate screen after a successful login. Will show the
    /// dashboard or the connected screen if an OnDemand connection is
    /// currently underway.
    ///
    /// - parameter notification: The vpn notification.
    func statusLoginSucceeded(_ notification: Notification) {
        onLogin()
    }
    
    func statusAutomaticLoginSuceeded(_ notification: Notification) {
        onLogin()
    }
    
    func onLogin() {
        
        Task { @MainActor in
            let _ = try? await ApiManagerHelper.shared.refreshLocation()
            let _ = await ApiManagerHelper.shared.refreshServer()
            let success = await ApiManagerHelper.shared.synchronizeConfiguration()
            self.connectView.vpnConnectButton.isClickable = success
            if shouldConnectAtStartUp {
                evaluateInitialConnectionToServer()
            }

        }
        
        
        if currentView is ConnectView {
            connectView.vpnConnectButton.buttonText = NSLocalizedString("Connect", comment: "Connect")
        }
        
        manageConnectionViews()
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.onLogin()
        }
        
    }
    
    /// Resets the title of the header view and displays the write header view
    /// UI when the user successfully logs out.
    /// Reset the values on Logout
    ///
    func statusLogoutSucceeded(_ notification: Notification) {
        
        if let error = notification.object as? NSError, (error.code == VPNImportError.VPNTokenExpiredError.rawValue || error.code == VPNKitLoginError.reauthenticationFailed.rawValue) {
            let alert = NSAlert()
            alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Ok"))
            alert.informativeText = "Session Expired"
            alert.messageText = "Your session expired. Please log in again."
            
            if let window = window {
                alert.beginSheetModal(for: window) { [weak self] (selectedResponseCode) in
                    
                    guard let self = self else { return }
                    
                    if selectedResponseCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                        self.showLoginView()
                        
                        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                            appDelegate.onLogout()
                        }
                    }
                }
            }
        }
        else {
            showLoginView()
            
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.onLogout()
            }
        }
        
    }
    
    func statusLogoutFailed(_ notification: Notification) {
        
        showLoginView()
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.onLogout()
        }
    }
}

//MARK: - Connection Status Reporting Conformance

extension MainWindowController : VPNConnectionStatusReporting {
    func statusConnectionFailed(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        if !ApiManagerHelper.shared.isNetworkReachable() {
            displayAlert(informativeText: "Connection Failed",
                         messageText: "Please check your internet connection.")
        } else {
            displayAlert(informativeText: "Connection Failed",
                         messageText: (notification.object as? NSError)?.localizedDescription ?? "Unknown")
        }
        
        updateAppliedViewForDisconnectOrFailure()
        
        //connectionView
        connectView.toggleUIForEnabledState(isEnabled: true)
        connectView.vpnConnectButton.buttonText = NSLocalizedString("Connect", comment: "Connect")
    }
    
    func statusConnectionWillBegin(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        if !(currentView is LoadingView) {
            loadingView.loadingCircle.message = "Connecting";
            showLoadingView()
        }
        
        connectView.toggleUIForEnabledState(isEnabled: false)
        connectView.vpnConnectButton.buttonText = NSLocalizedString("Connecting", comment: "Connecting...")
    }
    
    func statusConnectionWillDisconnect(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        if !(currentView is LoadingView) {
            loadingView.loadingCircle.message = "Disconnecting"
            showLoadingView()
        }
        connectView.toggleUIForEnabledState(isEnabled: false)
    }
    
    func statusConnectionSucceeded(_ notification: Notification) {
        
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        
        guard !cancelledConnection else {
            cancelledConnection = false
            ApiManagerHelper.shared.disconnect()
            return
        }
        
        //If we also connect from the Server List then just stay there and don't
        //swap.
        if !(currentView is DisconnectView) {
            showDisconnectView()
        }
        
        //connectionView
        connectView.toggleUIForEnabledState(isEnabled: true)
        connectView.vpnConnectButton.buttonText = NSLocalizedString("Connect", comment: "Connect")
    }
    
    func statusConnectionDidDisconnect(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        updateAppliedViewForDisconnectOrFailure()
        //connectionView
        connectView.toggleUIForEnabledState(isEnabled: true)
        connectView.vpnConnectButton.buttonText = NSLocalizedString("Connect", comment: "Connect")
        if !(currentView is ConnectView) {
            showConnectView()
        }
        ApiManagerHelper.shared.refreshLocation()
        
        if let error = notification.object as? NSError {
            displayAlert(informativeText: "Connection Failed",
                         messageText: error.localizedDescription)
        }
    }
    
    //MARK: - VPN Configuration Status Reporting Conformance
    
    func updateConfigurationBegin(_ notification: Notification) {
        connectView.toggleUIForEnabledState(isEnabled: false)
    }
    
    func updateConfigurationSucceeded(_ notification: Notification) {
        connectView.toggleUIForEnabledState(isEnabled: true)
    }
    
    func updateConfigurationFailed(_ notification: Notification) {
        connectView.toggleUIForEnabledState(isEnabled: true)
        connectView.vpnConnectButton.buttonText = NSLocalizedString("Connect", comment: "Connect")
    }
    
    //MARK: - VPN Health Check
    func statusConnectionHealthUpdate(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        if let error = notification.object as? NSError {
            displayAlert(informativeText: "VPN Health Check",
                         messageText: error.localizedDescription)
        } else {
            displayAlert(informativeText: "VPN Health Check",
                         messageText: "Your VPN Connection is healthy!")
        }
    }
}

//MARK: - VPNConfiguration Status Reporting Conformance

extension MainWindowController : VPNConfigurationStatusReporting {
    
    func statusCurrentLocationDidChange(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        disconnectView.ipAddressLabel.stringValue = ApiManagerHelper.shared.getCurrentIPLocationString()
    }
    
    func statusCurrentCityDidChange(_ notification: Notification) {
        debugPrint("[ConsumerVPN] \(#function) \(notification)")
        connectView.locationNameLabel.stringValue = ApiManagerHelper.shared.getCityLocationString()
        updateTouchBar()
    }
}

extension MainWindowController : ConnectViewDelegate {
    
    func didSelectConnect() {
        connectView.vpnConnectButton.isClickable = false
        
        if ApiManagerHelper.shared.selectedProtocol == .wireGuard {
            ApiManagerHelper.shared.installWgSystemExtensionIfRequired { success in
                if success {
                    displayAlert(informativeText: NSLocalizedString("A System Extension for WireGuard® needs to be installed.To do so click on \"Open System Settings\", select \"Security & Privacy\" and then \"Allow IPVanish\"",
                                                                    comment: " System Extension blocked"),
                                 messageText: NSLocalizedString("System extension blocked",
                                                                comment: " System Extension blocked"))
                    return
                }
            }
        }
        else if ApiManagerHelper.shared.selectedProtocol == .openVPN_TCP || ApiManagerHelper.shared.selectedProtocol == .openVPN_UDP {
            
            if !(ApiManagerHelper.shared.isOpenVPNHelperInstalled()) {
                ApiManagerHelper.shared.installPrivilegedHelper()
                return
            }
        }
        ApiManagerHelper.shared.connect()
    }
    
    func didSelectChooseLocation() {
        serverViewController.view.window?.title = NSLocalizedString("Servers", comment: "")
        serverViewController.view.window?.windowController?.showWindow(self)
    }
}

extension MainWindowController : LoadingViewDelegate {
    func didSelectCancelConnect() {
        cancelledConnection = true
    }
    
}

extension MainWindowController : DisconnectViewDelegate {
    
    func didSelectDisconnect() {
        if ApiManagerHelper.shared.isOnDemandEnabled {
            confirmVPNDisconnect()
        } else {
            ApiManagerHelper.shared.disconnect()
        }
    }
    
    // Display an alert window to the user confirming that they wish to disconnect.
    /// Attempts to disconnect if the user confirms they wish to disconnect.
    fileprivate func confirmVPNDisconnect() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.addButton(withTitle: NSLocalizedString("Disconnect", comment: "Disconnect"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        alert.informativeText = NSLocalizedString("OnDemandConfirm", comment: "OnDemandConfirm")
        alert.alertStyle = NSAlert.Style.informational
        
        alert.beginSheetModal(for: window) { (selectedResponseCode) in
            if selectedResponseCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                self.manageOnDemandDisconnect()
            }
        }
    }
    
    /// When a user has confirmed that they wish to disconnect when OnDemand has
    /// been enabled, we disconnect from the VPN, turn off the OnDemand option
    /// on the VPNConfiguration and then install a new VPN helper that will reflect
    /// these OnDemand updated changes. This function also posts a app specific notification
    /// so that the preferences window can update it's UI to reflect this preference
    /// being turned off automatically.
    fileprivate func manageOnDemandDisconnect() {
        ApiManagerHelper.shared.setOnDemand(enable: false)
        ApiManagerHelper.shared.disconnect()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ApiManagerHelper.shared.synchronizeConfiguration { success in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name(WLOnDemandOptionChangedNotification),
                                                             object: nil,
                                                             userInfo: nil)
                }
            }
        }
    }
}

extension MainWindowController: VPNServerStatusReporting {
    func statusServerUpdateSucceeded(_ notification: Notification) {
       
    }
}

extension MainWindowController : CredentialsViewToggleDelegate {
    func switchToSignup() {
        if Theme.enableIAP {
            swapView(to: signupViewController.colorView)
        } else {
            NSWorkspace.shared.open(URL(string: Theme.signupURL)!)
        }
    }
    
    func switchToLogin() {
        swapView(to: loginViewController.colorView)
    }
}

extension MainWindowController {
    
    @objc func userDidSignup() {
        swapView(to: productsViewController.colorView)
    }
}

extension MainWindowController {
    @objc func userDidSelectPlan(notification: Notification) {
        purchaseViewController.selectedPlan = notification.object as? Plan
        swapView(to: purchaseViewController.colorView)
    }
}

//MARK: - VPN Helper Status Reporting Conformance

extension MainWindowController : VPNHelperStatusReporting {
    
    func statusHelperShouldInstall(_ notification: Notification) {
        //IKEV2 helper will be installed silently and should never require an
        //explicit helper dialog from the user. OpenVPN should connect after a
        //successful helper installation.
        if ApiManagerHelper.shared.selectedProtocol != .ikEv2 {
            ApiManagerHelper.shared.connect()
        }
        connectView.vpnConnectButton.isClickable = true
    }
    
    func statusHelperInstallPending(_ notification: Notification) {
        
    }
    
    func statusHelperInstallSuccess(_ notification: Notification) {
        connectView.vpnConnectButton.isClickable = true
    }
    
    func statusHelperInstallFailed(_ notification: Notification) {
        connectView.toggleUIForEnabledState(isEnabled: true)
    }
}
