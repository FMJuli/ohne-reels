# Ohne Reels

Eine kleine iPhone-App, die instagram.com in einem eingebetteten Browser (WKWebView) anzeigt – aber ohne Reels, ohne Explore-Raster, ohne Vorschläge und ohne Werbung.

Die App benutzt ausschließlich die normale Instagram-Webseite. Es wird **keine** inoffizielle oder nachgebaute Instagram-API verwendet.

## Was geht, was nicht

| Bleibt erlaubt | Wird blockiert |
|---|---|
| Direktnachrichten, inklusive geteilter Beiträge und einzelner geteilter Reels | `/reels/` und jeder Weg in den Reels-Feed |
| Stories (Leiste oben und auf Profilen) | Wischen von einem Reel zum nächsten |
| Suche nach Personen | Explore-Raster, Hashtag- und Ortsseiten |
| Profile ansehen (Beitragsraster abschaltbar) | Reels-Tab auf Profilen |
| Home-Feed (abschaltbar) | Reels/Videos, „Vorgeschlagen für dich“ und Werbung im Feed |

Externe Links öffnen sich in Safari. Sprünge in die Instagram-App oder den App Store werden abgefangen.

## Von null zur App auf dem iPhone

Du brauchst nur einen Windows-Rechner, ein iPhone und ein kostenloses GitHub-Konto. Einen Mac braucht GitHub für dich.

### 1. Repo hochladen

**Variante A – im Browser**

1. Auf github.com einloggen → **New repository** → Name z. B. `ohne-reels` → **Create repository**.
2. Auf der leeren Repo-Seite auf **uploading an existing file** klicken.
3. Im Windows-Explorer den Ordner `ohne-reels` öffnen, **alles darin** markieren (auch den Ordner `.github`!) und ins Browserfenster ziehen.
4. Unten auf **Commit changes** klicken.

**Variante B – mit Git** (im Ordner `ohne-reels`, `DEINNAME` ersetzen)

```bash
git init -b main
git add .
git commit -m "Erste Version"
git remote add origin https://github.com/DEINNAME/ohne-reels.git
git push -u origin main
```

Öffentlich oder privat? Bei einem **öffentlichen** Repo sind die Build-Minuten kostenlos und die .ipa lässt sich ohne Login laden. Bei einem **privaten** Repo reichen die Frei-Minuten für etwa 40 Builds pro Monat. Im Code stehen keine persönlichen Daten.

### 2. Actions bauen lassen

Im Repo oben auf **Actions** klicken. Der Workflow **IPA bauen** startet nach jedem Push von selbst und braucht etwa 5 Minuten. Grüner Haken = fertig.

Roter Punkt = Fehler. Dann den fehlgeschlagenen Schritt aufklappen und die Zeilen mit `error:` kopieren – damit lässt sich der Fehler gezielt beheben.

### 3. .ipa unter Releases

Auf der Startseite des Repos rechts unter **Releases** liegt nach jedem Build die Datei `OhneReels.ipa`.

Am bequemsten direkt auf dem iPhone in Safari laden (bei öffentlichem Repo):

```
https://github.com/DEINNAME/ohne-reels/releases/latest/download/OhneReels.ipa
```

### 4. Installation mit SideStore

Voraussetzung: SideStore ist auf dem iPhone eingerichtet (über iloader am Windows-Rechner).

1. **LocalDevVPN** aus dem App Store installieren, öffnen und verbinden. SideStore braucht dieses lokale VPN zum Installieren und Verlängern.
2. **SideStore** öffnen → Tab **My Apps** → oben links **+** → `OhneReels.ipa` auswählen. Beim ersten Mal nach der Apple-ID fragen lassen.
3. **Entwicklermodus** einschalten, falls noch nicht geschehen: *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* → iPhone neu starten → bestätigen.
4. Meldet iOS „Nicht vertrauenswürdiger Entwickler“: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → deine Apple-ID → **Vertrauen**.

