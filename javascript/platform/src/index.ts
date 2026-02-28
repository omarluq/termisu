export type PlatformTarget =
  | "linux-x64-gnu"
  | "linux-arm64-gnu"
  | "linux-x64-musl"
  | "linux-arm64-musl"
  | "darwin-x64"
  | "darwin-arm64"
  | "freebsd-x64"
  | "freebsd-arm64";

export const detectTarget = (): PlatformTarget | null => {
  const platform = process.platform;
  const arch = process.arch;

  if (platform === "linux" && arch === "x64") return "linux-x64-gnu";
  if (platform === "linux" && arch === "arm64") return "linux-arm64-gnu";
  if (platform === "darwin" && arch === "x64") return "darwin-x64";
  if (platform === "darwin" && arch === "arm64") return "darwin-arm64";
  if (platform === "freebsd" && arch === "x64") return "freebsd-x64";
  if (platform === "freebsd" && arch === "arm64") return "freebsd-arm64";

  return null;
};

export const nativePackageByTarget: Record<PlatformTarget, string> = {
  "linux-x64-gnu": "@termisu/native-linux-x64-gnu",
  "linux-arm64-gnu": "@termisu/native-linux-arm64-gnu",
  "linux-x64-musl": "@termisu/native-linux-x64-musl",
  "linux-arm64-musl": "@termisu/native-linux-arm64-musl",
  "darwin-x64": "@termisu/native-darwin-x64",
  "darwin-arm64": "@termisu/native-darwin-arm64",
  "freebsd-x64": "@termisu/native-freebsd-x64",
  "freebsd-arm64": "@termisu/native-freebsd-arm64",
};
