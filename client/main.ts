import { Elm, type Flags } from "./Main.elm";

//-- FLAGS

const media = window.matchMedia("(prefers-color-scheme: dark)");
const getStoredTheme = () => {
  try {
    return (localStorage.getItem("theme") as Flags["theme"]) ?? null;
  } catch {
    return null;
  }
};

//-- INIT

const app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    theme: getStoredTheme(),
    systemDark: media.matches,
  },
});

//-- PORTS:SEND

media.addEventListener("change", (event) =>
  app.ports.interopToElm.send({
    tag: "SystemThemeChanged",
    dark: event.matches,
  }),
);

//-- PORTS:SUBSCRIBE

app.ports.interopFromElm.subscribe((msg) => {
  switch (msg.tag) {
    case "CopyToClipboard":
      return navigator.clipboard.writeText(msg.data).catch((error) =>
        app.ports.interopToElm.send({
          tag: "ClipboardError",
          message: String(error),
        }),
      );

    case "ReadFromLocalStorage":
      try {
        return localStorage.getItem(msg.data);
      } catch (error) {
        return app.ports.interopToElm.send({
          tag: "LocalStorageError",
          key: msg.data,
          message: String(error),
        });
      }

    case "WriteToLocalStorage":
      try {
        return localStorage.setItem(msg.data.key, msg.data.value);
      } catch (error) {
        return app.ports.interopToElm.send({
          tag: "LocalStorageError",
          key: msg.data.key,
          message: String(error),
        });
      }

    default:
      return msg satisfies never;
  }
});
