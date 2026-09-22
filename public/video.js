(() => {
  "use strict";

  let sdkPromise;
  const positions = new Map();
  const clock = (seconds) =>
    `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    node.className = className;
    if (text) node.textContent = text;
    return node;
  };
  const loadVimeo = () => {
    if (window.Vimeo?.Player) return Promise.resolve(window.Vimeo.Player);
    if (!sdkPromise) {
      sdkPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        const timer = setTimeout(() => fail(), 12000);
        const fail = () => {
          clearTimeout(timer);
          script.remove();
          reject(new Error("Lecteur indisponible"));
        };
        script.src = "./vimeo/player.min.js";
        script.async = true;
        script.onload = () => {
          clearTimeout(timer);
          if (window.Vimeo?.Player) resolve(window.Vimeo.Player);
          else fail();
        };
        script.onerror = fail;
        document.head.append(script);
      }).catch((error) => {
        sdkPromise = undefined;
        throw error;
      });
    }
    return sdkPromise;
  };

  class CourseVideo extends HTMLElement {
    static get observedAttributes() {
      return ["src", "video-title", "poster", "start", "watch-url"];
    }

    connectedCallback() {
      this.showPoster();
    }

    attributeChangedCallback(oldName, oldValue, newValue) {
      if (!this.isConnected || oldValue === newValue || this.scheduled) return;
      this.scheduled = true;
      queueMicrotask(() => {
        this.scheduled = false;
        if (this.isConnected) this.showPoster();
      });
    }

    disconnectedCallback() {
      this.stop();
    }

    stop() {
      this.generation = (this.generation || 0) + 1;
      clearTimeout(this.timer);
      if (this.player) this.player.destroy().catch(() => {});
      this.player = null;
      this.removeAttribute("aria-busy");
    }

    showPoster() {
      this.stop();
      const frame = element("div", "video-poster");
      const poster = this.getAttribute("poster");
      // Aucun contact avec un hébergeur externe avant l'activation du lecteur.
      if (poster && new URL(poster, location.href).origin === location.origin) {
        const img = element("img", "video-poster-image");
        img.src = poster;
        img.alt = "";
        img.decoding = "async";
        img.loading = "lazy";
        frame.append(img);
      }
      const start = Number(this.getAttribute("start")) || 0;
      const key = `${this.getAttribute("src")}|${start}`;
      const saved = positions.get(key);
      const from = saved ?? start;
      const play = element("button", "video-play");
      play.type = "button";
      play.setAttribute(
        "aria-label",
        `${saved ? "Reprendre" : "Lire"} ${this.getAttribute("video-title")} à ${clock(from)}`,
      );
      const symbol = element("span", "video-play-symbol", "▶");
      symbol.setAttribute("aria-hidden", "true");
      play.append(
        symbol,
        element(
          "span",
          "video-play-label",
          saved
            ? `Reprendre à ${clock(from)}`
            : start
              ? `Regarder à partir de ${clock(start)}`
              : "Regarder la vidéo",
        ),
      );
      play.addEventListener("click", () => this.play(from, key));
      frame.append(play);
      if (from > 0) {
        const beginning = element(
          "button",
          "video-beginning",
          "Depuis le début",
        );
        beginning.type = "button";
        beginning.addEventListener("click", () => {
          positions.delete(key);
          this.play(0, key);
        });
        frame.append(beginning);
      }
      const information = element("p", "video-confidentialite", "Activer ce lecteur contacte l’hébergeur vidéo, qui reçoit votre adresse IP et peut utiliser des traceurs. Vous pouvez poursuivre les exercices sans l’activer.");
      information.id = "information-video";
      play.setAttribute("aria-describedby", information.id);
      this.replaceChildren(information, frame);
    }

    showError() {
      this.stop();
      const box = element("div", "video-fallback");
      box.setAttribute("role", "status");
      box.append(element("span", "video-proof-mark", "▷"));
      box.append(element("h3", "", "Retrouvez cette vidéo sur Vimeo"));
      box.append(
        element(
          "p",
          "",
          "La lecture intégrée est indisponible pour le moment. Vous pouvez regarder la vidéo sur Vimeo, puis revenir aux questions.",
        ),
      );
      const link = element("a", "primary", "Regarder sur Vimeo ↗");
      link.href = this.getAttribute("watch-url");
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      const retry = element("button", "quiet", "Réessayer ici");
      retry.type = "button";
      retry.addEventListener("click", () => {
        this.showPoster();
        this.querySelector("button")?.focus();
      });
      box.append(link, retry);
      this.replaceChildren(box);
      link.focus({ preventScroll: true });
    }

    async play(from, key) {
      this.stop();
      const generation = this.generation;
      const current = () => this.isConnected && this.generation === generation;
      const fail = () => {
        if (current()) this.showError();
      };
      this.setAttribute("aria-busy", "true");
      const loading = element("div", "video-loading", "Ouverture de la vidéo…");
      loading.setAttribute("role", "status");
      this.replaceChildren(loading);
      this.timer = setTimeout(fail, 15000);
      try {
        const url = new URL(this.getAttribute("src"));
        if (url.protocol !== "https:" || !["player.vimeo.com", "www.youtube-nocookie.com"].includes(url.hostname))
          throw new Error("Source vidéo invalide");
        const Player = url.hostname === "player.vimeo.com" ? await loadVimeo() : null;
        if (!current()) return;
        url.searchParams.set("autoplay", "1");
        url.searchParams.set("dnt", "1");
        url.hash = `t=${Math.floor(from)}s`;
        const iframe = document.createElement("iframe");
        iframe.title = this.getAttribute("video-title");
        iframe.src = url.href;
        iframe.allow =
          "autoplay; encrypted-media; picture-in-picture; fullscreen";
        iframe.allowFullscreen = true;
        iframe.referrerPolicy = "strict-origin-when-cross-origin";
        const arreter = element("button", "quiet", "Arrêter la vidéo");
        arreter.type = "button";
        arreter.addEventListener("click", () => { this.showPoster(); this.querySelector(".video-play")?.focus(); });
        this.replaceChildren(iframe, arreter);
        if (!Player) { clearTimeout(this.timer); this.removeAttribute("aria-busy"); iframe.focus(); return; }
        const player = new Player(iframe);
        this.player = player;
        player.on("timeupdate", ({ seconds }) => {
          if (current()) positions.set(key, seconds);
        });
        player.on("ended", () => {
          if (current()) positions.delete(key);
        });
        player.on("error", ({ name }) => {
          if (name === "PrivacyError") fail();
        });
        await player.ready();
        if (!current()) return;
        clearTimeout(this.timer);
        this.removeAttribute("aria-busy");
        iframe.focus({ preventScroll: true });
      } catch {
        fail();
      }
    }
  }

  if (!customElements.get("course-video"))
    customElements.define("course-video", CourseVideo);
})();
