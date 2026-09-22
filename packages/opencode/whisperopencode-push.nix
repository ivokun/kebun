# @whisperopencode/push 0.3.0 — OpenCode plugin that publishes session
# completion events to a push-notification relay. The published entrypoint is
# V1-only, so this derivation replaces it with the reviewed V2 adapter before
# bundling the prebuilt relative modules.
#
# Deployed as a *local* plugin file (whisperopencode-push.js) so OpenCode
# never installs anything from the npm registry at startup. The plugin
# entry imports only relative modules and Node builtins, so neither npm
# dependencies nor runtime registry access are needed for the local plugin.
{
  esbuild,
  fetchzip,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "whisperopencode-push";
  version = "0.3.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@whisperopencode/push/-/push-0.3.0.tgz";
    hash = "sha256-JmORU12KeBJx11H9EuYOc0YLM0S3cv5n0rOdBch/IkI=";
  };

  postPatch = ''
    cp ${./whisperopencode-push-v2.js} dist/src/index.js
  '';

  # Stable store path for the plugin file; home/features/opencode.nix
  # deploys it as ~/.config/opencode/plugins/whisperopencode-push.js.
  nativeBuildInputs = [esbuild];
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    esbuild dist/src/index.js \
      --bundle --format=esm --platform=node \
      --outfile=whisperopencode-push.js

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 whisperopencode-push.js $out/whisperopencode-push.js

    runHook postInstall
  '';
}
