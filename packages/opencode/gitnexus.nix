# GitNexus 1.6.12 — code-intelligence CLI and MCP server. Packed from the
# npm registry tarball; the committed lockfile pins the resolved dependency
# tree, and npmDepsHash pins its contents. Native modules (tree-sitter,
# onnxruntime, sharp, @ladybugdb/core) all ship linux-x64 prebuilds in their
# tarballs, so `npm ci --ignore-scripts` is enough — no install scripts run.
{
  buildNpmPackage,
  fetchzip,
  nodejs,
}:
buildNpmPackage {
  pname = "gitnexus";
  version = "1.6.12";

  src = fetchzip {
    url = "https://registry.npmjs.org/gitnexus/-/gitnexus-1.6.12.tgz";
    hash = "sha256-/Q3hcVrIt+jk/nCX7vcvBXM9fqFfQmcKXUq3Ldve4aA=";
  };

  # The npm tarball ships no lockfile; ours pins the resolved tree. The
  # tarball's devDependencies include a "file:../gitnexus-shared" spec and
  # its "overrides" section only applies when it is the install root —
  # npx runs it as a dependency, with both ignored. The committed lockfile
  # is generated from that same dependency perspective, so the tree npm ci
  # installs here is exactly the one npx used to run.
  postPatch = ''
    cp ${./gitnexus-package-lock.json} package-lock.json
    ${nodejs}/bin/node -e '
      const fs = require("fs");
      const p = JSON.parse(fs.readFileSync("package.json"));
      delete p.devDependencies;
      delete p.overrides;
      fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
    '
  '';

  npmDepsHash = "sha256-ZRy3pRGmQ8ZbmeHsj3V1IBsMtKn9YF3RP8Tonc1ad5w=";

  # dist/ and the vendored tree-sitter grammars ship prebuilt in the tarball.
  dontNpmBuild = true;

  # npm pack (used by the install hook to enumerate package files) runs
  # the "prepare" script by default; keep it inert like npm ci above.
  npmPackFlags = ["--ignore-scripts"];

  # npm rebuild runs packages' install scripts; onnxruntime-node's fetches
  # CUDA binaries from api.nuget.org. Unneeded: every native module ships
  # prebuilds for linux-x64 in its tarball.
  npmRebuildFlags = ["--ignore-scripts"];

  # @ladybugdb/core's install script copies the platform binary
  # (lbugjs.node) from the optional sub-package into the core package dir;
  # with --ignore-scripts it never ran, and the runtime copy would fail on
  # the read-only store. Do the same copy explicitly at install time.
  postInstall = ''
    core=$out/lib/node_modules/gitnexus/node_modules/@ladybugdb/core
    sub=$out/lib/node_modules/gitnexus/node_modules/@ladybugdb/core-linux-x64
    test -f "$sub/lbugjs.node"
    cp "$sub/lbugjs.node" "$core/lbugjs.node"
  '';

  meta.mainProgram = "gitnexus";
}
