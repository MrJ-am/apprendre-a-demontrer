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
  const nettoyer = () => {
    if (!geste) return;
    geste.fantome?.remove();
    geste.zone?.removeAttribute("data-depot-actif");
    geste.poignee.removeAttribute("data-saisie-active");
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
    const marge = 85;
    const delta =
      geste.y < marge
        ? -Math.ceil((marge - geste.y) / 5)
        : geste.y > innerHeight - marge
          ? Math.ceil((geste.y - innerHeight + marge) / 5)
          : 0;
    if (delta) {
      // Défiler le panneau situé sous le pointeur, puis la page s'il est en butée.
      const sous = document.elementFromPoint(
        geste.x,
        Math.max(0, Math.min(innerHeight - 1, geste.y)),
      );
      const panneau = sous?.closest(".atelier-palette-defilante");
      const avant = panneau?.scrollTop;
      if (panneau) panneau.scrollTop += delta;
      if (!panneau || panneau.scrollTop === avant) window.scrollBy(0, delta);
    }
    actualiser();
    frame = requestAnimationFrame(defiler);
  };
  document.addEventListener("pointerdown", (e) => {
    if (!e.isPrimary || e.button !== 0 || geste) return;
    const poignee = e.target.closest("#atelier [data-atelier-source]");
    if (!poignee) return;
    geste = {
      id: e.pointerId,
      poignee,
      source: poignee.dataset.atelierSource,
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
        geste.poignee.setPointerCapture(e.pointerId);
        const modele = geste.poignee.closest(".mrjam-bloc") || geste.poignee;
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
        fantome.style.width = `${Math.min(400, Math.max(220, modele.getBoundingClientRect().width))}px`;
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
      const cible = geste.zone?.dataset.atelierCible;
      const source = geste.source;
      bloquerClic = true;
      setTimeout(() => {
        bloquerClic = false;
      }, 0);
      nettoyer();
      if (cible) envoyer({ type: "depot", source, cible });
    } else nettoyer();
  });
  document.addEventListener("pointercancel", nettoyer);
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
      if (bloquerClic) {
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