**Verlängerung alle 7 Tage:** Mit kostenloser Apple-ID läuft die Signatur nach 7 Tagen ab. Vorher LocalDevVPN verbinden und in SideStore unter **My Apps** auf **Refresh All** tippen. Läuft sie doch ab, startet die App nicht mehr – deine Einstellungen bleiben aber erhalten, nach dem Refresh geht alles wieder.

Weitere Grenzen der kostenlosen Apple-ID: höchstens 3 so installierte Apps gleichzeitig (SideStore zählt mit) und 10 neue App-Kennungen pro Woche.

**Update einspielen:** neue `OhneReels.ipa` laden und in SideStore wieder über **+** installieren. Die alte Version wird ersetzt.

## Bedienung

- Unten die native Leiste: **Feed, Suche, Nachrichten, Profil** und das **Zahnrad** für die Einstellungen.
- Tipp auf den bereits aktiven Tab: erst zurück zur Hauptseite des Tabs, beim nächsten Tipp nach oben scrollen.
- Vom linken Rand wischen: zurück. Nach unten ziehen: neu laden.
- **Login:** mit Benutzername und Passwort. „Mit Facebook anmelden“ wird nicht unterstützt (das würde in Safari landen).

### Einstellungen

| Schalter | Standard | Wirkung |
|---|---|---|
| Home-Feed anzeigen | an | Aus: nur noch die Stories-Leiste, keine Beiträge |
| Beitragsraster auf Profilen | an | Aus: Profile zeigen Kopf, Bio und Story-Highlights, aber keine Beiträge |
| Instagrams eigene Leiste ausblenden | an | Aus: Instagrams Web-Leiste bleibt zusätzlich sichtbar (ohne Reels-Symbol) |
| Eigener Benutzername | leer | Nur nötig, falls der Profil-Tab dein Profil nicht selbst findet |
| Inkognito-Modus | aus | An: nichts wird dauerhaft gespeichert, Login bei jedem Start |
| Alle Daten löschen & abmelden | – | Entfernt Login, Cookies, Cache und Website-Speicher |

## Datenschutz

- **Behalten** werden nur diese Cookies von instagram.com: `sessionid`, `ds_user_id`, `csrftoken` (Login) sowie `mid`, `ig_did`, `datr` (Geräte-Kennung). Die Liste steht zentral in [OhneReels/Datenschutz.swift](OhneReels/Datenschutz.swift).
- **Warum die Geräte-Kennung?** Für den Login ist sie technisch nicht nötig. Ohne sie sähe Instagram aber bei jedem Start einen unbekannten Browser mit bestehender Sitzung – das kann Sicherheitsabfragen oder eine Sperre auslösen. Wer es trotzdem strenger will, leert `geraeteCookies` in der Datei.
- **Gelöscht** werden beim Start und bei jedem Wechsel in den Hintergrund: Cache, localStorage, sessionStorage, IndexedDB, Service Worker und alle übrigen Cookies. Folge: Nach der Rückkehr in die App lädt die Seite einmal neu.
- **Blockiert** werden Tracking-Anfragen über eine WebKit-Blockliste, siehe [OhneReels/Blockliste.swift](OhneReels/Blockliste.swift).
- Die App selbst enthält kein Analytics und kein Crash-Reporting und stellt keine eigenen Netzwerkanfragen. Einstellungen liegen nur in UserDefaults auf dem Gerät.
- „Alle Daten löschen & abmelden“ entfernt die Sitzung **auf dem iPhone**. Wer sie auch bei Instagram beenden will: in Instagram unter *Kontenübersicht → Passwort und Sicherheit → Wo du angemeldet bist*.

## Regeln selbst anpassen

Alle Kommentare im Code sind auf Deutsch. Die Blockade ist dreifach abgesichert:

