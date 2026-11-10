type Listener = () => void;

class Events {
  #listeners = new Map<string, Listener[]>();

  addEventListener(type: string, listener: Listener) {
    this.#listeners.set(type, [...(this.#listeners.get(type) ?? []), listener]);
  }

  removeEventListener(type: string, listener: Listener) {
    this.#listeners.set(
      type,
      (this.#listeners.get(type) ?? []).filter((l) => l !== listener),
    );
  }

  protected emit(type: string) {
    for (const listener of this.#listeners.get(type) ?? []) listener();
  }
}

class FetchXMLHttpRequest extends Events {
  readonly upload = new Events();

  timeout = 0;
  responseType = "";
  withCredentials = false;

  status = 0;
  statusText = "";
  responseURL = "";
  response: unknown = null;

  #method = "GET";
  #url = "";
  #headers = new Headers();
  #responseHeaders = new Headers();
  #controller = new AbortController();

  open(method: string, url: string) {
    this.#method = method;
    this.#url = new URL(url).href;
  }

  setRequestHeader(name: string, value: string) {
    this.#headers.append(name, value);
  }

  getAllResponseHeaders() {
    return [...this.#responseHeaders].map(([name, value]) => `${name}: ${value}`).join("\r\n");
  }

  abort() {
    this.#controller.abort();
  }

  send(body?: RequestInit["body"]) {
    let timedOut = false;
    const timer =
      this.timeout > 0
        ? setTimeout(() => {
            timedOut = true;
            this.#controller.abort();
          }, this.timeout)
        : undefined;

    fetch(this.#url, {
      method: this.#method,
      headers: this.#headers,
      body: body ?? undefined,
      credentials: this.withCredentials ? "include" : "same-origin",
      signal: this.#controller.signal,
    })
      .then(async (res) => {
        this.status = res.status;
        this.statusText = res.statusText;
        this.responseURL = res.url;
        this.#responseHeaders = res.headers;
        this.response =
          this.responseType === "arraybuffer"
            ? await res.arrayBuffer()
            : this.responseType === "blob"
              ? await res.blob()
              : await res.text();
        clearTimeout(timer);
        this.emit("load");
      })
      .catch(() => {
        clearTimeout(timer);
        if (this.#controller.signal.aborted && !timedOut) return;
        this.emit(timedOut ? "timeout" : "error");
      });
  }
}

const scope = globalThis as { XMLHttpRequest?: unknown };
scope.XMLHttpRequest ??= FetchXMLHttpRequest;
