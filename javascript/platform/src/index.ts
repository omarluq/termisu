import { existsSync } from "node:fs";

export type PlatformTarget =
  | "linux-x64-gnu"
  | "linux-arm64-gnu"
  | "linux-x64-musl"
  | "linux-arm64-musl"
  | "darwin-x64"
  | "darwin-arm64"
  | "freebsd-x64"
  | "freebsd-arm64";

const MUSL_LOADER_BY_ARCH = {
  arm64: "/lib/ld-musl-aarch64.so.1",
  x64: "/lib/ld-musl-x86_64.so.1",
} as const;

type RuntimeReportHeader = {
  glibcVersionRuntime?: string;
};

type RuntimeReport = {
  header?: RuntimeReportHeader;
};

const NON_LINUX_TARGET_BY_KEY = {
  "darwin:arm64": "darwin-arm64",
  "darwin:x64": "darwin-x64",
  "freebsd:arm64": "freebsd-arm64",
  "freebsd:x64": "freebsd-x64",
} as const satisfies Partial<Record<`${NodeJS.Platform}:${NodeJS.Architecture}`, PlatformTarget>>;

const hasNonLinuxTarget = (targetKey: string): targetKey is keyof typeof NON_LINUX_TARGET_BY_KEY =>
  targetKey in NON_LINUX_TARGET_BY_KEY;

const isLinuxMusl = (arch: NodeJS.Architecture): boolean => {
  const report = process.report?.getReport?.() as RuntimeReport | undefined;
  const glibcVersion = report?.header?.glibcVersionRuntime;

  if (typeof glibcVersion === "string" && glibcVersion.length > 0) {
    return false;
  }

  const muslLoader = arch === "arm64" || arch === "x64" ? MUSL_LOADER_BY_ARCH[arch] : undefined;
  if (muslLoader) {
    return existsSync(muslLoader);
  }

  return false;
};

const detectLinuxTarget = (arch: NodeJS.Architecture): PlatformTarget | null => {
  const linuxTargetByArch = {
    arm64: isLinuxMusl(arch) ? "linux-arm64-musl" : "linux-arm64-gnu",
    x64: isLinuxMusl(arch) ? "linux-x64-musl" : "linux-x64-gnu",
  } as const satisfies Record<"arm64" | "x64", PlatformTarget>;

  return arch === "arm64" || arch === "x64" ? linuxTargetByArch[arch] : null;
};

export const detectTarget = (): PlatformTarget | null => {
  const platform = process.platform;
  const arch = process.arch;

  if (platform === "linux") {
    return detectLinuxTarget(arch);
  }

  const targetKey = `${platform}:${arch}`;
  return hasNonLinuxTarget(targetKey) ? NON_LINUX_TARGET_BY_KEY[targetKey] : null;
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
