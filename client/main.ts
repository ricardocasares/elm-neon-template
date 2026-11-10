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
    case "WriteToLocalStorage":
      try {
        return localStorage.setItem(msg.data.key, msg.data.value);
      } catch {
        return;
      }

    default:
      return msg.tag satisfies never;
  }
});
