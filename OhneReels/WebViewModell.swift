import Combine
import SwiftUI
import UIKit
import WebKit

/// Die vier Bereiche der nativen Tab-Leiste.
enum Bereich: String, CaseIterable, Identifiable {
    case feed, suche, nachrichten, profil

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .feed: return "Feed"
        case .suche: return "Suche"
        case .nachrichten: return "Nachrichten"
        case .profil: return "Profil"
        }
    }

    /// SF-Symbol im Normalzustand.
    var symbol: String {
        switch self {
        case .feed: return "house"
        case .suche: return "magnifyingglass"
        case .nachrichten: return "paperplane"
        case .profil: return "person.crop.circle"
        }
    }

    /// SF-Symbol, wenn der Bereich aktiv ist.
    var symbolAktiv: String {
        switch self {
        case .feed: return "house.fill"
        case .suche: return "magnifyingglass"
        case .nachrichten: return "paperplane.fill"
        case .profil: return "person.crop.circle.fill"
        }
    }
}

/// Herzstück der App: besitzt den WKWebView, wendet die Navigationsregeln an,
/// spielt das Userscript ein und kümmert sich um das Löschen der Daten.
@MainActor
final class WebViewModell: NSObject, ObservableObject {

    // MARK: - Zustand für die Oberfläche

    /// Wird erhöht, wenn ein neuer WebView erzeugt wurde (Inkognito-Wechsel, "Alle Daten löschen").
    @Published private(set) var generation = 0
    @Published private(set) var fortschritt: Double = 0
    @Published private(set) var laedt = false
    @Published private(set) var aktiverBereich: Bereich = .feed
    @Published private(set) var tastaturSichtbar = false
    @Published private(set) var fehlermeldung: String?
    @Published private(set) var hinweis: String?

    private(set) var webView: WKWebView

    // MARK: - Interner Zustand

    /// Name des Kanals, über den das Userscript Nachrichten an Swift schickt.
    private static let nachrichtenKanal = "ohneReels"

    private let skript: String
    private var regeln = Regelwerk()
    private var abos = Set<AnyCancellable>()
    /// Vom Userscript erkannter eigener Benutzername (nur im Arbeitsspeicher).
    private var erkannterName: String?
    private var profilAusstehend = false
    private var hintergrundAufgabe = UIBackgroundTaskIdentifier.invalid
    private var nachRueckkehrNeuLaden = false

    private var eigenerName: String? { erkannterName ?? Einstellungen.benutzername }

    // MARK: - Start

    override init() {
        skript = WebViewModell.ladeSkript()
        webView = WebViewModell.baueWebView()
        super.init()

        verbinde(webView)

        let zentrale = NotificationCenter.default
        zentrale.addObserver(self, selector: #selector(inDenHintergrund),
                             name: UIApplication.didEnterBackgroundNotification, object: nil)
        zentrale.addObserver(self, selector: #selector(inDenVordergrund),
                             name: UIApplication.willEnterForegroundNotification, object: nil)
        zentrale.addObserver(self, selector: #selector(tastaturErscheint),
                             name: UIResponder.keyboardWillShowNotification, object: nil)
        zentrale.addObserver(self, selector: #selector(tastaturVerschwindet),
                             name: UIResponder.keyboardWillHideNotification, object: nil)

        // Beim Start: erst aufräumen, dann Blockliste aktivieren, dann erst Instagram laden.
        let ansicht = webView
        Datenschutz.bereinigen(ansicht.configuration.websiteDataStore) { [weak self] in
            self?.aktiviereBlocklisteUndLade(ansicht)
        }
    }

