export const Attribute = Object.freeze({
  None: 0,
  Bold: 1,
  Underline: 2,
  Reverse: 4,
  Blink: 8,
  Dim: 16,
  // Cursive and Italic are aliases in Termisu and share the same bit.
  Cursive: 32,
  Italic: 32,
  Hidden: 64,
  Strikethrough: 128,
} as const);

export type AttributeMask = number;

export function attrs(...flags: Array<number | undefined | null>): AttributeMask {
  let mask = 0;
  for (const flag of flags) {
    if (typeof flag === "number") {
      mask |= flag;
    }
  }
  return mask;
}
