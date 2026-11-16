/*
 * Ohne Reels – Userscript (zweite Sicherung neben den Swift-Regeln in Regelwerk.swift)
 *
 * Wird von der App ab "documentStart" in jede Instagram-Seite eingespielt und
 *   1. blendet Unerwünschtes per CSS aus,
 *   2. durchsucht die Seite bei jeder Änderung neu (MutationObserver),
 *   3. fängt pushState, replaceState und popstate ab, weil Instagram eine Single-Page-App ist
 *      und beim Navigieren meist KEINE neue Seite lädt.
 *
 * Grundsatz: Es werden nur hrefs, aria-labels und sichtbare Texte (Deutsch und Englisch) benutzt –
 * keine von Instagram automatisch erzeugten Klassennamen, denn die ändern sich ständig.
 *
 * Zum Anpassen: Abschnitt 1 (Listen) und Abschnitt 4 (CSS).
 */
(function () {
  'use strict';

  if (window.__ohneReels) { return; }
  if (!/(^|\.)instagram\.com$/i.test(location.hostname)) { return; }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. ANPASSBARE LISTEN
  // ───────────────────────────────────────────────────────────────────────────

  // Alle Videos im Home-Feed gelten als Reels und werden ausgeblendet.
  // Auf false setzen, wenn nur Beiträge mit ausdrücklichem /reel/-Link verschwinden sollen.
  var VIDEOS_IM_FEED_AUSBLENDEN = true;

  // Überschriften von Vorschlags-Blöcken (exakter Text eines Elements).
  var TEXTE_VORSCHLAG = [
    'Vorgeschlagen für dich', 'Vorschläge für dich', 'Vorgeschlagene Beiträge', 'Vorgeschlagene Reels',
    'Personen entdecken', 'Ähnliche Konten',
    'Suggested for you', 'Suggestions for you', 'Suggested posts', 'Suggested reels',
    'Discover people', 'Similar accounts'
  ];

  // Kennzeichnung von Werbung im Feed (exakter Text eines Elements).
  var TEXTE_WERBUNG = ['Gesponsert', 'Anzeige', 'Sponsored'];

  // "Folgen"-Knopf: Im Home-Feed haben ihn nur Beiträge von Konten, denen du NICHT folgst = Vorschläge.
  var TEXTE_FOLGEN = ['Folgen', 'Follow'];

  // Knöpfe, die in die Instagram-App oder den App Store locken.
  var TEXTE_APP = [
    'App öffnen', 'In der App öffnen', 'In App öffnen', 'Instagram öffnen', 'App verwenden', 'Zur App',
    'App holen', 'App herunterladen', 'Hol dir die App',
    'Open app', 'Open in app', 'Open Instagram', 'Use the app', 'Use app', 'Get the app', 'Get app'
  ];

  // aria-labels des Reels-Symbols (im Deutschen heißt es ebenfalls "Reels").
  var ARIA_REELS = ['Reels'];

  // Erste Pfadteile, die keine Benutzernamen sind (muss zu Regelwerk.swift passen).
  var RESERVIERT = [
    'about', 'accounts', 'ads', 'api', 'ar', 'archive', 'auth_platform', 'challenge', 'consent',
    'create', 'developer', 'direct', 'directory', 'download', 'emails', 'explore', 'fxcal',
    'graphql', 'help', 'invites', 'legal', 'lite', 'locations', 'nametag', 'notifications',
    'oauth', 'p', 'press', 'privacy', 'qr', 'reel', 'reels', 'session', 'settings', 'static',
    'stories', 'tags', 'terms', 'topics', 'tv', 'two_factor', 'web', 'your_activity'
  ];

  // So lange (ms) gilt ein Rücksprung von /reel/CODE/ auf /reels/CODE/ als "Instagram besteht
  // auf dem Reels-Betrachter" (gleiche Logik wie in Regelwerk.swift).
  var RUECKSPRUNG_FRIST = 15000;

  // ───────────────────────────────────────────────────────────────────────────
  // 2. EINSTELLUNGEN (kommen aus der App)
  // ───────────────────────────────────────────────────────────────────────────

  var wurzel = document.documentElement;
  var config = { feed: true, raster: true, navAus: true, diagnose: false };

  function uebernehmeConfig(neu) {
    if (!neu) { return; }
    Object.keys(config).forEach(function (name) {
      if (name in neu) { config[name] = !!neu[name]; }
    });
  }

  // Die Einstellungen landen als Attribute am <html>-Element; das CSS unten reagiert darauf.
  function wendeConfigAn() {
    wurzel.setAttribute('data-or-feed', config.feed ? 'an' : 'aus');
    wurzel.setAttribute('data-or-raster', config.raster ? 'an' : 'aus');
    wurzel.setAttribute('data-or-nav', config.navAus ? 'aus' : 'an');
  }

  uebernehmeConfig(window.__ohneReelsConfig);
  wendeConfigAn();

  // ───────────────────────────────────────────────────────────────────────────
  // 3. NAVIGATIONSREGELN (Spiegel von Regelwerk.swift)
  // ───────────────────────────────────────────────────────────────────────────

  var CODE = /^[A-Za-z0-9_-]{5,}$/;
  var NAME = /^[A-Za-z0-9._]{1,30}$/;

  var akzeptiert = null;       // zuletzt akzeptierter Pfad
  var einzelReel = null;       // { code, zeit } des zuletzt geöffneten /reel/CODE/
  var betrachterCode = null;   // das eine Reel, das im Betrachter /reels/CODE/ bleiben darf

  function teileVon(pfad) {
    return String(pfad || '').split('/').filter(Boolean);
  }

  function istBenutzername(text) {
    return NAME.test(text) && RESERVIERT.indexOf(text.toLowerCase()) < 0;
  }

  // Reel-Code aus /reel/CODE/, /reels/CODE/ oder /name/reel/CODE/ – sonst null.
  function reelCode(teile) {
    var erstes = (teile[0] || '').toLowerCase();
    if (erstes === 'reel' && teile.length >= 2 && CODE.test(teile[1])) { return teile[1]; }
    if (erstes === 'reels' && teile.length === 2 && CODE.test(teile[1])) { return teile[1]; }
    if (teile.length >= 3 && teile[1].toLowerCase() === 'reel' && CODE.test(teile[2])) { return teile[2]; }
    return null;
  }

  // Liefert null, wenn der Pfad erlaubt ist – sonst den Pfad, auf den umgeleitet wird.
  function bewerte(pfad, vorher) {
    var teile = teileVon(pfad);
    var erstes = (teile[0] || '').toLowerCase();
    var neuerCode = reelCode(teile);
    var alterCode = vorher ? reelCode(teileVon(vorher)) : null;

    // REGEL 1 – Kein Wischen von Reel zu Reel.
    if (neuerCode && alterCode && neuerCode !== alterCode) { return vorher; }

    // REGEL 2 – Der Reels-Bereich.
    if (erstes === 'reels') {
      if (!neuerCode) { return '/'; }                         // /reels/ (Feed), /reels/audio/… usw.
      if (betrachterCode === neuerCode) { return null; }
      if (einzelReel && einzelReel.code === neuerCode && Date.now() - einzelReel.zeit < RUECKSPRUNG_FRIST) {
        betrachterCode = neuerCode;                           // Instagram besteht auf dem Betrachter
        return null;
      }
      return '/reel/' + neuerCode + '/';                      // lieber die Einzelansicht
    }

    // REGEL 3 – Explore: nur die Suche bleibt.
    if (erstes === 'explore') {
      if (teile.length === 1) { return null; }
      if (teile.length === 2 && teile[1].toLowerCase() === 'search') { return null; }
      return '/explore/';
    }

    // REGEL 4 – Reels-Tab auf Profilen.
    if (teile.length >= 2 && teile[1].toLowerCase() === 'reels' && istBenutzername(teile[0])) {
      return '/' + teile[0] + '/';
    }

    return null;
  }

  // Seitentyp für das CSS (Attribut data-or-seite am <html>-Element).
  function seitenTyp(pfad) {
    var teile = teileVon(pfad);
    if (teile.length === 0) { return 'home'; }
    var erstes = teile[0].toLowerCase();
    if (erstes === 'explore') { return 'explore'; }
    if (erstes === 'direct') { return 'direct'; }
    if (erstes === 'reels') { return 'betrachter'; }
    if (erstes === 'reel') { return 'reel'; }
    if (erstes === 'p' || erstes === 'tv') { return 'beitrag'; }
    if (erstes === 'stories') { return 'stories'; }
    if (RESERVIERT.indexOf(erstes) >= 0) { return 'sonst'; }
    if (teile.length >= 2 && teile[1].toLowerCase() === 'reel') { return 'reel'; }
    if (teile.length >= 2 && teile[1].toLowerCase() === 'p') { return 'beitrag'; }
    return 'profil';
  }

  function akzeptiere(pfad) {
    akzeptiert = pfad;
    var teile = teileVon(pfad);
    var code = reelCode(teile);
    if (code && (teile[0] || '').toLowerCase() !== 'reels') {
      einzelReel = { code: code, zeit: Date.now() };
    }
    var typ = seitenTyp(pfad);
    if (wurzel.getAttribute('data-or-seite') !== typ) {
      wurzel.setAttribute('data-or-seite', typ);
    }
  }

  // Verbotene Navigation: Seite verbergen und wirklich woanders hin laden.
  // (Nur pushState zu unterdrücken reicht nicht – Instagram würde die Seite trotzdem zeichnen.)
  function leiteUm(ziel, ersetzen) {
    wurzel.setAttribute('data-or-sperre', '1');
    // Notbremse gegen Endlosschleifen: höchstens 8 Umleitungen in 10 Sekunden.
    var jetzt = Date.now();
    var liste = [];
    try { liste = JSON.parse(sessionStorage.getItem('or_umleitungen') || '[]'); } catch (e1) { liste = []; }
    liste = liste.filter(function (zeit) { return jetzt - zeit < 10000; });
    liste.push(jetzt);
    try { sessionStorage.setItem('or_umleitungen', JSON.stringify(liste)); } catch (e2) { /* egal */ }
    if (liste.length > 8) { return; }                  // aufgeben – Seite bleibt verborgen
    if (liste.length > 5) { ziel = '/direct/inbox/'; } // Ausweichziel
    if (ersetzen) { location.replace(ziel); } else { location.assign(ziel); }
  }

  // Prüft einen Pfad. true = erlaubt, false = es wird umgeleitet.
  function pruefe(pfad, ersetzen) {
    var ziel = bewerte(pfad, akzeptiert);
    if (ziel === null) {
      akzeptiere(pfad);
      return true;
    }
    leiteUm(ziel, ersetzen);
    return false;
  }

  // Erster Aufruf beim Laden der Seite. Volle Seitenaufrufe hat Swift bereits geprüft; ein
  // /reels/CODE/ an dieser Stelle ist deshalb der von Swift zugelassene Einzel-Betrachter.
  (function () {
    var start = teileVon(location.pathname);
    if (start.length === 2 && start[0].toLowerCase() === 'reels' && CODE.test(start[1])) {
      betrachterCode = start[1];
    }
    pruefe(location.pathname, true);
  })();

  // pushState / replaceState abfangen.
  ['pushState', 'replaceState'].forEach(function (name) {
    var original = history[name];
    history[name] = function (zustand, titel, adresse) {
      if (adresse !== undefined && adresse !== null) {
        var ziel = null;
        try { ziel = new URL(String(adresse), location.href); } catch (e) { ziel = null; }
        if (ziel && ziel.origin === location.origin && !pruefe(ziel.pathname, name === 'replaceState')) {
          return undefined;   // verbotene Navigation: gar nicht erst ausführen
        }
      }
      var ergebnis = original.apply(this, arguments);
      planeSuche();
      return ergebnis;
    };
  });

  // Zurück / Vorwärts.
  window.addEventListener('popstate', function () {
    pruefe(location.pathname, true);
    planeSuche();
  }, true);

  // Sicherheitsnetz, falls Instagram einmal an den abgefangenen Funktionen vorbei navigiert.
  setInterval(function () {
    if (location.pathname !== akzeptiert) {
      pruefe(location.pathname, true);
      planeSuche();
    }
  }, 500);

  // ───────────────────────────────────────────────────────────────────────────
  // 4. CSS
  // ───────────────────────────────────────────────────────────────────────────

  var CSS = [
    // Während einer Umleitung nichts zeigen.
    'html[data-or-sperre] body { visibility: hidden !important; }',

    // Wege in den Reels-Feed: Symbol in Instagrams Leiste, Reels-Tab auf Profilen, Audio-Seiten.
    // [data-or-weg] setzt das Skript unten an alles, was zusätzlich verschwinden soll.
    'a[href="/reels/"], a[href$="/reels/"], a[href*="/reels/audio/"], [data-or-weg] { display: none !important; }',

    // Sprünge in die App / den App Store.
    'a[href^="instagram://"], a[href*="apps.apple.com"], a[href*="itunes.apple.com"], a[href*="play.google.com"] { display: none !important; }',

    // Instagrams eigene Leiste (das Skript markiert sie mit data-or-leiste, wenn es sie sicher erkannt hat).
    'html[data-or-nav="aus"] [data-or-leiste] { display: none !important; }',

    // Home-Feed aus: Beiträge unsichtbar, Stories-Leiste bleibt. Der Platz bleibt absichtlich belegt
    // und das Scrollen ist gesperrt – sonst würde Instagram endlos weitere Beiträge nachladen.
    'html[data-or-seite="home"][data-or-feed="aus"] article { visibility: hidden !important; pointer-events: none !important; }',
    'html[data-or-seite="home"][data-or-feed="aus"], html[data-or-seite="home"][data-or-feed="aus"] body { overflow: hidden !important; }',

    // Home-Feed an: Reels, Vorschläge und Werbung. "mitte" = verschwindet ganz. "ende" = steht am
    // Schluss der Liste und behält etwas Höhe, damit Instagram nicht endlos nachlädt.
    'html[data-or-seite="home"] article[data-or-aus="mitte"] { display: none !important; }',
    'html[data-or-seite="home"] article[data-or-aus="ende"] { visibility: hidden !important; pointer-events: none !important; max-height: 240px !important; overflow: hidden !important; }',

    // Explore: das Raster mit vorgeschlagenen Inhalten unsichtbar – auch unter dem Suchfeld.
    'html[data-or-seite="explore"] a[href*="/p/"], html[data-or-seite="explore"] a[href*="/reel/"] { visibility: hidden !important; pointer-events: none !important; }',
    'html[data-or-seite="explore"] a[href^="/explore/tags/"], html[data-or-seite="explore"] a[href^="/explore/locations/"], html[data-or-seite="explore"] a[href^="/explore/search/keyword"] { display: none !important; }',

    // Profile: Beitragsraster per Einstellung aus.
    'html[data-or-seite="profil"][data-or-raster="aus"] a[href*="/p/"], html[data-or-seite="profil"][data-or-raster="aus"] a[href*="/reel/"] { visibility: hidden !important; pointer-events: none !important; }'
  ].join('\n');

  var stilElement = document.createElement('style');
  stilElement.id = 'ohne-reels-stil';
  stilElement.textContent = CSS;

  var stilBlatt = null;
  try {
    stilBlatt = new CSSStyleSheet();
    stilBlatt.replaceSync(CSS);
  } catch (e) {
    stilBlatt = null;   // ältere iOS-Versionen: dann nur das <style>-Element
  }

  // Das CSS wird doppelt eingehängt (Element + "adoptedStyleSheets") und bei jeder Suche geprüft.
  function sichereStil() {
    if (!stilElement.isConnected) {
      (document.head || wurzel).appendChild(stilElement);
    }
    if (stilBlatt) {
      try {
        if (document.adoptedStyleSheets.indexOf(stilBlatt) < 0) {
          document.adoptedStyleSheets = Array.from(document.adoptedStyleSheets).concat([stilBlatt]);
        }
      } catch (e) { /* egal */ }
    }
  }
  sichereStil();

  // ───────────────────────────────────────────────────────────────────────────
  // 5. SEITE DURCHSUCHEN (läuft bei jeder Änderung der Seite, höchstens alle 150 ms)
  // ───────────────────────────────────────────────────────────────────────────

  function alle(selektor, basis) {
    return Array.prototype.slice.call((basis || document).querySelectorAll(selektor));
  }

  function trimme(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  // XPath-Ausdruck: Elemente, deren eigener Text exakt einem Listeneintrag entspricht.
  function xpathFuer(texte) {
    var bedingungen = texte.map(function (text) {
      var literal = text.indexOf("'") < 0 ? "'" + text + "'" : '"' + text + '"';
      return 'normalize-space(text())=' + literal;
    });
    return './/*[' + bedingungen.join(' or ') + ']';
  }
  var XPATH_VORSCHLAG = xpathFuer(TEXTE_VORSCHLAG);
  var XPATH_WERBUNG = xpathFuer(TEXTE_WERBUNG);

  function findeText(basis, xpath) {
    var treffer = [];
    try {
      var ergebnis = document.evaluate(xpath, basis, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
      for (var i = 0; i < ergebnis.snapshotLength; i++) { treffer.push(ergebnis.snapshotItem(i)); }
    } catch (e) { /* egal */ }
    return treffer;
  }

  function hatKnopfMitText(basis, texte) {
    return alle('button, [role="button"]', basis).some(function (knopf) {
      return texte.indexOf(trimme(knopf.textContent)) >= 0;
    });
  }

  // Blendet ein Element aus – samt Hüllen, die NUR dieses Element enthalten (sonst bleibt eine Lücke).
  function versteckeMitHuelle(element) {
    var ziel = element;
    var eltern = element.parentElement;
    var tiefe = 0;
    while (eltern && tiefe < 4 && eltern !== document.body && eltern.children.length === 1 &&
           !eltern.hasAttribute('data-or-leiste')) {
      ziel = eltern;
      eltern = eltern.parentElement;
      tiefe++;
    }
    if (!ziel.hasAttribute('data-or-weg')) { ziel.setAttribute('data-or-weg', '1'); }
  }

  // 5a. Wege in den Reels-Feed.
  function versteckeReelsEinstiege(typ) {
    alle('a[href="/reels/"], a[href$="/reels/"]').forEach(versteckeMitHuelle);
    // Zusätzlich über das aria-label des Symbols – aber nicht in Nachrichten, damit geteilte
    // Reels dort sichtbar bleiben, und nie bei Links auf einen einzelnen Beitrag.
    if (typ === 'direct') { return; }
    ARIA_REELS.forEach(function (label) {
      alle('svg[aria-label="' + label + '"], a[aria-label="' + label + '"], [role="tab"][aria-label="' + label + '"]')
        .forEach(function (element) {
          var klickbar = element.closest('a, [role="tab"], [role="link"], [role="button"], button');
          if (!klickbar) { return; }
          var href = klickbar.getAttribute('href') || '';
          if (/\/(reel|p|tv)\/[^/]+/.test(href)) { return; }
          versteckeMitHuelle(klickbar);
        });
    });
  }

  // 5b. "App öffnen"-Knöpfe und -Banner.
  function versteckeAppHinweise() {
    alle('a, button, [role="button"]').forEach(function (element) {
      if (element.hasAttribute('data-or-weg')) { return; }
      var text = element.textContent || '';
      if (text.length === 0 || text.length > 40) { return; }
      if (TEXTE_APP.indexOf(trimme(text)) >= 0) { versteckeMitHuelle(element); }
    });
  }

  // 5c. Instagrams eigene Leiste finden. Sie wird nur markiert, wenn alles zusammenpasst:
  //     enthält den Home-Link UND einen weiteren Hauptlink, ist flach, breit und sitzt unten.
  //     Passt etwas nicht, bleibt die Leiste einfach sichtbar (nur ohne Reels-Symbol).
  var gemeldeterName = null;

  function findeLeiste() {
    var leiste = document.querySelector('[data-or-leiste]');
    if (!leiste) {
      var anker = alle('a[href="/explore/"], a[href="/direct/inbox/"], a[href="/reels/"]');
      for (var i = 0; i < anker.length && !leiste; i++) {
        var element = anker[i].parentElement;
        var tiefe = 0;
        while (element && element !== document.body && tiefe < 8) {
          if (element.querySelector('a[href="/"]')) {
            var kasten = element.getBoundingClientRect();
            if (kasten.height > 0 && kasten.height <= 110 && kasten.width >= window.innerWidth * 0.8 &&
                kasten.top >= window.innerHeight * 0.6) {
              leiste = element;
            }
            break;
          }
          element = element.parentElement;
          tiefe++;
        }
      }
      if (leiste) {
        // Flache Hüllen (Rahmen, Hintergrund) mitnehmen.
        var eltern = leiste.parentElement;
        while (eltern && eltern !== document.body && eltern.tagName !== 'MAIN') {
          var hoehe = eltern.getBoundingClientRect().height;
          if (hoehe <= 0 || hoehe > 110) { break; }
          leiste = eltern;
          eltern = eltern.parentElement;
        }
        leiste.setAttribute('data-or-leiste', '1');
      }
    }
    if (leiste) { meldeBenutzer(leiste); }
  }

  // Der Profil-Link in der Leiste verrät den eigenen Benutzernamen – die App braucht ihn für den Profil-Tab.
  function meldeBenutzer(leiste) {
    var links = alle('a[href]', leiste);
    for (var i = 0; i < links.length; i++) {
      var treffer = /^\/([A-Za-z0-9._]{1,30})\/$/.exec(links[i].getAttribute('href') || '');
      if (treffer && istBenutzername(treffer[1])) {
        if (treffer[1] !== gemeldeterName) {
          gemeldeterName = treffer[1];
          sende({ typ: 'benutzer', name: gemeldeterName });
        }
        return;
      }
    }
  }

  function sende(nachricht) {
    try { window.webkit.messageHandlers.ohneReels.postMessage(nachricht); } catch (e) { /* egal */ }
  }

  // 5d. Home-Feed: Reels, Vorschläge und Werbung.
  function grundFuer(artikel) {
    if (artikel.querySelector('a[href*="/reel/"]')) { return 'reel'; }
    if (VIDEOS_IM_FEED_AUSBLENDEN && artikel.querySelector('video')) { return 'reel'; }
    if (findeText(artikel, XPATH_WERBUNG).length > 0) { return 'werbung'; }
    if (findeText(artikel, XPATH_VORSCHLAG).length > 0) { return 'vorschlag'; }
    if (hatKnopfMitText(artikel, TEXTE_FOLGEN)) { return 'vorschlag'; }
    return null;
  }

  function filtereFeed() {
    var artikel = alle('article');
    artikel.forEach(function (eintrag) {
      if (eintrag.hasAttribute('data-or-grund')) { return; }
      var grund = grundFuer(eintrag);
      if (grund) { eintrag.setAttribute('data-or-grund', grund); }
    });
    // Von hinten nach vorn: Ausgeblendetes am Listenende bekommt "ende", alles davor "mitte".
    var sichtbaresDanach = false;
    for (var i = artikel.length - 1; i >= 0; i--) {
      if (artikel[i].hasAttribute('data-or-grund')) {
        var modus = sichtbaresDanach ? 'mitte' : 'ende';
        if (artikel[i].getAttribute('data-or-aus') !== modus) { artikel[i].setAttribute('data-or-aus', modus); }
      } else {
        sichtbaresDanach = true;
      }
    }
  }

  // 5e. Vorschlags-Blöcke außerhalb von Beiträgen ("Vorgeschlagen für dich" mit Konten-Karussell).
  function zaehleProfilLinks(basis) {
    var gesehen = {};
    var anzahl = 0;
    alle('a[href]', basis).forEach(function (link) {
      var treffer = /^\/([A-Za-z0-9._]{1,30})\/$/.exec(link.getAttribute('href') || '');
      if (treffer && istBenutzername(treffer[1]) && !gesehen[treffer[1]]) {
        gesehen[treffer[1]] = true;
        anzahl++;
      }
    });
    return anzahl;
  }

  function versteckeVorschlaege() {
    findeText(document.body, XPATH_VORSCHLAG).forEach(function (ueberschrift) {
      if (ueberschrift.closest('[data-or-weg], article, [data-or-leiste]')) { return; }
      var kandidat = ueberschrift.parentElement;
      var tiefe = 0;
      while (kandidat && tiefe < 6 && kandidat !== document.body && kandidat.tagName !== 'MAIN') {
        // Zu groß geraten (enthält Beiträge oder die Navigation)? Dann lieber nichts ausblenden.
        if (kandidat.querySelector('article, nav, [data-or-leiste]')) { return; }
        if (zaehleProfilLinks(kandidat) >= 2 || kandidat.querySelector('a[href^="/explore/people"]')) {
          if (kandidat.getBoundingClientRect().height < window.innerHeight * 0.9) {
            kandidat.setAttribute('data-or-weg', '1');
          }
          return;
        }
        kandidat = kandidat.parentElement;
        tiefe++;
      }
    });
  }

  // Jeder Schritt einzeln abgesichert: Ein Fehler in einem Schritt hält die anderen nicht auf.
  function versuche(schritt) {
    try { schritt(); } catch (e) { /* egal */ }
  }

  var geplant = false;

  function suche() {
    geplant = false;
    sichereStil();
    if (!document.body) { return; }
    var typ = wurzel.getAttribute('data-or-seite');
    versuche(function () { versteckeReelsEinstiege(typ); });
    versuche(versteckeAppHinweise);
    versuche(findeLeiste);
    if (typ === 'home') { versuche(filtereFeed); }
    versuche(versteckeVorschlaege);
  }

  function planeSuche() {
    if (geplant) { return; }
    geplant = true;
    setTimeout(suche, 150);
  }

  new MutationObserver(planeSuche).observe(wurzel, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', planeSuche);
  planeSuche();

  // ───────────────────────────────────────────────────────────────────────────
  // 6. WISCH-SPERRE IM REELS-BETRACHTER
  // ───────────────────────────────────────────────────────────────────────────
  // Öffnet sich ein geteiltes Reel im wischbaren Betrachter, werden senkrechte Wischgesten
  // verschluckt – außer in Dialogen (z. B. Kommentare). Regel 1 oben ist die zweite Absicherung:
  // Wechselt die Adresse doch auf ein anderes Reel, wird das erlaubte Reel neu geladen.

  //
  // Die Sperre hängt NICHT nur an der Adresse: Aus den Nachrichten heraus öffnet Instagram ein Reel
  // auch als Überlagerung, ohne die Adresse zu ändern. Deshalb wird zusätzlich am Inhalt erkannt,
  // ob gerade ein bildschirmfüllendes Video gezeigt wird.

  // Ab diesem Anteil der Bildschirmhöhe gilt ein Video als "bildschirmfüllend" (Reel-Betrachter).
  var VIDEO_MINDESTHOEHE = 0.7;

  var startX = 0;
  var startY = 0;
  var gesperrt = false;   // wird bei jedem Berührungsbeginn neu bestimmt

  // Gibt es in "basis" ein Video, das gerade (fast) den ganzen Bildschirm füllt?
  function hatGrossesVideo(basis) {
    var hoehe = window.innerHeight;
    return alle('video', basis).some(function (video) {
      var kasten = video.getBoundingClientRect();
      return kasten.height >= hoehe * VIDEO_MINDESTHOEHE &&
             kasten.top < hoehe * 0.3 && kasten.bottom > hoehe * 0.7;
    });
  }

  // Nächster Vorfahre, der sich senkrecht scrollen lässt (null = die Seite selbst scrollt).
  function scrollBehaelter(element) {
    while (element && element !== document.body && element !== wurzel) {
      if (element.scrollHeight > element.clientHeight + 10) {
        var art = getComputedStyle(element).overflowY;
        if (art === 'auto' || art === 'scroll' || art === 'overlay') { return element; }
      }
      element = element.parentElement;
    }
    return null;
  }

  function sollSperren(ziel) {
    var typ = wurzel.getAttribute('data-or-seite');
    // Feed und Stories sind nie betroffen (Videos im Feed blendet Abschnitt 5d ohnehin aus).
    if (typ === 'home' || typ === 'stories') { return false; }
    if (!ziel || !ziel.closest) { return false; }

    // Fall 1: Der Finger liegt in einer scrollbaren Liste. Gesperrt wird sie nur, wenn sie selbst
    // das bildschirmfüllende Video enthält – Kommentare und der Chatverlauf bleiben scrollbar.
    var behaelter = scrollBehaelter(ziel);
    if (behaelter) { return hatGrossesVideo(behaelter); }

    // Fall 2: Kein eigener Scrollbereich (die Seite scrollt, oder Instagram wertet die Wischgeste
    // selbst aus). Dialoge ohne Video (z. B. Kommentare, Teilen) bleiben bedienbar.
    var dialog = ziel.closest('[role="dialog"]');
    if (dialog && !dialog.querySelector('video')) { return false; }
    if (typ === 'betrachter') { return true; }
    if (typ === 'reel' && document.querySelectorAll('video').length > 1) { return true; }
    return hatGrossesVideo(document);
  }

  document.addEventListener('touchstart', function (ereignis) {
    if (ereignis.touches.length > 0) {
      startX = ereignis.touches[0].clientX;
      startY = ereignis.touches[0].clientY;
    }
    gesperrt = false;
    try { gesperrt = sollSperren(ereignis.target); } catch (e) { gesperrt = false; }
    if (config.diagnose) {
      try { letzteBeruehrung = beschreibeBeruehrung(ereignis.target); } catch (e2) { letzteBeruehrung = 'Fehler: ' + e2; }
    }
  }, { capture: true, passive: true });

  document.addEventListener('touchmove', function (ereignis) {
    if (!gesperrt || ereignis.touches.length === 0) { return; }
    var dx = Math.abs(ereignis.touches[0].clientX - startX);
    var dy = Math.abs(ereignis.touches[0].clientY - startY);
    if (dy > dx) {
      if (ereignis.cancelable) { ereignis.preventDefault(); }
      ereignis.stopPropagation();
    }
  }, { capture: true, passive: false });

  // ───────────────────────────────────────────────────────────────────────────
  // 7. DIAGNOSE (nur wenn in den Einstellungen eingeschaltet)
  // ───────────────────────────────────────────────────────────────────────────
  // Zeigt einen Kasten mit technischen Angaben über der Seite. Gedacht für einen Screenshot,
  // wenn etwas nicht so aussieht oder sich nicht so verhält wie erwartet. Es wird nichts verschickt.

  var letzteBeruehrung = '–';
  var diagnoseKasten = null;

  function masse(element) {
    var k = element.getBoundingClientRect();
    return Math.round(k.left) + ',' + Math.round(k.top) + ' ' + Math.round(k.width) + 'x' + Math.round(k.height);
  }

  function kurz(element) {
    if (!element || !element.tagName) { return '–'; }
    var rolle = element.getAttribute('role');
    return element.tagName.toLowerCase() + (rolle ? '[' + rolle + ']' : '') + ' ' + masse(element);
  }

  function beschreibeBeruehrung(ziel) {
    var behaelter = scrollBehaelter(ziel);
    var dialog = ziel && ziel.closest ? ziel.closest('[role="dialog"]') : null;
    return 'gesperrt=' + gesperrt + ' ziel=' + kurz(ziel) +
      '\n  scroller=' + (behaelter
        ? kurz(behaelter) + ' inhalt=' + behaelter.scrollHeight + ' pos=' + Math.round(behaelter.scrollTop) +
          ' videos=' + behaelter.querySelectorAll('video').length + ' gross=' + hatGrossesVideo(behaelter)
        : 'keiner (seite=' + wurzel.scrollHeight + ')') +
      '\n  dialog=' + (dialog ? 'ja videos=' + dialog.querySelectorAll('video').length : 'nein');
  }

  function zeigeDiagnose() {
    if (!config.diagnose || !document.body) {
      if (diagnoseKasten) { diagnoseKasten.remove(); diagnoseKasten = null; }
      return;
    }
    if (!diagnoseKasten) {
      diagnoseKasten = document.createElement('pre');
      diagnoseKasten.setAttribute('style',
        'position:fixed;left:6px;top:90px;max-width:86%;margin:0;padding:6px;z-index:2147483647;' +
        'font:10px/1.3 Menlo,monospace;color:#7CFC00;background:rgba(0,0,0,0.8);border-radius:6px;' +
        'white-space:pre-wrap;word-break:break-all;pointer-events:none;');
    }
    if (!diagnoseKasten.isConnected) { document.body.appendChild(diagnoseKasten); }

    var zeilen = [];
    zeilen.push('pfad=' + location.pathname);
    zeilen.push('typ=' + wurzel.getAttribute('data-or-seite') + ' fenster=' + window.innerWidth + 'x' + window.innerHeight);
    zeilen.push('breite html=' + wurzel.scrollWidth + ' body=' + document.body.scrollWidth +
      ' scrollX=' + Math.round(window.scrollX));
    if (window.visualViewport) {
      var v = window.visualViewport;
      zeilen.push('ansicht=' + Math.round(v.width) + 'x' + Math.round(v.height) + ' zoom=' + v.scale.toFixed(2) +
        ' links=' + Math.round(v.offsetLeft));
    }
    var videos = alle('video');
    zeilen.push('videos=' + videos.length + videos.slice(0, 3).map(function (video) { return '\n  ' + masse(video); }).join(''));
    // Was liegt am rechten Rand, Bildschirmmitte? (für den schwarzen Balken)
    var rechts = document.elementFromPoint(window.innerWidth - 8, window.innerHeight / 2);
    for (var i = 0; rechts && i < 3; i++) {
      zeilen.push('rechts' + i + '=' + kurz(rechts) + ' ' + getComputedStyle(rechts).backgroundColor);
      rechts = rechts.parentElement;
    }
    zeilen.push('beruehrung: ' + letzteBeruehrung);
    var text = zeilen.join('\n');
    if (diagnoseKasten.textContent !== text) { diagnoseKasten.textContent = text; }
  }

  setInterval(function () {
    try { zeigeDiagnose(); } catch (e) { /* egal */ }
  }, 700);

  // ───────────────────────────────────────────────────────────────────────────
  // 8. SCHNITTSTELLE FÜR DIE APP
  // ───────────────────────────────────────────────────────────────────────────

  window.__ohneReels = {
    // Neue Einstellungen aus dem Einstellungsbildschirm übernehmen.
    setzeConfig: function (neu) {
      uebernehmeConfig(neu);
      wendeConfigAn();
      planeSuche();
    },
    // Für "Tipp auf den aktiven Tab".
    nachOben: function () {
      try { window.scrollTo({ top: 0, behavior: 'smooth' }); } catch (e) { window.scrollTo(0, 0); }
    },
    // Tippt Instagrams eigenen (ggf. unsichtbaren) Navigationslink an. true = hat geklappt.
    gehe: function (pfad) {
      var leiste = document.querySelector('[data-or-leiste]');
      if (!leiste) { return false; }
      var links = alle('a[href]', leiste);
      for (var i = 0; i < links.length; i++) {
        if (links[i].getAttribute('href') === pfad) {
          links[i].click();
          return true;
        }
      }
      return false;
    }
  };
})();