    /// Liest Ressourcen/userscript.js aus dem App-Paket.
    private static func ladeSkript() -> String {
        guard let adresse = Bundle.main.url(forResource: "userscript", withExtension: "js"),
              let text = try? String(contentsOf: adresse, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// Erzeugt einen frisch konfigurierten WebView (je nach Einstellung dauerhaft oder Inkognito).
    private static func baueWebView() -> WKWebView {
        let konfiguration = WKWebViewConfiguration()
        // Inkognito: Daten leben nur im Arbeitsspeicher und sind nach dem Beenden der App weg.
        if Einstellungen.inkognito {
            konfiguration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        } else {
            konfiguration.websiteDataStore = WKWebsiteDataStore.default()
        }
        // Videos (Stories) im Seitenlayout abspielen statt im Vollbild-Player.
        konfiguration.allowsInlineMediaPlayback = true
        konfiguration.mediaTypesRequiringUserActionForPlayback = []
        // User-Agent wie mobiles Safari (siehe safariKennung).
        konfiguration.applicationNameForUserAgent = safariKennung()
        konfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let ansicht = WKWebView(frame: .zero, configuration: konfiguration)
        ansicht.allowsBackForwardNavigationGestures = true   // Wischen vom Rand = zurück
        ansicht.allowsLinkPreview = false                     // keine Safari-artige Linkvorschau
        ansicht.isOpaque = false
        ansicht.backgroundColor = .systemBackground           // folgt Hell/Dunkel des Systems
        ansicht.scrollView.backgroundColor = .systemBackground
        ansicht.scrollView.contentInsetAdjustmentBehavior = .never
        ansicht.scrollView.keyboardDismissMode = .interactive
        return ansicht
    }

    /// WKWebView meldet sich von Haus aus ohne "Version/… Safari/…". Mit diesem Zusatz sieht der
    /// User-Agent genauso aus wie beim echten Safari derselben iOS-Version – so erscheinen keine
    /// Hinweise wie "Browser nicht unterstützt".
    private static func safariKennung() -> String {
        let teile = UIDevice.current.systemVersion.split(separator: ".")
        let haupt = teile.first.map { String($0) } ?? "18"
        let neben = teile.count > 1 ? String(teile[1]) : "0"
        return "Version/\(haupt).\(neben) Mobile/15E148 Safari/604.1"
    }

    /// Hängt Delegates, Userscript, Pull-to-Refresh und Beobachter an einen WebView.
    private func verbinde(_ ansicht: WKWebView) {
        ansicht.navigationDelegate = self
        ansicht.uiDelegate = self

        let steuerung = ansicht.configuration.userContentController
        steuerung.add(SchwacherEmpfaenger(self), name: WebViewModell.nachrichtenKanal)
        setzeSkripte(steuerung)

        // Pull-to-Refresh
        let ziehen = UIRefreshControl()
        ziehen.addTarget(self, action: #selector(neuLadenGezogen(_:)), for: .valueChanged)
        ansicht.scrollView.refreshControl = ziehen

        // Ladefortschritt und Adresse beobachten
        abos.removeAll()
        ansicht.publisher(for: \.estimatedProgress)
            .sink { [weak self] wert in self?.fortschritt = wert }
            .store(in: &abos)
        ansicht.publisher(for: \.isLoading)
            .sink { [weak self] wert in self?.laedt = wert }
            .store(in: &abos)
        ansicht.publisher(for: \.url)
            .sink { [weak self] adresse in self?.adresseGeaendert(adresse) }
            .store(in: &abos)
    }

    /// Spielt die Einstellungen und das Userscript ein – beides ab documentStart, nur im Hauptrahmen.
    private func setzeSkripte(_ steuerung: WKUserContentController) {
        steuerung.removeAllUserScripts()
        let einstellungen = WKUserScript(source: "window.__ohneReelsConfig = \(Einstellungen.alsJavaScript);",
                                         injectionTime: .atDocumentStart, forMainFrameOnly: true)
        steuerung.addUserScript(einstellungen)
        let hauptskript = WKUserScript(source: skript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        steuerung.addUserScript(hauptskript)
    }

    private func aktiviereBlocklisteUndLade(_ ansicht: WKWebView) {
        Blockliste.laden { [weak self] listen in
            guard let self, ansicht === self.webView else { return }
            for liste in listen {
                ansicht.configuration.userContentController.add(liste)
            }
            self.lade(Regelwerk.startseite)
        }
    }

    // MARK: - Navigation aus der nativen Oberfläche

    /// Tipp auf einen Tab. Zweiter Tipp auf den aktiven Tab scrollt nach oben.
    func waehle(_ bereich: Bereich) {
        fehlermeldung = nil
        if bereich == aktiverBereich, istAufWurzel(bereich) {
            nachOben()
            return
        }
        aktiverBereich = bereich
        switch bereich {
        case .feed: gehe(zu: "/")
        case .suche: gehe(zu: "/explore/")
        case .nachrichten: gehe(zu: "/direct/inbox/")
        case .profil: oeffneProfil()
        }
    }

    func neuLaden() {
        fehlermeldung = nil
        if webView.url == nil {
            lade(Regelwerk.startseite)
        } else {
            webView.reload()
        }
    }

    func nachOben() {
        webView.evaluateJavaScript("window.__ohneReels && window.__ohneReels.nachOben(); true", completionHandler: nil)
        let rollbereich = webView.scrollView
        rollbereich.setContentOffset(CGPoint(x: 0, y: -rollbereich.adjustedContentInset.top), animated: true)
    }

    private func lade(_ adresse: URL) {
        fehlermeldung = nil
        webView.load(URLRequest(url: adresse))
    }

    /// Wechselt zu einem Instagram-Pfad. Erst wird versucht, Instagrams eigenen (ggf. unsichtbaren)
    /// Navigationslink anzutippen – das ist schneller, weil die Seite nicht neu geladen wird.
    /// Klappt das nicht, wird die Adresse normal geladen.
    private func gehe(zu pfad: String) {
        guard let ziel = URL(string: "https://www.instagram.com" + pfad) else { return }
        let ansicht = webView
        // "pfad" besteht nur aus festen Werten oder einem geprüften Benutzernamen – kein Einschleusen möglich.
        let js = "(window.__ohneReels && window.__ohneReels.gehe('\(pfad)')) === true"
        ansicht.evaluateJavaScript(js) { [weak self] ergebnis, _ in
            let geklappt = (ergebnis as? Bool) == true
            Task { @MainActor in
                guard let self, ansicht === self.webView else { return }
                if !geklappt {
                    self.lade(ziel)
                }
            }
        }
    }

    private func oeffneProfil() {
        if let name = eigenerName {
            gehe(zu: "/\(name)/")
            return
        }
        // Benutzername noch unbekannt: Startseite laden. Das Userscript liest dort den Profil-Link
        // aus Instagrams Navigation und meldet den Namen (siehe userContentController unten).
        profilAusstehend = true
        if !istAufWurzel(.feed) {
            lade(Regelwerk.startseite)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard let self, self.profilAusstehend else { return }
            self.profilAusstehend = false
            self.zeigeHinweis("Dein Profil wurde nicht erkannt. Trage deinen Benutzernamen in den Einstellungen (Zahnrad) ein.")
        }
    }

    private func zeigeHinweis(_ text: String) {
        hinweis = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, self.hinweis == text else { return }
            self.hinweis = nil
        }
    }

    private func istAufWurzel(_ bereich: Bereich) -> Bool {
        guard let adresse = webView.url, let host = adresse.host?.lowercased(),
              Regelwerk.istInstagram(host) else { return false }
        let teile = Regelwerk.segmente(adresse).map { $0.lowercased() }
        switch bereich {
        case .feed:
            return teile.isEmpty
        case .suche:
            return teile == ["explore"]
        case .nachrichten:
            return teile == ["direct", "inbox"]
        case .profil:
            guard let name = eigenerName?.lowercased() else { return false }
            return teile == [name]
        }
    }

    // MARK: - Adresse beobachten (dritte Sicherung)

    /// Wird bei JEDER Adressänderung aufgerufen – auch wenn Instagram als Single-Page-App nur
    /// history.pushState benutzt und decidePolicyFor deshalb gar nicht gefragt wird.
    private func adresseGeaendert(_ adresse: URL?) {
        guard let adresse, let host = adresse.host?.lowercased(), Regelwerk.istInstagram(host) else { return }
        switch regeln.bewerte(adresse) {
        case .erlauben:
            aktualisiereBereich(adresse)
        case .umleiten(let ziel):
            webView.load(URLRequest(url: ziel))
        case .blockieren, .extern:
            webView.load(URLRequest(url: Regelwerk.startseite))
        }
    }

    /// Markiert den passenden Tab, wenn man innerhalb von Instagram navigiert.
    private func aktualisiereBereich(_ adresse: URL) {
        let teile = Regelwerk.segmente(adresse).map { $0.lowercased() }
        var neu = aktiverBereich
        if teile.isEmpty {
            neu = .feed
        } else if teile[0] == "direct" {
            neu = .nachrichten
        } else if teile[0] == "explore" {
            neu = .suche
        } else if let name = eigenerName?.lowercased(), teile[0] == name {
            neu = .profil
        }
        if neu != aktiverBereich {
            aktiverBereich = neu
        }
    }

    // MARK: - Einstellungen wurden geändert

    /// Feed / Profilraster / Instagram-Leiste: sofort an die laufende Seite weitergeben.
    func einstellungenGeaendert() {
        setzeSkripte(webView.configuration.userContentController)
        let js = "window.__ohneReels && window.__ohneReels.setzeConfig(\(Einstellungen.alsJavaScript)); true"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Inkognito an/aus: braucht einen neuen WebView mit anderem Datenspeicher.
    func inkognitoGeaendert() {
        if Einstellungen.inkognito {
            // Beim Einschalten alles dauerhaft Gespeicherte entfernen – auch den Login.
            Datenschutz.allesLoeschen(WKWebsiteDataStore.default()) { [weak self] in
                self?.neuerWebView()
            }
        } else {
            neuerWebView()
        }
    }

    /// "Alle Daten löschen & abmelden".
    func allesLoeschenUndAbmelden() {
        UserDefaults.standard.removeObject(forKey: Einstellungen.Schluessel.benutzername)
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        let aktuell = webView.configuration.websiteDataStore
        Datenschutz.allesLoeschen(aktuell) { [weak self] in
            Datenschutz.allesLoeschen(WKWebsiteDataStore.default()) { [weak self] in
                self?.neuerWebView()
            }
        }
    }

    /// Verwirft den alten WebView samt Zustand und baut einen neuen auf.
    private func neuerWebView() {
        let alt = webView
        alt.stopLoading()
        alt.navigationDelegate = nil
        alt.uiDelegate = nil
        alt.configuration.userContentController.removeScriptMessageHandler(forName: WebViewModell.nachrichtenKanal)

        regeln = Regelwerk()
        erkannterName = nil
        profilAusstehend = false
        fortschritt = 0
        laedt = false
        fehlermeldung = nil
        aktiverBereich = .feed

        let neu = WebViewModell.baueWebView()
        webView = neu
        verbinde(neu)
        generation += 1
        aktiviereBlocklisteUndLade(neu)
    }

    // MARK: - Hintergrund / Vordergrund

    /// Beim Wechsel in den Hintergrund: Cache, Speicher und überflüssige Cookies löschen.
    @objc private func inDenHintergrund() {
        guard hintergrundAufgabe == .invalid else { return }
        // Etwas Zeit vom System erbitten, damit das Löschen sicher fertig wird.
        hintergrundAufgabe = UIApplication.shared.beginBackgroundTask(withName: "Bereinigung") { [weak self] in
            Task { @MainActor in
                self?.beendeHintergrundAufgabe()
            }
        }
        Datenschutz.bereinigen(webView.configuration.websiteDataStore) { [weak self] in
            // Der geladenen Seite wurde der Speicher unter den Füßen weggezogen –
            // deshalb bei der Rückkehr einmal neu laden.
            self?.nachRueckkehrNeuLaden = true
            self?.beendeHintergrundAufgabe()
        }
    }

    private func beendeHintergrundAufgabe() {
        guard hintergrundAufgabe != .invalid else { return }
        UIApplication.shared.endBackgroundTask(hintergrundAufgabe)
        hintergrundAufgabe = .invalid
    }

    @objc private func inDenVordergrund() {
        guard nachRueckkehrNeuLaden else { return }
        nachRueckkehrNeuLaden = false
        neuLaden()
    }

    @objc private func tastaturErscheint() {
        tastaturSichtbar = true
    }

    @objc private func tastaturVerschwindet() {
        tastaturSichtbar = false
    }

    @objc private func neuLadenGezogen(_ ziehen: UIRefreshControl) {
        neuLaden()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            ziehen.endRefreshing()
        }
    }

    // MARK: - Fehler

    private func behandleFehler(_ fehler: Error) {
        let details = fehler as NSError
        // Abgebrochene Ladevorgänge sind normal (z. B. wenn eine Regel umleitet).
        if details.domain == NSURLErrorDomain && details.code == NSURLErrorCancelled { return }
        if details.domain == "WebKitErrorDomain" { return }
        fehlermeldung = details.localizedDescription
    }
}

// MARK: - Navigationsregeln anwenden (erste Sicherung)

extension WebViewModell: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let adresse = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // targetFrame == nil bedeutet: der Link will ein neues Fenster (target="_blank").
        let neuesFenster = navigationAction.targetFrame == nil
        let hauptrahmen = navigationAction.targetFrame?.isMainFrame ?? true

        // Eingebettete Rahmen: nur das Schema prüfen.
        if !hauptrahmen {
            decisionHandler(Regelwerk.unterrahmenErlaubt(adresse) ? .allow : .cancel)
            return
        }

        switch regeln.bewerte(adresse) {
        case .erlauben:
            if neuesFenster {
                // Es gibt keine Fenster – im selben WebView öffnen.
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else {
                decisionHandler(.allow)
            }
        case .blockieren:
            decisionHandler(.cancel)
        case .umleiten(let ziel):
            decisionHandler(.cancel)
            webView.load(URLRequest(url: ziel))
        case .extern(let ziel):
            // Externe Links in Safari öffnen.
            decisionHandler(.cancel)
            UIApplication.shared.open(ziel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        fehlermeldung = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        behandleFehler(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        behandleFehler(error)
    }

    /// iOS hat den Webseiten-Prozess beendet (Speicherdruck) – einfach neu laden.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        neuLaden()
    }
}

// MARK: - Fenster und Kamera

extension WebViewModell: WKUIDelegate {

    /// window.open(…) und target="_blank": Es werden nie neue Fenster erzeugt.
    /// Die Adresse läuft durch dieselben Regeln wie jede andere Navigation.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let adresse = navigationAction.request.url else { return nil }
        switch regeln.bewerte(adresse) {
        case .erlauben:
            webView.load(navigationAction.request)
        case .umleiten(let ziel):
            webView.load(URLRequest(url: ziel))
        case .extern(let ziel):
            UIApplication.shared.open(ziel)
        case .blockieren:
            break
        }
        return nil
    }

    /// Kamera/Mikrofon direkt in der Webseite (z. B. Story aufnehmen): für Instagram ohne zusätzliche
    /// Web-Nachfrage erlauben. Die Systemabfrage von iOS (Info.plist-Texte) erscheint trotzdem.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Regelwerk.istInstagram(origin.host.lowercased()) ? .grant : .deny)
    }
}

// MARK: - Nachrichten vom Userscript

extension WebViewModell: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == WebViewModell.nachrichtenKanal,
              message.frameInfo.isMainFrame,
              Regelwerk.istInstagram(message.frameInfo.securityOrigin.host.lowercased()),
              let inhalt = message.body as? [String: Any],
              let typ = inhalt["typ"] as? String else { return }

        // Das Userscript hat den eigenen Benutzernamen in Instagrams Navigation gefunden.
        if typ == "benutzer", let name = inhalt["name"] as? String, Regelwerk.istBenutzername(name) {
            erkannterName = name
            if profilAusstehend {
                profilAusstehend = false
                aktiverBereich = .profil
                gehe(zu: "/\(name)/")
            }
        }
    }
}

/// WKUserContentController hält seinen Empfänger fest. Dieser Zwischenschritt verhindert,
/// dass WebView und Modell sich gegenseitig am Leben halten.
@MainActor
private final class SchwacherEmpfaenger: NSObject, WKScriptMessageHandler {
    private weak var ziel: WebViewModell?

    init(_ ziel: WebViewModell) {
        self.ziel = ziel
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        ziel?.userContentController(userContentController, didReceive: message)
    }
}
