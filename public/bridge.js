(() => {
  "use strict";
  class MathTex extends HTMLElement {
    static get observedAttributes() {
      return ["formula", "display-mode"];
    }
    connectedCallback() {
      this.render();
    }
    attributeChangedCallback() {
      if (this.isConnected) this.render();
    }
    render() {
      const formula = this.getAttribute("formula") || "";
      if (window.katex) {
        window.katex.render(formula, this, {
          displayMode: this.hasAttribute("display-mode"),
          throwOnError: false,
          strict: "warn",
          trust: false,
          output: "htmlAndMathml",
        });
      } else {
        this.textContent = formula;
      }
    }
  }
  if (!customElements.get("math-tex"))
    customElements.define("math-tex", MathTex);
  const course = window.courseData;
  if (!course || !window.Elm?.Main) {
    document.getElementById("app").textContent =
      "Le parcours n’a pas pu s’ouvrir. Rechargez la page pour réessayer.";
    return;
  }
  const app = window.Elm.Main.init({
    node: document.getElementById("app"),
    flags: course,
  });
  let latest = null;
  let sequence = 0;
  const pending = new Map();
  app.ports.reportState.subscribe((state) => {
    if (!state.error) latest = state;
    const entry = pending.get(state.requestId);
    if (!entry) return;
    pending.delete(state.requestId);
    clearTimeout(entry.timer);
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        if (state.error) entry.reject(new Error(state.error));
        else entry.resolve({ ...state, requestId: undefined });
      }),
    );
  });
  app.ports.focusElement.subscribe((id) =>
    requestAnimationFrame(() => {
      const target = document.getElementById(id);
      if (!target) return;
      target.focus({ preventScroll: true });
      if (id === "lesson-heading") {
        const top = target.getBoundingClientRect().top;
        if (top < 0 || top > innerHeight * 0.65)
          target.scrollIntoView({ block: "start", behavior: "auto" });
      } else if (id === "feedback") {
        const rect = target.getBoundingClientRect();
        if (rect.top > innerHeight - 100)
          target.scrollIntoView({
            block: "center",
            behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
              ? "auto"
              : "smooth",
          });
      }
    }),
  );
  const send = (payload) =>
    new Promise((resolve, reject) => {
      const requestId = String(++sequence);
      const timer = setTimeout(() => {
        pending.delete(requestId);
        reject(new Error("Le parcours ne répond pas."));
      }, 5000);
      pending.set(requestId, { resolve, reject, timer });
      app.ports.agentAction.send({ requestId, ...payload });
    });
  const context = document.modelContext;
  if (!context?.registerTool) return;
  const lifecycle = new AbortController();
  const register = (tool) => {
    try {
      Promise.resolve(
        context.registerTool(tool, { signal: lifecycle.signal }),
      ).catch((error) => console.warn("Outil du parcours indisponible", error));
    } catch (error) {
      console.warn("Outil du parcours indisponible", error);
    }
  };
  register({
    name: "read_learning_state",
    title: "Lire le parcours et l’exercice courant",
    description:
      "Lit les parcours disponibles et la question affichée, avec la réponse et le retour de la dernière vérification. Ne dévoile pas de corrigé à l’avance.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, untrustedContentHint: true },
    execute(input) {
      if (!input || typeof input !== "object" || Object.keys(input).length)
        throw new Error("Aucun paramètre attendu.");
      return {
        current: latest,
        tracks: course.tracks.map((t) => ({
          id: t.id,
          title: t.title,
          lessons: t.lessons.map((l) => ({
            id: l.id,
            title: l.title,
            steps: l.steps.length,
          })),
        })),
      };
    },
  });
  register({
    name: "open_learning_lesson",
    title: "Ouvrir une leçon",
    description:
      "Navigue vers une leçon et une étape. Cette action ne valide aucun exercice.",
    inputSchema: {
      type: "object",
      properties: {
        trackId: { type: "string" },
        lessonId: { type: "string" },
        step: { type: "integer", minimum: 1 },
      },
      required: ["trackId", "lessonId"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, untrustedContentHint: false },
    async execute(input) {
      if (
        !input ||
        typeof input !== "object" ||
        Object.keys(input).some(
          (k) => !["trackId", "lessonId", "step"].includes(k),
        )
      )
        throw new Error("Paramètres invalides.");
      const track = course.tracks.find((t) => t.id === input.trackId);
      const lesson = track?.lessons.find((l) => l.id === input.lessonId);
      const step = input.step ?? 1;
      if (
        !lesson ||
        !Number.isInteger(step) ||
        step < 1 ||
        step > lesson.steps.length
      )
        throw new Error("Leçon ou étape introuvable.");
      return send({
        action: "navigate",
        route: `#/${track.id}/${lesson.id}/${step}`,
      });
    },
  });
  register({
    name: "submit_learning_answer",
    title: "Vérifier une réponse",
    description:
      "Saisit et vérifie une réponse à la question affichée avec le même correcteur que l’interface. Pour un choix, passer son identifiant. Reste sur la question pour lire le retour.",
    inputSchema: {
      type: "object",
      properties: { answer: { type: "string", minLength: 1, maxLength: 500 } },
      required: ["answer"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, untrustedContentHint: true },
    async execute(input) {
      if (
        !input ||
        typeof input !== "object" ||
        Object.keys(input).some((k) => k !== "answer") ||
        typeof input.answer !== "string" ||
        !input.answer.trim() ||
        input.answer.length > 500
      )
        throw new Error("Une réponse de 1 à 500 caractères est attendue.");
      if (!latest || latest.page !== "exercice")
        throw new Error("Ouvrez d’abord un exercice.");
      if (
        latest.kind === "choice" &&
        !latest.choices.some((c) => c.id === input.answer)
      )
        throw new Error("Identifiant de réponse inconnu.");
      return send({ action: "answer", answer: input.answer });
    },
  });
  addEventListener(
    "pagehide",
    () => {
      lifecycle.abort();
      for (const entry of pending.values()) {
        clearTimeout(entry.timer);
        entry.reject(new Error("La page a été fermée."));
      }
      pending.clear();
    },
    { once: true },
  );
})();
