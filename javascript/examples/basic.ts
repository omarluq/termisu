import { Attribute, Color, EventType, Termisu } from "../src/index";

const termisu = new Termisu({ syncUpdates: true });

try {
  termisu.clear();

  termisu.setCell(2, 1, "T", {
    fg: Color.green,
    attr: Attribute.Bold,
  });
  termisu.setCell(3, 1, "S", {
    fg: Color.green,
    attr: Attribute.Bold,
  });
  termisu.setCell(4, 1, "!", {
    fg: Color.cyan,
  });

  const message = "Press q to quit";
  for (let i = 0; i < message.length; i += 1) {
    termisu.setCell(2 + i, 3, message[i], {
      fg: Color.white,
    });
  }

  termisu.render();

  while (true) {
    const event = termisu.pollEvent(100);
    if (!event) continue;

    if (
      event.type === EventType.Key &&
      (event.keyChar === "q".codePointAt(0) || event.keyChar === "Q".codePointAt(0))
    ) {
      break;
    }
  }
} finally {
  termisu.destroy();
}
