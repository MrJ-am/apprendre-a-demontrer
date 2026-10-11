/* Pont navigateur uniquement : Pointer Events, fichiers et stockage. Elm reste
   l'unique autorité sur les formules, les contextes, les preuves et l'historique. */
window.installerAtelier = (app) => {
  "use strict";
  const cle = "mrjam.atelier-preuves.v1";
  const envoyer = (evenement) => app.ports.atelierEvenement.send(evenement);
  const erreur = (message) => envoyer({ type: "erreur-stockage", message });
  app.ports.atelierCommande.subscribe(
    ({ operation, document: travail, intervalle }) => {
      if (operation === "sauvegarder") {
        try {
          localStorage.setItem(cle, JSON.stringify(travail));
        } catch {
          erreur("Le navigateur refuse la sauvegarde locale.");
        }
      } else if (operation === "recentrer") {
        document.getElementById("atelier-surface")?.scrollTo(0, 0);
      } else if (operation === "exporter") {
        exporter(travail);
      } else if (operation === "importer") {
        importer();
      } else if (operation === "defiler") {
        defiler(intervalle);
      }
    },
  );
  function exporter(travail) {
    const blob = new Blob([JSON.stringify(travail, null, 2) + "\n"], {
      type: "application/json",
    });
    const adresse = URL.createObjectURL(blob);
    const lien = document.createElement("a");
    lien.href = adresse;
    lien.download = "atelier-preuves.json";
    lien.click();
    setTimeout(() => URL.revokeObjectURL(adresse), 1000);
  }
  function importer() {
    const fichier = document.createElement("input");
    fichier.type = "file";
    fichier.accept = ".json,application/json";
    fichier.setAttribute("aria-label", "Importer une preuve JSON");
    fichier.addEventListener("change", async () => {
      const choix = fichier.files?.[0];
      if (!choix) return;
      if (choix.size > 2_000_000) {
        erreur("Ce fichier dépasse la limite de 2 Mo.");
        return;
      }
      try {
        envoyer({ type: "import", texte: await choix.text() });
      } catch {
        erreur("La lecture du fichier a échoué.");
      }
    });
    fichier.click();
  }
  try {
    const sauvegarde = localStorage.getItem(cle);
    if (sauvegarde !== null) envoyer({ type: "restaurer", texte: sauvegarde });
  } catch {
    erreur("La sauvegarde locale est inaccessible.");
  }

  let geste = null;
  let bloquerClic = false;

  // Une pièce se prend par sa surface, pas seulement par son libellé.
  // Les cavités restent défilables et les commandes gardent leur action.
  const poigneeAuPoint = (element) => {
    const directe = element.closest("#atelier [data-atelier-source]");
    if (directe) return directe;
    if (element.closest('button, input, textarea, select, a, [role="button"]'))
      return null;
    const surface = element.closest(
      '[data-mrjam-construction="entete"], [data-mrjam-construction="pied"], [data-mrjam-construction="epine"], [data-mrjam-construction="traverse"], [data-mrjam-construction="objet"]',
    );
    return surface?.closest("#atelier [data-atelier-piece]") ?? null;
  };
  const nettoyer = () => {
    if (!geste) return;
    envoyer({ type: "fin-geste" });
    const { poignee, id } = geste;
    geste = null;

    if (poignee.hasPointerCapture(id)) poignee.releasePointerCapture(id);
  };
  const cibleAuPoint = (x, y) => {
    for (const element of document.elementsFromPoint(x, y)) {
      const cible = element.closest("#atelier [data-atelier-cible]");
      if (cible) return cible;
    }
    const element = document.elementFromPoint(x, y);
    // Le fond libre est la fin de la séquence ; aucune coordonnée n'entre
    // dans le modèle logique. Une formule garde ses emplacements spécifiques.
    if (
      !/^(prop:|atome:|connecteur:)/.test(geste.source) &&
      !element?.closest(
        '[data-mrjam-construction="bloc"], [data-atelier-cible]',
      )
    ) {
      const fond = element?.closest("#atelier [data-atelier-fond]");
      if (fond) return fond;
    }
    return null;
  };
  const actualiser = () => {
    if (!geste?.actif) return;
    const { x, y } = geste;
    geste.zone = cibleAuPoint(x, y);
    const cible =
      geste.zone?.dataset.atelierCible ??
      geste.zone?.dataset.atelierFond ??
      null;
    envoyer({
      type: "geste",
      source: geste.source,
      cible,
      x,
      y,
      largeur: geste.largeur,
    });
  };
  const defiler = (delta) => {
    if (!geste?.actif) return;
    const sous = document.elementFromPoint(geste.x, geste.y);
    const panneau = sous?.closest(
      '[data-atelier-defile], [data-mrjam-construction="palette"]',
    );
    if (panneau) {
      const cadre = panneau.getBoundingClientRect();
      const vitesse = (point, debut, fin) => {
        const marge = Math.min(50, (fin - debut) / 5);
        return point < debut + marge
          ? -Math.ceil((debut + marge - point) / 6)
          : point > fin - marge
            ? Math.ceil((point - fin + marge) / 6)
            : 0;
      };
      panneau.scrollBy(
        (vitesse(geste.x, cadre.left, cadre.right) *
          Math.min(50, Math.max(0, delta))) /
          (1000 / 60),
        (vitesse(geste.y, cadre.top, cadre.bottom) *
          Math.min(50, Math.max(0, delta))) /
          (1000 / 60),
      );
    }
    actualiser();
  };
  // Chromium peut ajuster un toucher près d'un bouton vers ce bouton voisin.
  // La prise vise la surface peinte au point réel, sans bloquer les gestes
  // natifs ailleurs ni les taps ordinaires sur les commandes.
  document.addEventListener(
    "touchstart",
    (e) => {
      const point = e.touches[0];
      if (!point) return;
      const prise = poigneeAuPoint(
        document.elementFromPoint(point.clientX, point.clientY),
      );
      if (prise && prise !== poigneeAuPoint(e.target)) e.preventDefault();
    },
    { passive: false },
  );
  document.addEventListener("pointerdown", (e) => {
    if (!e.isPrimary || (e.pointerType !== "touch" && e.button !== 0) || geste)
      return;
    const poignee =
      poigneeAuPoint(document.elementFromPoint(e.clientX, e.clientY)) ??
      poigneeAuPoint(e.target);
    if (!poignee) return;
    geste = {
      id: e.pointerId,
      poignee,
      source: poignee.dataset.atelierSource ?? poignee.dataset.atelierPiece,
      departX: e.clientX,
      departY: e.clientY,
      x: e.clientX,
      y: e.clientY,
      actif: false,
      zone: null,
      largeur: 0,
    };
  });
  document.addEventListener(
    "pointermove",
    (e) => {
      if (!geste || e.pointerId !== geste.id) return;
      geste.x = e.clientX;
      geste.y = e.clientY;
      if (
        !geste.actif &&
        Math.hypot(e.clientX - geste.departX, e.clientY - geste.departY) >= 7
      ) {
        geste.actif = true;
        geste.poignee.setPointerCapture(e.pointerId);
        const modele = /^(prop:|atome:|connecteur:)/.test(geste.source)
          ? geste.poignee
          : geste.poignee.closest('[data-mrjam-construction="bloc"]') ||
            geste.poignee;
        geste.largeur = Math.min(500, modele.getBoundingClientRect().width);
      }
      if (geste.actif) {
        e.preventDefault();
        actualiser();
      }
    },
    { passive: false },
  );
  document.addEventListener("pointerup", (e) => {
    if (!geste || e.pointerId !== geste.id) return;
    if (geste.actif) {
      e.preventDefault();
      geste.x = e.clientX;
      geste.y = e.clientY;
      actualiser();
      const cible =
        geste.zone?.dataset.atelierCible ?? geste.zone?.dataset.atelierFond;
      const source = geste.source;
      bloquerClic = true;
      setTimeout(() => {
        bloquerClic = false;
      }, 0);
      nettoyer();
      if (cible) envoyer({ type: "depot", source, cible });
    } else nettoyer();
  });
  document.addEventListener("pointercancel", (e) => {
    if (geste?.id === e.pointerId) nettoyer();
  });
  document.addEventListener("contextmenu", (e) => {
    if (geste || poigneeAuPoint(e.target)) e.preventDefault();
  });
  document.addEventListener("dragstart", (e) => {
    if (poigneeAuPoint(e.target)) e.preventDefault();
  });
  document.addEventListener("lostpointercapture", (e) => {
    if (
      geste &&
      e.pointerId === geste.id &&
      e.target === geste.poignee &&
      !geste.poignee.hasPointerCapture(e.pointerId)
    )
      nettoyer();
  });
  document.addEventListener(
    "click",
    (e) => {
      if (bloquerClic && e.detail !== 0) {
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    },
    true,
  );
  addEventListener("blur", nettoyer);
  document.addEventListener("keydown", (e) => {
    if (!document.getElementById("atelier")) return;
    if (e.key === "Escape") {
      nettoyer();
      envoyer({ type: "echapper" });
    }
    const saisie = e.target.closest("input,textarea,[contenteditable=true]");
    if (!saisie && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
      e.preventDefault();
      envoyer({ type: e.shiftKey ? "retablir" : "annuler" });
    }
  });
};
