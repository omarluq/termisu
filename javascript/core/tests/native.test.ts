import { suffix } from "bun:ffi";
import { describe, expect, it } from "bun:test";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { ABI_VERSION } from "../src/constants";
import { loadNative, resolveLibraryPath, resolveNativePackageLibraryPath } from "../src/native";

function asNumber(value: number | bigint | undefined): number {
  if (value === undefined) {
    throw new Error("native symbol returned undefined");
  }
  return typeof value === "number" ? value : Number(value);
}

describe("native loader", () => {
  it("prefers an explicit library path during resolution", () => {
    const resolvedPath = resolveLibraryPath("./bin/libtermisu.test.so", {
      env: {},
      fileExists: () => false,
    });

    expect(resolvedPath).toBe(resolve("./bin/libtermisu.test.so"));
  });

  it("uses TERMISU_LIB_PATH when no explicit path is provided", () => {
    const envPath = resolveLibraryPath(undefined, {
      env: { TERMISU_LIB_PATH: "./bin/libtermisu.env.so" },
      fileExists: () => false,
    });

    expect(envPath).toBe(resolve("./bin/libtermisu.env.so"));
  });

  it("returns null when optional native package resolution throws", () => {
    const packagePath = resolveNativePackageLibraryPath({
      detectTarget: () => "linux-x64-gnu",
      resolveModule: () => {
        throw new Error("package not installed");
      },
    });

    expect(packagePath).toBeNull();
  });

  it("uses the resolved native package path when available", () => {
    const packageDir = "/tmp/termisu-native-package";
    const manifestUrl = pathToFileURL(`${packageDir}/manifest.json`).toString();
    const packageLibraryPath = resolve(`${packageDir}/libtermisu.${suffix}`);

    const resolvedPath = resolveLibraryPath(undefined, {
      cwd: "/tmp/termisu-project",
      detectTarget: () => "linux-x64-gnu",
      env: {},
      fileExists: (candidate) => candidate === packageLibraryPath,
      moduleUrl: pathToFileURL("/tmp/termisu-project/javascript/core/src/native.ts").toString(),
      resolveModule: () => manifestUrl,
    });

    expect(resolvedPath).toBe(packageLibraryPath);
  });

  it("raises an actionable error when no library path can be found", () => {
    expect(() =>
      resolveLibraryPath(undefined, {
        cwd: "/tmp/termisu-project",
        detectTarget: () => null,
        env: {},
        fileExists: () => false,
        moduleUrl: pathToFileURL("/tmp/termisu-project/javascript/core/src/native.ts").toString(),
      })
    ).toThrow(/Could not locate Termisu native library/);

    expect(() =>
      resolveLibraryPath(undefined, {
        cwd: "/tmp/termisu-project",
        detectTarget: () => null,
        env: {},
        fileExists: () => false,
        moduleUrl: pathToFileURL("/tmp/termisu-project/javascript/core/src/native.ts").toString(),
      })
    ).toThrow(/TERMISU_LIB_PATH/);
  });

  it("loads and caches native libraries by path", () => {
    const explicitPath = process.env.TERMISU_LIB_PATH;
    const a = loadNative(explicitPath);
    const b = loadNative(explicitPath);

    expect(a).toBe(b);
    if (explicitPath) {
      expect(a.path).toBe(resolve(explicitPath));
    }
  });

  it("evicts cache entry when close is called", () => {
    const explicitPath = process.env.TERMISU_LIB_PATH;
    const first = loadNative(explicitPath);
    first.close();

    const second = loadNative(explicitPath);
    expect(second).not.toBe(first);
    second.close();
  });

  it("exposes expected ABI and non-zero layout signature", () => {
    const native = loadNative(process.env.TERMISU_LIB_PATH);
    expect(asNumber(native.symbols.termisu_abi_version())).toBe(ABI_VERSION);

    const signature = native.symbols.termisu_layout_signature();
    const signatureBigint = typeof signature === "bigint" ? signature : BigInt(signature ?? 0);
    expect(signatureBigint > 0n).toBe(true);
  });
});
