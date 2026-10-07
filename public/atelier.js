/* Pont navigateur uniquement : Pointer Events, fichiers et stockage. Elm reste
   l'unique autorité sur les formules, les contextes, les preuves et l'historique. */
window.installerAtelier = (app) => {
  "use strict";
  const cle = "mrjam.atelier-preuves.v1";
  const envoyer = (evenement) => app.ports.atelierEvenement.send(evenement);
  const erreur = (message) => envoyer({ type: "erreur-stockage", message });
  app.ports.atelierCommande.subscribe(({ operation, document: travail }) => {
    if (operation === "sauvegarder") {
      try {
        localStorage.setItem(cle, JSON.stringify(travail));
      } catch {
        erreur("Le navigateur refuse la sauvegarde locale.");
      }
    } else if (operation === "recentrer") {
      document.getElementById("atelier-surface")?.scrollTo(0, 0);
    } else if (operation === "exporter") {
      const blob = new Blob([JSON.stringify(travail, null, 2) + "\n"], {
        type: "application/json",
      });
      const adresse = URL.createObjectURL(blob);
      const lien = document.createElement("a");
      lien.href = adresse;
      lien.download = "atelier-preuves.json";
      lien.click();
      setTimeout(() => URL.revokeObjectURL(adresse), 1000);
    } else if (operation === "importer") {
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
  });
  try {
    const sauvegarde = localStorage.getItem(cle);
    if (sauvegarde !== null) envoyer({ type: "restaurer", texte: sauvegarde });
  } catch {
    erreur("La sauvegarde locale est inaccessible.");
  }

  let geste = null;
  let bloquerClic = false;
  let frame = null;
  // Une pièce se prend par sa surface, pas seulement par son libellé.
  // Les cavités restent défilables et les commandes gardent leur action.
  const poigneeAuPoint = (element) => {
    const directe = element.closest("#atelier [data-atelier-source]");
    if (directe) return directe;
    if (element.closest('button, input, textarea, select, a, [role="button"]'))
      return null;
    const surface = element.closest(
      ".mrjam-bloc-entete, .mrjam-bloc-pied, .mrjam-bloc-epine, .mrjam-bloc-traverse, .mrjam-proposition",
    );
    return surface?.closest("#atelier [data-atelier-piece]") ?? null;
  };
  const nettoyer = () => {
    if (!geste) return;
    geste.fantome?.remove();
    geste.zone?.removeAttribute("data-depot-actif");
    geste.poignee.removeAttribute("data-saisie-active");
    document.getElementById("atelier")?.classList.remove("en-deplacement");
    const { poignee, id } = geste;
    geste = null;
    cancelAnimationFrame(frame);
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
      !element?.closest(".mrjam-bloc, [data-atelier-cible]")
    ) {
      const fond = element?.closest("#atelier [data-atelier-fond]");
      if (fond) return fond;
    }
    return null;
  };
  const actualiser = () => {
    if (!geste?.actif) return;
    const { x, y, fantome } = geste;
    fantome.style.transform = `translate(${x + 12}px, ${y + 12}px)`;
    const zone = cibleAuPoint(x, y);
    if (zone !== geste.zone) {
      geste.zone?.removeAttribute("data-depot-actif");
      zone?.setAttribute("data-depot-actif", "true");
      geste.zone = zone;
    }
  };
  const defiler = () => {
    if (!geste?.actif) return;
    const sous = document.elementFromPoint(geste.x, geste.y);
    const panneau = sous?.closest(
      "[data-atelier-defile], .mrjam-atelier-palette",
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
        vitesse(geste.x, cadre.left, cadre.right),
        vitesse(geste.y, cadre.top, cadre.bottom),
      );
    }
    actualiser();
    frame = requestAnimationFrame(defiler);
  };
  document.addEventListener("pointerdown", (e) => {
    if (!e.isPrimary || (e.pointerType !== "touch" && e.button !== 0) || geste)
      return;
    const poignee = poigneeAuPoint(e.target);
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
      fantome: null,
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
        document.getElementById("atelier")?.classList.add("en-deplacement");
        geste.poignee.setPointerCapture(e.pointerId);
        const modele =
          geste.source.startsWith("prop:") ||
          geste.source.startsWith("atome:") ||
          geste.source.startsWith("connecteur:")
            ? geste.poignee
            : geste.poignee.closest(".mrjam-bloc") || geste.poignee;
        const fantome = modele.cloneNode(true);
        fantome.classList.add("atelier-fantome");
        fantome.setAttribute("aria-hidden", "true");
        for (const el of [fantome, ...fantome.querySelectorAll("*")]) {
          el.removeAttribute("id");
          el.removeAttribute("data-atelier-cible");
          el.removeAttribute("data-bloc");
          el.removeAttribute("data-testid");
          el.setAttribute("tabindex", "-1");
        }
        fantome.style.width = `${Math.min(500, modele.getBoundingClientRect().width)}px`;
        document.body.append(fantome);
        geste.fantome = fantome;
        geste.poignee.setAttribute("data-saisie-active", "true");
        frame = requestAnimationFrame(defiler);
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
