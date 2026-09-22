# Backport 1.12.2: includes the post-1.6 authority, URL, response, write, and
# schema hardening required before passing a live GitHub credential to it.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:
buildGoModule (finalAttrs: {
  pname = "github-mcp-server";
  version = "1.12.2";

  src = fetchFromGitHub {
    owner = "github";
    repo = "github-mcp-server";
    tag = "v${finalAttrs.version}";
    hash = "sha256-UCzRYbVLmMMC1LZeThhF8G8r4sFQdLIqSa5AxrisqgE=";
  };

  vendorHash = "sha256-dqn9W2gOb3ZCfppzfSczDO2bvpwsGyPe4I/h6y3JL9A=";

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${finalAttrs.version}"
    "-X=main.commit=${finalAttrs.src.rev}"
    "-X=main.date=1970-01-01T00:00:00Z"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [versionCheckHook];

  meta = {
    changelog = "https://github.com/github/github-mcp-server/releases/tag/v${finalAttrs.version}";
    description = "GitHub's official MCP Server";
    homepage = "https://github.com/github/github-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "github-mcp-server";
  };
})