| Datei | Aufgabe |
|---|---|
| [OhneReels/Regelwerk.swift](OhneReels/Regelwerk.swift) | Navigationsregeln in Swift: welche Adressen erlaubt, umgeleitet oder in Safari geöffnet werden |
| [Ressourcen/userscript.js](Ressourcen/userscript.js) | Dieselben Regeln für Instagrams Single-Page-Navigation, dazu CSS und die Suche nach Vorschlägen, Werbung und der Leiste |
| [OhneReels/Blockliste.swift](OhneReels/Blockliste.swift) | Tracking-Blocker und einfache Ausblend-Regeln direkt in WebKit |
| [OhneReels/Datenschutz.swift](OhneReels/Datenschutz.swift) | Cookie-Liste und Löschroutinen |
| [OhneReels/Einstellungen.swift](OhneReels/Einstellungen.swift) | Schalter und ihre Standardwerte |

Typische Anpassungen in `userscript.js`, Abschnitt 1:

- Instagram nennt einen Vorschlags-Block anders → Text in `TEXTE_VORSCHLAG` ergänzen.
- Werbung rutscht durch → Kennzeichnung in `TEXTE_WERBUNG` ergänzen.
- Videos im Feed sollen bleiben → `VIDEOS_IM_FEED_AUSBLENDEN = false`.
- Ein „App öffnen“-Knopf bleibt stehen → Beschriftung in `TEXTE_APP` ergänzen.

Wer eine Navigationsregel ändert, ändert sie am besten in `Regelwerk.swift` **und** in `userscript.js`.

Nach jeder Änderung: hochladen bzw. pushen → Actions baut neu → neue .ipa installieren.

## Was noch nicht auf einem echten iPhone getestet wurde

Diese App wurde ohne Mac und ohne iPhone geschrieben. Geprüft sind die Syntax des Userscripts und seine Navigationsregeln (automatisch durchgespielt). **Nicht** geprüft werden konnte alles, was von Instagrams tatsächlichem Seitenaufbau abhängt:

1. **Kompiliert der Swift-Code?** Sorgfältig gegengelesen, aber nie durch einen Compiler gelaufen. Der erste Actions-Lauf zeigt es.
2. **Erkennung von Instagrams Leiste** (zum Ausblenden und für den Profil-Tab). Schlägt sie fehl, bleibt die Leiste sichtbar und der Profil-Tab bittet um den Benutzernamen in den Einstellungen.
3. **Vorschläge und Werbung im Feed.** Die Erkennung läuft über sichtbare Texte und den „Folgen“-Knopf. Möglich sind durchrutschende Anzeigen oder Lücken im Feed.
4. **Reels im Feed.** Es werden alle Beiträge mit Video ausgeblendet – auch Karussells, die ein Video enthalten.
5. **Geteilte Reels in Nachrichten.** Ob Instagram sie als Einzelansicht oder im wischbaren Betrachter öffnet, ist unbekannt. Für beide Fälle gibt es Regeln; die Wisch-Sperre selbst ist ungetestet.
6. **Suche.** Der Suche-Tab öffnet `/explore/` mit unsichtbarem Raster. Ob das Suchfeld dort wie erwartet erscheint, muss sich zeigen.
7. **Feed aus / Profilraster aus.** Beiträge werden unsichtbar, der Platz bleibt aber teils belegt (leere Fläche).
8. **Löschen im Hintergrund.** Ende-zu-Ende-verschlüsselte Chats speichern ihre Schlüssel im Website-Speicher. Es kann sein, dass Instagram deshalb nach jedem Start nach der Chat-PIN fragt oder ältere verschlüsselte Nachrichten nicht zeigt.
9. **Tracking-Blockliste.** Die Muster sind nach den Regeln von WebKit geschrieben, aber nie von WebKit kompiliert worden. Scheitert das, läuft die App ohne diesen Schutz weiter.
10. **Kamera und Fotos.** Die Berechtigungstexte sind gesetzt; der Upload selbst ist ungetestet.
